#pragma once

#include <QByteArray>
#include <QString>
#include <QStringList>
#include <functional>

// The files of a phone, as Legato's sync sees them: the `Legato/` folder of docs/sync.md and what is in it. Paths are relative to that
// folder ("manifest.json", "Music/3f2a….flac"). An iPhone is reached over AFC (IPhoneStorage), an Android phone over MTP
// (AndroidStorage). Each call blocks; the sync runs them on a thread of its own. Calls that can fail return false and leave why in
// error().
class DeviceStorage {
public:
    virtual ~DeviceStorage() = default;

    // the device's name ("Jacob's iPhone"), once open
    virtual QString name() const = 0;
    // bytes free on the device, or -1 if it won't say
    virtual qint64 freeSpace() = 0;

    // the names of the files in a folder ("Music"), which is created if it isn't there
    virtual bool list(const QString &dir, QStringList *names) = 0;
    // a small file's contents (the manifest); false when it isn't there or can't be read
    virtual bool read(const QString &path, QByteArray *data) = 0;
    // a local file onto the device, over anything already at path. progress(bytes sent so far) may be called as it goes; returning false
    // from it stops the copy.
    virtual bool upload(const QString &localPath, const QString &path, const std::function<bool(qint64)> &progress) = 0;
    virtual bool write(const QString &path, const QByteArray &data) = 0;
    // rename over anything already at to
    virtual bool rename(const QString &from, const QString &to) = 0;
    virtual bool remove(const QString &path) = 0;

    QString error() const { return m_error; }

protected:
    bool fail(const QString &why) { m_error = why; return false; }
    QString m_error;
};
