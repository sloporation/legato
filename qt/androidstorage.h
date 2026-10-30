#pragma once

#include "devicestorage.h"

#include <QHash>

struct LIBMTP_mtpdevice_struct;

// An Android phone on USB, as it shows itself to computers: MTP (the phone's USB setting "File transfer"), with libmtp. The music goes
// in Music/Legato on its main storage, where Legato for Android reads it.
class AndroidStorage : public DeviceStorage {
public:
    ~AndroidStorage() override;

    // the MTP devices on USB, as "bus:device" (which is how libmtp finds one again)
    static QStringList connected();

    // takes the phone (only one program at a time can) and finds Music/Legato; false says why not
    bool open(const QString &where);
    // the phone's serial number: what tells it apart from another
    QString serial() const { return m_serial; }

    QString name() const override { return m_name; }
    qint64 freeSpace() override;
    bool list(const QString &dir, QStringList *names) override;
    bool read(const QString &path, QByteArray *data) override;
    bool upload(const QString &localPath, const QString &path, const std::function<bool(qint64)> &progress) override;
    bool write(const QString &path, const QByteArray &data) override;
    bool rename(const QString &from, const QString &to) override;
    bool remove(const QString &path) override;

private:
    // the folder's id, made if need be ("" is Legato itself)
    quint32 folder(const QString &dir);
    // what is in a folder: name → id (kept, and changed as files come and go)
    QHash<QString, quint32> *contents(quint32 folder);
    // the file's folder and id (0 if it isn't there)
    quint32 find(const QString &path, quint32 *parent);
    bool mtpFailed(const QString &what);
    void close();

    LIBMTP_mtpdevice_struct *m_device = nullptr;
    quint32 m_storage = 0;
    quint32 m_legato = 0;
    QHash<QString, quint32> m_folders;                  // "Music" → its id
    QHash<quint32, QHash<QString, quint32>> m_contents;
    QString m_name, m_serial;
};
