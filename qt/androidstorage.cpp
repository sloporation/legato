#include "androidstorage.h"

#include <QFile>
#include <QFileInfo>
#include <QTemporaryFile>

#include <libmtp.h>

namespace {

void initOnce()
{
    static const bool done = [] { LIBMTP_Init(); return true; }();
    Q_UNUSED(done);
}

QString takeString(char *s)
{
    const QString out = QString::fromUtf8(s ? s : "");
    free(s);
    return out;
}

struct ProgressHook {
    const std::function<bool(qint64)> *progress;
};

int onProgress(uint64_t sent, uint64_t, void const *const data)
{
    const auto *hook = static_cast<const ProgressHook *>(data);
    return (*hook->progress)(qint64(sent)) ? 0 : 1;     // non-zero stops the transfer
}

} // namespace

AndroidStorage::~AndroidStorage()
{
    close();
}

void AndroidStorage::close()
{
    if (m_device)
        LIBMTP_Release_Device(m_device);
    m_device = nullptr;
    m_folders.clear();
    m_contents.clear();
}

QStringList AndroidStorage::connected()
{
    initOnce();
    QStringList found;
    LIBMTP_raw_device_t *raw = nullptr;
    int count = 0;
    if (LIBMTP_Detect_Raw_Devices(&raw, &count) != LIBMTP_ERROR_NONE)
        return found;
    for (int i = 0; i < count; ++i)
        if (raw[i].device_entry.vendor_id != 0x05ac)     // an iPhone offers its photos as PTP: not this
            found << QString("%1:%2").arg(raw[i].bus_location).arg(raw[i].devnum);
    free(raw);
    return found;
}

bool AndroidStorage::open(const QString &where)
{
    initOnce();
    close();
    LIBMTP_raw_device_t *raw = nullptr;
    int count = 0;
    if (LIBMTP_Detect_Raw_Devices(&raw, &count) != LIBMTP_ERROR_NONE)
        return fail(QObject::tr("The phone isn't connected"));
    for (int i = 0; i < count && !m_device; ++i)
        if (QString("%1:%2").arg(raw[i].bus_location).arg(raw[i].devnum) == where)
            m_device = LIBMTP_Open_Raw_Device_Uncached(&raw[i]);
    free(raw);
    if (!m_device)
        return fail(QObject::tr("Couldn't open the phone. If another app is using it (Android File Transfer, a photos app), quit it."));

    m_name = takeString(LIBMTP_Get_Friendlyname(m_device));
    if (m_name.isEmpty())
        m_name = takeString(LIBMTP_Get_Modelname(m_device));
    if (m_name.isEmpty())
        m_name = QObject::tr("Android phone");
    m_serial = takeString(LIBMTP_Get_Serialnumber(m_device));
    if (m_serial.isEmpty())
        m_serial = where;

    if (LIBMTP_Get_Storage(m_device, LIBMTP_STORAGE_SORTBY_NOTSORTED) != 0 || !m_device->storage)
        return fail(QObject::tr("The phone isn't sharing its files"));
    m_storage = m_device->storage->id;     // the first is the phone's own

    // Music, then Legato in it
    quint32 music = contents(LIBMTP_FILES_AND_FOLDERS_ROOT)->value("Music");
    if (!music) {
        music = LIBMTP_Create_Folder(m_device, const_cast<char *>("Music"), LIBMTP_FILES_AND_FOLDERS_ROOT, m_storage);
        if (!music)
            return mtpFailed(QObject::tr("Couldn't make the Music folder on the phone"));
        m_contents[LIBMTP_FILES_AND_FOLDERS_ROOT].insert("Music", music);
    }
    m_legato = contents(music)->value("Legato");
    if (!m_legato) {
        m_legato = LIBMTP_Create_Folder(m_device, const_cast<char *>("Legato"), music, m_storage);
        if (!m_legato)
            return mtpFailed(QObject::tr("Couldn't make Music/Legato on the phone"));
        m_contents[music].insert("Legato", m_legato);
    }
    m_folders.insert("", m_legato);
    return true;
}

bool AndroidStorage::mtpFailed(const QString &what)
{
    QString detail;
    if (m_device) {
        for (LIBMTP_error_t *e = LIBMTP_Get_Errorstack(m_device); e; e = e->next)
            if (e->error_text)
                detail = QString::fromUtf8(e->error_text).trimmed();
        LIBMTP_Clear_Errorstack(m_device);
    }
    return fail(detail.isEmpty() ? what : what + " (" + detail + ")");
}

QHash<QString, quint32> *AndroidStorage::contents(quint32 folder)
{
    auto it = m_contents.find(folder);
    if (it != m_contents.end())
        return &it.value();
    QHash<QString, quint32> names;
    for (LIBMTP_file_t *f = LIBMTP_Get_Files_And_Folders(m_device, m_storage, folder); f;) {
        names.insert(QString::fromUtf8(f->filename), f->item_id);
        LIBMTP_file_t *next = f->next;
        LIBMTP_destroy_file_t(f);
        f = next;
    }
    LIBMTP_Clear_Errorstack(m_device);
    return &m_contents.insert(folder, names).value();
}

quint32 AndroidStorage::folder(const QString &dir)
{
    if (m_folders.contains(dir))
        return m_folders.value(dir);
    const int slash = dir.lastIndexOf('/');
    const quint32 parent = folder(slash < 0 ? QString() : dir.left(slash));
    if (!parent)
        return 0;
    const QString name = dir.mid(slash + 1);
    quint32 id = contents(parent)->value(name);
    if (!id) {
        QByteArray utf8 = name.toUtf8();
        id = LIBMTP_Create_Folder(m_device, utf8.data(), parent, m_storage);
        if (!id) {
            mtpFailed(QObject::tr("Couldn't make a folder on the phone"));
            return 0;
        }
        contents(parent)->insert(name, id);
    }
    m_folders.insert(dir, id);
    return id;
}

quint32 AndroidStorage::find(const QString &path, quint32 *parent)
{
    const int slash = path.lastIndexOf('/');
    *parent = folder(slash < 0 ? QString() : path.left(slash));
    return *parent ? contents(*parent)->value(path.mid(slash + 1)) : 0;
}

qint64 AndroidStorage::freeSpace()
{
    LIBMTP_Get_Storage(m_device, LIBMTP_STORAGE_SORTBY_NOTSORTED);     // (fresh numbers)
    for (LIBMTP_devicestorage_t *s = m_device->storage; s; s = s->next)
        if (s->id == m_storage)
            return qint64(s->FreeSpaceInBytes);
    return -1;
}

bool AndroidStorage::list(const QString &dir, QStringList *names)
{
    const quint32 id = folder(dir);
    if (!id)
        return false;
    *names = contents(id)->keys();
    return true;
}

bool AndroidStorage::read(const QString &path, QByteArray *data)
{
    quint32 parent = 0;
    const quint32 id = find(path, &parent);
    if (!id)
        return fail(QObject::tr("%1 isn't there").arg(path));
    QTemporaryFile temp;
    if (!temp.open())
        return fail(temp.errorString());
    if (LIBMTP_Get_File_To_File_Descriptor(m_device, id, temp.handle(), nullptr, nullptr) != 0)
        return mtpFailed(QObject::tr("Couldn't read %1 from the phone").arg(path));
    temp.seek(0);
    *data = temp.readAll();
    return true;
}

bool AndroidStorage::upload(const QString &localPath, const QString &path, const std::function<bool(qint64)> &progress)
{
    quint32 parent = 0;
    const quint32 existing = find(path, &parent);
    if (!parent)
        return false;
    if (existing && !remove(path))     // MTP makes a second file of the same name rather than replace it
        return false;
    const QString name = path.mid(path.lastIndexOf('/') + 1);
    LIBMTP_file_t *file = LIBMTP_new_file_t();
    file->filename = strdup(name.toUtf8().constData());
    file->filesize = uint64_t(QFileInfo(localPath).size());
    file->filetype = LIBMTP_FILETYPE_UNKNOWN;
    file->parent_id = parent;
    file->storage_id = m_storage;
    ProgressHook hook { &progress };
    const int e = LIBMTP_Send_File_From_File(m_device, QFile::encodeName(localPath).constData(), file, onProgress, &hook);
    const quint32 id = file->item_id;
    LIBMTP_destroy_file_t(file);
    if (e != 0)
        return mtpFailed(QObject::tr("Couldn't copy to the phone"));
    contents(parent)->insert(name, id);
    return true;
}

bool AndroidStorage::write(const QString &path, const QByteArray &data)
{
    QTemporaryFile temp;
    if (!temp.open() || temp.write(data) != data.size() || !temp.flush())
        return fail(temp.errorString());
    const std::function<bool(qint64)> any = [](qint64) { return true; };
    return upload(temp.fileName(), path, any);
}

bool AndroidStorage::rename(const QString &from, const QString &to)
{
    quint32 parent = 0;
    const quint32 id = find(from, &parent);
    if (!id)
        return fail(QObject::tr("%1 isn't there").arg(from));
    quint32 toParent = 0;
    if (find(to, &toParent) && !remove(to))
        return false;
    LIBMTP_file_t *file = LIBMTP_Get_Filemetadata(m_device, id);
    if (!file)
        return mtpFailed(QObject::tr("Couldn't rename a file on the phone"));
    const QString name = to.mid(to.lastIndexOf('/') + 1);
    const int e = LIBMTP_Set_File_Name(m_device, file, name.toUtf8().constData());
    LIBMTP_destroy_file_t(file);
    if (e != 0)
        return mtpFailed(QObject::tr("Couldn't rename a file on the phone"));
    contents(parent)->remove(from.mid(from.lastIndexOf('/') + 1));
    contents(parent)->insert(name, id);
    return true;
}

bool AndroidStorage::remove(const QString &path)
{
    quint32 parent = 0;
    const quint32 id = find(path, &parent);
    if (!id)
        return true;
    if (LIBMTP_Delete_Object(m_device, id) != 0)
        return mtpFailed(QObject::tr("Couldn't delete a file on the phone"));
    contents(parent)->remove(path.mid(path.lastIndexOf('/') + 1));
    return true;
}
