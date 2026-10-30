#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QThread>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>
#include <atomic>

#include "sync.h"

class Library;

// Looks for phones on USB from a thread of its own, and syncs them there. (A class of its own so it can live on that thread.)
class DeviceWorker : public QObject {
    Q_OBJECT
public:
    std::atomic<bool> stop { false };     // set from the window's thread to stop a sync

public slots:
    void poll();
    void sync(const QString &id, const SyncJob &job);

signals:
    void seen(const QVariantMap &device);
    void gone(const QString &id);
    void progress(const QString &id, qint64 done, qint64 total, const QString &what);
    void synced(const QString &id, const QVariantMap &result);

private:
    QVariantMap look(const QString &id);     // open the phone: its name, whether it can be synced, what was chosen for it
    QHash<QString, QVariantMap> m_known;
};
Q_DECLARE_METATYPE(SyncJob)

// The phones on USB, for QML as the `Devices` singleton, and putting music on them (docs/sync.md). What goes on a phone is chosen on its
// page: everything, or some playlists, artists and albums. The choice is kept on the phone, in its manifest, and syncing copies what is
// new or changed and deletes what is no longer chosen.
class Devices : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // [{ id, kind: "iphone"|"android", name, status: "ready"|"trust"|"locked"|"noapp"|"error", message, free (bytes, -1 unknown),
    //    chosen: { everything, playlists: [names], artists: [names], albums: [keys] }, syncing, done, total (bytes), what, result }]
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
public:
    explicit Devices(Library *library, QObject *parent = nullptr);
    ~Devices() override;
    static Devices *create(QQmlEngine *qml, QJSEngine *js);

    QVariantList devices() const { return m_devices; }

    // what the phone is to have; kept until it's synced (and then on the phone)
    Q_INVOKABLE void choose(const QString &id, const QVariantMap &chosen);
    // what a choice comes to on that kind of phone: { songs, bytes, unplayable }
    Q_INVOKABLE QVariantMap measure(const QString &kind, const QVariantMap &chosen) const;
    Q_INVOKABLE void sync(const QString &id);
    Q_INVOKABLE void stopSync();

signals:
    void devicesChanged();
    void synced(const QString &name, const QString &message);

private:
    SyncJob job(const QString &kind, const QVariantMap &chosen) const;
    int indexOf(const QString &id) const;
    void update(const QString &id, const QVariantMap &changes);

    Library *m_library;
    QVariantList m_devices;
    QThread m_thread;
    DeviceWorker *m_worker;
};
