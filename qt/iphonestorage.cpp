#include "iphonestorage.h"

#include <QFile>

#include <libimobiledevice/lockdown.h>
#include <plist/plist.h>

namespace {

const char *const appId = "com.sloporation.legato";
const char *const label = "legato";

} // namespace

IPhoneStorage::~IPhoneStorage()
{
    close();
}

void IPhoneStorage::close()
{
    if (m_afc)
        afc_client_free(m_afc);
    if (m_houseArrest)
        house_arrest_client_free(m_houseArrest);
    if (m_device)
        idevice_free(m_device);
    m_afc = nullptr;
    m_houseArrest = nullptr;
    m_device = nullptr;
}

QStringList IPhoneStorage::connected()
{
    QStringList udids;
    idevice_info_t *list = nullptr;
    int count = 0;
    if (idevice_get_device_list_extended(&list, &count) != IDEVICE_E_SUCCESS)
        return udids;     // usbmuxd isn't running (Linux without it installed; Windows without Apple's drivers)
    for (int i = 0; i < count; ++i)
        if (list[i]->conn_type == CONNECTION_USBMUXD && !udids.contains(QString::fromUtf8(list[i]->udid)))     // USB only
            udids << QString::fromUtf8(list[i]->udid);
    idevice_device_list_extended_free(list);
    return udids;
}

IPhoneStorage::Status IPhoneStorage::open(const QString &udid)
{
    close();
    if (idevice_new_with_options(&m_device, udid.toUtf8().constData(), IDEVICE_LOOKUP_USBMUX) != IDEVICE_E_SUCCESS) {
        fail(QObject::tr("The iPhone isn't connected"));
        return Unreachable;
    }

    lockdownd_client_t lockdown = nullptr;
    const lockdownd_error_t e = lockdownd_client_new_with_handshake(m_device, &lockdown, label);
    switch (e) {
    case LOCKDOWN_E_SUCCESS:
        break;
    case LOCKDOWN_E_PAIRING_DIALOG_RESPONSE_PENDING:
    case LOCKDOWN_E_USER_DENIED_PAIRING:
    case LOCKDOWN_E_INVALID_HOST_ID:
        fail(QObject::tr("Tap Trust on the iPhone"));
        return NotTrusted;
    case LOCKDOWN_E_PASSWORD_PROTECTED:
        fail(QObject::tr("Unlock the iPhone"));
        return Locked;
    default:
        fail(QObject::tr("Couldn't talk to the iPhone (lockdown error %1)").arg(int(e)));
        return Unreachable;
    }
    char *name = nullptr;
    if (lockdownd_get_device_name(lockdown, &name) == LOCKDOWN_E_SUCCESS && name) {
        m_name = QString::fromUtf8(name);
        free(name);
    }
    lockdownd_client_free(lockdown);

    if (house_arrest_client_start_service(m_device, &m_houseArrest, label) != HOUSE_ARREST_E_SUCCESS) {
        fail(QObject::tr("Couldn't open the iPhone's app folders"));
        return Unreachable;
    }
    plist_t answer = nullptr;
    if (house_arrest_send_command(m_houseArrest, "VendDocuments", appId) != HOUSE_ARREST_E_SUCCESS
        || house_arrest_get_result(m_houseArrest, &answer) != HOUSE_ARREST_E_SUCCESS) {
        fail(QObject::tr("Couldn't open Legato's folder on the iPhone"));
        return Unreachable;
    }
    const bool refused = plist_dict_get_item(answer, "Error") != nullptr;
    plist_free(answer);
    if (refused) {
        fail(QObject::tr("Install Legato on the iPhone first"));
        return NoApp;
    }
    if (afc_client_new_from_house_arrest_client(m_houseArrest, &m_afc) != AFC_E_SUCCESS) {
        fail(QObject::tr("Couldn't open Legato's folder on the iPhone"));
        return Unreachable;
    }
    return Ready;
}

QByteArray IPhoneStorage::full(const QString &path) const
{
    return ("/Documents/Legato/" + path).toUtf8();
}

bool IPhoneStorage::check(afc_error_t e, const char *what)
{
    if (e == AFC_E_SUCCESS)
        return true;
    return fail(QObject::tr("%1 failed (AFC error %2)").arg(QString::fromUtf8(what)).arg(int(e)));
}

bool IPhoneStorage::made(const QString &dir)
{
    // (making a folder that is there is not an error)
    return check(afc_make_directory(m_afc, full(dir).constData()), "Making a folder");
}

qint64 IPhoneStorage::freeSpace()
{
    char *value = nullptr;
    if (afc_get_device_info_key(m_afc, "FSFreeBytes", &value) != AFC_E_SUCCESS || !value)
        return -1;
    const qint64 bytes = QByteArray(value).toLongLong();
    free(value);
    return bytes;
}

bool IPhoneStorage::list(const QString &dir, QStringList *names)
{
    if (!made(dir))
        return false;
    char **entries = nullptr;
    if (!check(afc_read_directory(m_afc, full(dir).constData(), &entries), "Listing a folder"))
        return false;
    names->clear();
    for (char **e = entries; e && *e; ++e) {
        const QString name = QString::fromUtf8(*e);
        if (name != "." && name != "..")
            *names << name;
    }
    afc_dictionary_free(entries);
    return true;
}

bool IPhoneStorage::read(const QString &path, QByteArray *data)
{
    uint64_t handle = 0;
    if (afc_file_open(m_afc, full(path).constData(), AFC_FOPEN_RDONLY, &handle) != AFC_E_SUCCESS)
        return fail(QObject::tr("%1 isn't there").arg(path));
    data->clear();
    char buffer[65536];
    uint32_t got = 0;
    while (afc_file_read(m_afc, handle, buffer, sizeof buffer, &got) == AFC_E_SUCCESS && got > 0)
        data->append(buffer, int(got));
    afc_file_close(m_afc, handle);
    return true;
}

bool IPhoneStorage::upload(const QString &localPath, const QString &path, const std::function<bool(qint64)> &progress)
{
    QFile file(localPath);
    if (!file.open(QIODevice::ReadOnly))
        return fail(file.errorString());
    uint64_t handle = 0;
    if (!check(afc_file_open(m_afc, full(path).constData(), AFC_FOPEN_WR, &handle), "Opening a file on the iPhone"))
        return false;
    qint64 sent = 0;
    QByteArray chunk;
    bool ok = true;
    while (ok && !(chunk = file.read(1 << 20)).isEmpty()) {
        const char *at = chunk.constData();
        qint64 left = chunk.size();
        while (left > 0) {
            uint32_t written = 0;
            if (!check(afc_file_write(m_afc, handle, at, uint32_t(left), &written), "Writing to the iPhone") || written == 0) {
                ok = false;
                break;
            }
            at += written;
            left -= written;
            sent += written;
        }
        if (ok && !progress(sent))
            ok = fail(QObject::tr("Stopped"));
    }
    afc_file_close(m_afc, handle);
    return ok;
}

bool IPhoneStorage::write(const QString &path, const QByteArray &data)
{
    uint64_t handle = 0;
    if (!check(afc_file_open(m_afc, full(path).constData(), AFC_FOPEN_WR, &handle), "Opening a file on the iPhone"))
        return false;
    const char *at = data.constData();
    qint64 left = data.size();
    bool ok = true;
    while (left > 0) {
        uint32_t written = 0;
        if (!check(afc_file_write(m_afc, handle, at, uint32_t(left), &written), "Writing to the iPhone") || written == 0) {
            ok = false;
            break;
        }
        at += written;
        left -= written;
    }
    afc_file_close(m_afc, handle);
    return ok;
}

bool IPhoneStorage::rename(const QString &from, const QString &to)
{
    return check(afc_rename_path(m_afc, full(from).constData(), full(to).constData()), "Renaming a file on the iPhone");
}

bool IPhoneStorage::remove(const QString &path)
{
    const afc_error_t e = afc_remove_path(m_afc, full(path).constData());
    return e == AFC_E_OBJECT_NOT_FOUND || check(e, "Deleting a file on the iPhone");
}
