#include "settings.h"

#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>

Settings::Settings(QObject *parent)
    : QObject(parent)
{
    if (legato_config_load(&m_config) != 0)
        qWarning() << "legato: could not load config from" << configPath();

    m_reloadTimer.setSingleShot(true);
    m_reloadTimer.setInterval(200);
    connect(&m_reloadTimer, &QTimer::timeout, this, &Settings::reload);
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(500);
    connect(&m_saveTimer, &QTimer::timeout, this, &Settings::save);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_reloadTimer, qOverload<>(&QTimer::start));
    // editors often save by replacing the file, which drops it from the watch: the folder notices it coming back
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_reloadTimer, qOverload<>(&QTimer::start));
    watch();
}

void Settings::watch()
{
    const QString path = configPath();
    if (path.isEmpty())
        return;
    if (!m_watcher.files().contains(path) && QFileInfo::exists(path))
        m_watcher.addPath(path);
    const QString dir = QFileInfo(path).absolutePath();
    if (!m_watcher.directories().contains(dir) && QFileInfo::exists(dir))
        m_watcher.addPath(dir);
}

QString Settings::configPath() const
{
    char path[LEGATO_PATH_MAX];
    return legato_config_path(path, sizeof path) == 0 ? QString::fromUtf8(path) : QString();
}

QStringList Settings::musicDirs() const
{
    QStringList dirs;
    for (int i = 0; i < m_config.music_dir_count; i++)
        dirs << QString::fromUtf8(m_config.music_dirs[i]);
    return dirs;
}

int Settings::volume() const
{
    return m_config.volume;
}

void Settings::setVolume(int volume)
{
    volume = qBound(0, volume, 100);
    if (volume == m_config.volume)
        return;
    m_config.volume = volume;
    m_saveTimer.start();
    emit volumeChanged();
}

bool Settings::addMusicDir(const QUrl &dir)
{
    const QString path = QDir::cleanPath(dir.isLocalFile() ? dir.toLocalFile() : dir.toString());
    if (path.isEmpty() || !QFileInfo(path).isDir()) {
        emit failed(tr("“%1” is not a folder.").arg(path));
        return false;
    }
    const int rc = legato_config_add_dir(&m_config, QDir::toNativeSeparators(path).toUtf8().constData());
    if (rc < 0) {
        emit failed(tr("Legato can look after at most %1 folders.").arg(LEGATO_DIRS_MAX));
        return false;
    }
    if (rc == 0) {
        save();
        emit musicDirsChanged();
    }
    return true;
}

void Settings::removeMusicDir(int index)
{
    if (legato_config_remove_dir(&m_config, index) != 0)
        return;
    save();
    emit musicDirsChanged();
}

void Settings::openConfigFile() const
{
    QDesktopServices::openUrl(QUrl::fromLocalFile(configPath()));
}

void Settings::reload()
{
    if (m_saveTimer.isActive())     // our own change, not yet written: the file is out of date, not the settings
        return;
    const QStringList dirs = musicDirs();
    const int vol = volume();
    legato_config next;
    if (legato_config_load(&next) != 0) {
        // half-written, or a typo: keep what we have until the file makes sense again
        qWarning() << "legato: could not read" << configPath() << "- keeping the current settings";
        watch();
        return;
    }
    m_config = next;
    watch();
    if (musicDirs() != dirs)
        emit musicDirsChanged();
    if (volume() != vol)
        emit volumeChanged();
}

void Settings::save()
{
    if (legato_config_save(&m_config) != 0) {
        qWarning() << "legato: could not save config to" << configPath();
        emit failed(tr("Could not save the settings to %1.").arg(configPath()));
    }
    watch();
}
