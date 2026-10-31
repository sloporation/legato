#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QStringList>

// Says when something changed somewhere under the music folders, so the library can look again. It does not say what changed: a rescan
// with the tag cache is cheap, and working out the difference here would only duplicate it.
//
// macOS: one FSEvents stream over the folders, which sees the whole tree and coalesces bursts by itself.
// Elsewhere: a QFileSystemWatcher on every folder in the tree (inotify on Linux, which has no recursive watch), handed the list by the scan.
class FolderWatcher : public QObject {
    Q_OBJECT
public:
    explicit FolderWatcher(QObject *parent = nullptr);
    ~FolderWatcher() override;

    // the music folders, and (where watching is per folder) every folder under them
    void watch(const QStringList &roots, const QStringList &subfolders);

signals:
    void changed();

private:
    void stop();

#ifdef Q_OS_MACOS
    void *m_stream = nullptr;      // FSEventStreamRef
    QStringList m_roots;
#else
    QFileSystemWatcher m_watcher;
#endif
};
