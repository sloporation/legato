#pragma once

#include "devicestorage.h"

#include <libimobiledevice/afc.h>
#include <libimobiledevice/house_arrest.h>
#include <libimobiledevice/libimobiledevice.h>

// An iPhone on USB, reached through usbmuxd (the system service Finder and Xcode use) with libimobiledevice: its Legato app's Documents
// folder, over AFC by way of house_arrest, as Finder's file sharing does. The phone has to trust the computer once, and Legato has to
// be installed on it (it sets UIFileSharingEnabled, which is what lets the folder be opened).
class IPhoneStorage : public DeviceStorage {
public:
    enum Status { Ready, NotTrusted, Locked, NoApp, Unreachable };

    ~IPhoneStorage() override;

    // the iPhones (and iPads) on USB, by UDID
    static QStringList connected();

    // reaches the phone and opens Legato's folder; anything but Ready says what is in the way (and the phone shows "Trust This
    // Computer?" when NotTrusted)
    Status open(const QString &udid);

    QString name() const override { return m_name; }
    qint64 freeSpace() override;
    bool list(const QString &dir, QStringList *names) override;
    bool read(const QString &path, QByteArray *data) override;
    bool upload(const QString &localPath, const QString &path, const std::function<bool(qint64)> &progress) override;
    bool write(const QString &path, const QByteArray &data) override;
    bool rename(const QString &from, const QString &to) override;
    bool remove(const QString &path) override;

private:
    QByteArray full(const QString &path) const;     // under /Documents/Legato
    bool made(const QString &dir);                  // the folder (and the ones above it) exists
    bool check(afc_error_t e, const char *what);
    void close();

    idevice_t m_device = nullptr;
    house_arrest_client_t m_houseArrest = nullptr;
    afc_client_t m_afc = nullptr;
    QString m_name;
};
