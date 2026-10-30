#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

extern "C" {
#include "config.h"
}

// The desktop client's settings (legato.yaml, read and written by core/config.c), for QML as the `Settings` singleton.
// Changes made in the window are saved at once. The file is watched, so an edit made by hand is picked up too.
class Settings : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString configPath READ configPath CONSTANT)
    Q_PROPERTY(QStringList musicDirs READ musicDirs NOTIFY musicDirsChanged)
    Q_PROPERTY(int volume READ volume WRITE setVolume NOTIFY volumeChanged)
public:
    explicit Settings(QObject *parent = nullptr);

    QString configPath() const;
    QStringList musicDirs() const;
    int volume() const;
    void setVolume(int volume);

    // a folder from a FolderDialog (a file: URL) or a plain path
    Q_INVOKABLE bool addMusicDir(const QUrl &dir);
    Q_INVOKABLE void removeMusicDir(int index);
    Q_INVOKABLE void openConfigFile() const;     // in the system's editor for .yaml
    Q_INVOKABLE void reload();

signals:
    void musicDirsChanged();
    void volumeChanged();
    void failed(const QString &message);

private:
    void save();
    void watch();

    legato_config m_config;
    QFileSystemWatcher m_watcher;
    QTimer m_reloadTimer;     // an editor may write the file in several steps: wait for it to settle
    QTimer m_saveTimer;       // a dragged volume slider changes it many times a second: save once it rests
};
