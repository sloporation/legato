#include "folderwatcher.h"

#include <QDebug>

#ifdef Q_OS_MACOS
#include <CoreServices/CoreServices.h>
#include <dispatch/dispatch.h>
#endif

FolderWatcher::FolderWatcher(QObject *parent)
    : QObject(parent)
{
#ifndef Q_OS_MACOS
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &FolderWatcher::changed);
#endif
}

FolderWatcher::~FolderWatcher()
{
    stop();
}

#ifdef Q_OS_MACOS

static void onEvents(ConstFSEventStreamRef, void *info, size_t, void *, const FSEventStreamEventFlags *, const FSEventStreamEventId *)
{
    // on FSEvents' queue: hand it to the main thread
    auto *watcher = static_cast<FolderWatcher *>(info);
    QMetaObject::invokeMethod(watcher, &FolderWatcher::changed, Qt::QueuedConnection);
}

void FolderWatcher::watch(const QStringList &roots, const QStringList &)
{
    if (roots == m_roots && m_stream)
        return;
    stop();
    m_roots = roots;
    if (roots.isEmpty())
        return;

    CFMutableArrayRef paths = CFArrayCreateMutable(nullptr, roots.size(), &kCFTypeArrayCallBacks);
    for (const QString &root : roots) {
        CFStringRef s = root.toCFString();
        CFArrayAppendValue(paths, s);
        CFRelease(s);
    }
    FSEventStreamContext context = { 0, this, nullptr, nullptr, nullptr };
    FSEventStreamRef stream = FSEventStreamCreate(nullptr, &onEvents, &context, paths, kFSEventStreamEventIdSinceNow,
                                                  1.0,      // seconds: FSEvents gathers a burst (a whole album copied in) into one call
                                                  kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot);
    CFRelease(paths);
    if (!stream) {
        qWarning() << "legato: could not watch" << roots;
        return;
    }
    FSEventStreamSetDispatchQueue(stream, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    if (!FSEventStreamStart(stream)) {
        FSEventStreamInvalidate(stream);
        FSEventStreamRelease(stream);
        qWarning() << "legato: could not watch" << roots;
        return;
    }
    m_stream = stream;
}

void FolderWatcher::stop()
{
    if (!m_stream)
        return;
    auto stream = static_cast<FSEventStreamRef>(m_stream);
    FSEventStreamStop(stream);
    FSEventStreamInvalidate(stream);      // after this no callback is running or will run, so `this` is safe to go
    FSEventStreamRelease(stream);
    m_stream = nullptr;
}

#else

void FolderWatcher::watch(const QStringList &roots, const QStringList &subfolders)
{
    // inotify allows a limited number of watches per user (often 8192 on older systems): past this, the periodic rescan covers the rest
    constexpr int limit = 8000;
    QStringList wanted = roots + subfolders;
    wanted.removeDuplicates();
    if (wanted.size() > limit) {
        qWarning() << "legato: watching the first" << limit << "of" << wanted.size() << "folders; the rest are checked now and then";
        wanted = wanted.mid(0, limit);
    }
    const QStringList current = m_watcher.directories();
    if (current == wanted)
        return;
    if (!current.isEmpty())
        m_watcher.removePaths(current);
    if (!wanted.isEmpty())
        m_watcher.addPaths(wanted);
}

void FolderWatcher::stop()
{
    const QStringList current = m_watcher.directories();
    if (!current.isEmpty())
        m_watcher.removePaths(current);
}

#endif
