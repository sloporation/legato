#include "library.h"
#include "settings.h"

#include <QCollator>
#include <QDataStream>
#include <QDir>
#include <QDirIterator>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QImage>
#include <QQmlEngine>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QUrl>

#include <taglib/fileref.h>
#include <taglib/tpropertymap.h>

namespace {

const QStringList audioSuffixes = {
    "mp3", "flac", "wav", "m4a", "mp4", "aac", "alac", "ogg", "oga", "opus", "spx",
    "aif", "aiff", "wma", "ape", "wv", "mpc", "dsf", "dff",
    "mka", "webm"      // Matroska: what yt-dlp and friends save (usually Opus audio, sometimes with the video too)
};
const QStringList playlistSuffixes = { "m3u", "m3u8" };

QString qs(const TagLib::String &s)
{
    return QString::fromUtf8(s.toCString(true));
}

// paths are compared after this: macOS hands out decomposed (NFD) names, and a playlist written elsewhere usually has composed ones
QString pathKey(const QString &path)
{
    return QDir::cleanPath(path).normalized(QString::NormalizationForm_C);
}

TagLib::FileRef openFile(const QString &path, bool audio)
{
#ifdef _WIN32
    return TagLib::FileRef(reinterpret_cast<const wchar_t *>(path.utf16()), audio, TagLib::AudioProperties::Fast);
#else
    return TagLib::FileRef(QFile::encodeName(path).constData(), audio, TagLib::AudioProperties::Fast);
#endif
}

// "3/12" -> 3
int leadingNumber(const TagLib::PropertyMap &props, const char *key)
{
    const TagLib::StringList values = props[key];
    return values.isEmpty() ? 0 : qs(values.front()).section('/', 0, 0).trimmed().toInt();
}

// what the tags say (no id or path); empty if TagLib can't read the file
QVariantMap readTags(const QString &path)
{
    TagLib::FileRef file = openFile(path, true);
    if (file.isNull())
        return {};
    QVariantMap t;
    TagLib::Tag *tag = file.tag();
    const TagLib::PropertyMap props = file.properties();
    const QString title = tag ? qs(tag->title()).trimmed() : QString();
    t["title"] = title.isEmpty() ? QFileInfo(path).completeBaseName() : title;
    t["artist"] = tag ? qs(tag->artist()).trimmed() : QString();
    t["album"] = tag ? qs(tag->album()).trimmed() : QString();
    t["genre"] = tag ? qs(tag->genre()).trimmed() : QString();
    t["year"] = tag ? int(tag->year()) : 0;
    t["trackNumber"] = tag ? int(tag->track()) : 0;
    t["discNumber"] = leadingNumber(props, "DISCNUMBER");
    const TagLib::StringList albumArtist = props["ALBUMARTIST"];
    t["albumArtist"] = albumArtist.isEmpty() ? QString() : qs(albumArtist.front()).trimmed();
    t["duration"] = file.audioProperties() ? file.audioProperties()->lengthInMilliseconds() / 1000.0 : 0.0;
    return t;
}

// What the tags of each file said when it was last read, so a scan only opens the files that changed since. It is only a cache: the
// files stay the truth, and deleting it costs one slow scan. It lives in the system's cache folder (~/Library/Caches/legato on macOS,
// ~/.cache/legato on Linux, %LOCALAPPDATA%\legato\cache on Windows) and holds the files seen by the last full scan.
struct TagCache {
    struct Entry {
        qint64 modified = 0;     // ms since the epoch
        qint64 size = 0;
        QVariantMap tags;        // empty: TagLib could not read it, so it is not tried again until it changes
    };
    QHash<QString, Entry> entries;     // pathKey -> entry

    static constexpr quint32 magic = 0x4c544331;   // "LTC1"
    static constexpr qint32 version = 1;           // bump when the tags kept change

    static QString path()
    {
        return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/tags.cache";
    }

    void load()
    {
        QFile f(path());
        if (!f.open(QIODevice::ReadOnly))
            return;
        QDataStream in(&f);
        in.setVersion(QDataStream::Qt_6_5);
        quint32 m;
        qint32 v, count;
        in >> m >> v >> count;
        if (m != magic || v != version || in.status() != QDataStream::Ok)
            return;
        entries.reserve(count);
        for (qint32 i = 0; i < count && in.status() == QDataStream::Ok; i++) {
            QString key;
            Entry e;
            in >> key >> e.modified >> e.size >> e.tags;
            entries.insert(key, e);
        }
        if (in.status() != QDataStream::Ok)     // cut short: trust none of it
            entries.clear();
    }

    bool save() const
    {
        QDir().mkpath(QFileInfo(path()).absolutePath());
        QSaveFile f(path());       // written beside it, then swapped in: a crash never leaves half a cache
        if (!f.open(QIODevice::WriteOnly))
            return false;
        QDataStream out(&f);
        out.setVersion(QDataStream::Qt_6_5);
        out << magic << version << qint32(entries.size());
        for (auto it = entries.cbegin(); it != entries.cend(); ++it)
            out << it.key() << it->modified << it->size << it->tags;
        return out.status() == QDataStream::Ok && f.commit();
    }
};

// the entries of an .m3u/.m3u8 that are in the library, as track ids
QVariantMap readPlaylist(const QString &path, const QHash<QString, int> &ids)
{
    QVariantMap p;
    p["name"] = QFileInfo(path).completeBaseName();
    p["path"] = path;
    QVariantList tracks;
    int missing = 0;
    QFile f(path);
    if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QDir base = QFileInfo(path).absoluteDir();
        for (const QByteArray &raw : f.readAll().split('\n')) {
            QString line = QString::fromUtf8(raw).trimmed();
            if (line.startsWith(QChar(0xFEFF)))
                line.remove(0, 1);
            if (line.isEmpty() || line.startsWith('#'))
                continue;
            if (line.startsWith("file:", Qt::CaseInsensitive))
                line = QUrl(line).toLocalFile();
            QString entry = base.absoluteFilePath(line);
            auto it = ids.constFind(pathKey(entry));
            if (it == ids.constEnd() && line.contains('\\'))      // written on Windows
                it = ids.constFind(pathKey(base.absoluteFilePath(QString(line).replace('\\', '/'))));
            if (it != ids.constEnd())
                tracks << *it;
            else
                missing++;
        }
    }
    p["tracks"] = tracks;
    p["missing"] = missing;
    return p;
}

} // namespace

Library::Library(Settings *settings, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
{
    connect(m_settings, &Settings::musicDirsChanged, this, [this] { startScan(true, true); });

    m_settle.setSingleShot(true);
    m_settle.setInterval(3000);
    connect(&m_watcher, &FolderWatcher::changed, &m_settle, qOverload<>(&QTimer::start));
    connect(&m_settle, &QTimer::timeout, this, &Library::lookAgain);
    m_periodic.setInterval(15 * 60 * 1000);
    connect(&m_periodic, &QTimer::timeout, this, &Library::lookAgain);
    m_periodic.start();

    startScan(true, true);
}

Library::~Library()
{
    stopScan();
}

Library *Library::create(QQmlEngine *qml, QJSEngine *)
{
    return new Library(qml->singletonInstance<Settings *>("App", "Settings"));
}

void Library::stopScan()
{
    if (!m_thread)
        return;
    const bool shown = m_showScan;
    m_showScan = false;
    m_generation++;
    m_thread->wait();     // it checks between files, so this is quick
    delete m_thread;
    m_thread = nullptr;
    if (shown)
        emit scanningChanged();
}

void Library::rescan()
{
    startScan(false, true);
}

void Library::lookAgain()
{
    if (m_thread)
        m_lookAgain = true;
    else
        startScan(false, false);
}

void Library::startScan(bool fresh, bool shown)
{
    stopScan();
    const int generation = ++m_generation;
    m_lookAgain = false;
    m_showScan = shown;
    if (fresh) {
        m_tracks.clear();
        m_albums.clear();
        emit tracksChanged();
    }

    const QStringList dirs = m_settings->musicDirs();
    if (fresh)
        m_watcher.watch(dirs, {});      // (per-folder watching gets the subfolders once the scan has found them)
    m_thread = QThread::create([this, dirs, generation, fresh] {
        QVariantList batch, all;
        QStringList subfolders;
        QHash<QString, int> ids;      // pathKey -> track id
        QStringList playlistFiles;
        TagCache cache, seen;          // what the last scan found; what this one does
        cache.load();
        int fromCache = 0, unreadable = 0;
        QElapsedTimer took;
        took.start();
        QElapsedTimer sinceFlush;
        sinceFlush.start();
        const auto flush = [&] {
            if (batch.isEmpty() || !fresh)
                return;
            QMetaObject::invokeMethod(this, [this, batch, generation] {
                if (generation == m_generation)
                    addTracks(batch);
            }, Qt::QueuedConnection);
            batch.clear();
            sinceFlush.restart();
        };

        for (const QString &dir : dirs) {
            QDirIterator it(dir, QDir::Files | QDir::Dirs | QDir::Readable | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
            while (it.hasNext()) {
                if (generation != m_generation)
                    return;
                const QString path = it.next();
                if (it.fileInfo().isDir()) {
                    subfolders << path;
                    continue;
                }
                const QString suffix = it.fileInfo().suffix().toLower();
                if (playlistSuffixes.contains(suffix)) {
                    playlistFiles << path;
                    continue;
                }
                if (!audioSuffixes.contains(suffix))
                    continue;
                const QString key = pathKey(path);
                if (ids.contains(key))      // one folder inside another
                    continue;
                const QFileInfo info = it.fileInfo();
                TagCache::Entry entry = cache.entries.value(key);
                if (entry.modified == info.lastModified().toMSecsSinceEpoch() && entry.size == info.size() && entry.modified != 0) {
                    fromCache++;
                } else {
                    entry = { info.lastModified().toMSecsSinceEpoch(), info.size(), readTags(path) };
                }
                seen.entries.insert(key, entry);
                if (entry.tags.isEmpty()) {
                    unreadable++;
                    continue;
                }
                QVariantMap track = entry.tags;
                track["id"] = ids.size();
                track["path"] = path;
                ids.insert(key, ids.size());
                batch << track;
                all << track;
                if (sinceFlush.elapsed() > 250)
                    flush();
            }
        }
        flush();

        // keep what this scan saw, which also forgets files that have gone (only when something changed: most scans write nothing)
        if (fromCache != seen.entries.size() || seen.entries.size() != cache.entries.size()) {
            if (!seen.save())
                qWarning() << "legato: could not write the tag cache to" << TagCache::path();
        }
        qInfo().noquote() << QString("legato: %1 tracks in %2 ms (%3 from the cache, %4 files unreadable)")
                                 .arg(ids.size()).arg(took.elapsed()).arg(fromCache).arg(unreadable);

        QVariantList playlists;
        for (const QString &path : std::as_const(playlistFiles))
            playlists << readPlaylist(path, ids);
        QMetaObject::invokeMethod(this, [this, all, playlists, subfolders, dirs, generation, fresh] {
            if (generation != m_generation)
                return;
            // a quiet scan changes nothing on screen unless there is something new to show
            if (!fresh && all != m_tracks) {
                m_tracks = all;
                rebuildAlbums();
                emit tracksChanged();
            }
            if (playlists != m_playlists)
                setPlaylists(playlists);
            m_watcher.watch(dirs, subfolders);
            m_thread->wait();
            delete m_thread;
            m_thread = nullptr;
            const bool shown = m_showScan;
            m_showScan = false;
            if (shown)
                emit scanningChanged();
            if (m_lookAgain)
                lookAgain();
        }, Qt::QueuedConnection);
    });
    m_thread->start(QThread::LowPriority);
    if (shown)
        emit scanningChanged();
}

void Library::addTracks(const QVariantList &batch)
{
    m_tracks.append(batch);
    rebuildAlbums();
    emit tracksChanged();
}

void Library::rebuildAlbums()
{
    struct Album { QVariantMap info; int disc = INT_MAX, track = INT_MAX; };
    QHash<QString, Album> byKey;
    QList<QString> order;
    for (const QVariant &v : std::as_const(m_tracks)) {
        const QVariantMap t = v.toMap();
        const QString artist = t["albumArtist"].toString().isEmpty() ? t["artist"].toString() : t["albumArtist"].toString();
        const QString title = t["album"].toString().isEmpty() ? tr("Unknown Album") : t["album"].toString();
        const QString key = artist.toCaseFolded() + QChar(0x1f) + title.toCaseFolded();
        auto it = byKey.find(key);
        if (it == byKey.end()) {
            order << key;
            it = byKey.insert(key, Album());
            it->info["title"] = title;
            it->info["artist"] = artist.isEmpty() ? tr("Unknown Artist") : artist;
            it->info["genre"] = t["genre"];
            it->info["year"] = 0;
            it->info["trackCount"] = 0;
        }
        it->info["trackCount"] = it->info["trackCount"].toInt() + 1;
        it->info["year"] = qMax(it->info["year"].toInt(), t["year"].toInt());
        // the cover comes from the album's first track
        const int disc = qMax(1, t["discNumber"].toInt()), track = t["trackNumber"].toInt();     // no disc number: disc 1
        if (disc < it->disc || (disc == it->disc && track < it->track)) {
            it->disc = disc;
            it->track = track;
            it->info["cover"] = "image://cover/" + QString::fromUtf8(QUrl::toPercentEncoding(t["path"].toString()));
        }
    }

    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    collator.setNumericMode(true);
    std::sort(order.begin(), order.end(), [&](const QString &a, const QString &b) {
        const QVariantMap &x = byKey[a].info, &y = byKey[b].info;
        const int c = collator.compare(x["artist"].toString(), y["artist"].toString());
        return c != 0 ? c < 0 : collator.compare(x["title"].toString(), y["title"].toString()) < 0;
    });
    m_albums.clear();
    for (const QString &key : std::as_const(order))
        m_albums << byKey[key].info;
}

void Library::setPlaylists(QVariantList playlists)
{
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    collator.setNumericMode(true);
    std::sort(playlists.begin(), playlists.end(), [&](const QVariant &a, const QVariant &b) {
        return collator.compare(a.toMap()["name"].toString(), b.toMap()["name"].toString()) < 0;
    });
    m_playlists = playlists;
    emit playlistsChanged();
}

int Library::createPlaylist(const QString &name)
{
    const QStringList dirs = m_settings->musicDirs();
    if (dirs.isEmpty()) {
        emit failed(tr("Choose a music folder first: playlists are kept in it."));
        return -1;
    }
    const QDir dir(dirs.first());
    QString path = dir.filePath(name + ".m3u8");
    for (int n = 2; QFileInfo::exists(path); n++)
        path = dir.filePath(QString("%1 %2.m3u8").arg(name).arg(n));
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::NewOnly) || f.write("#EXTM3U\n") < 0) {
        emit failed(tr("Could not create %1.").arg(path));
        return -1;
    }
    f.close();

    QVariantMap p;
    p["name"] = QFileInfo(path).completeBaseName();
    p["path"] = path;
    p["tracks"] = QVariantList();
    p["missing"] = 0;
    QVariantList playlists = m_playlists;
    playlists << p;
    setPlaylists(playlists);
    for (int i = 0; i < m_playlists.size(); i++)
        if (m_playlists[i].toMap()["path"] == path)
            return i;
    return -1;
}

QImage CoverProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    const QString path = QUrl::fromPercentEncoding(id.toUtf8());
    QImage image;

    TagLib::FileRef file = openFile(path, false);
    if (!file.isNull()) {
        const auto pictures = file.complexProperties("PICTURE");
        // the front cover if it is marked as one, else the first picture
        for (const auto &picture : pictures) {
            const TagLib::ByteVector data = picture["data"].toByteVector();
            QImage candidate = QImage::fromData(reinterpret_cast<const uchar *>(data.data()), int(data.size()));
            if (candidate.isNull())
                continue;
            if (image.isNull() || picture["pictureType"].toString() == "Front Cover")
                image = candidate;
            if (picture["pictureType"].toString() == "Front Cover")
                break;
        }
    }
    if (image.isNull()) {
        const QDir dir = QFileInfo(path).absoluteDir();
        for (const QString &name : dir.entryList({ "cover.*", "folder.*", "front.*", "album.*" }, QDir::Files)) {
            if (image.load(dir.filePath(name)))
                break;
        }
    }
    if (image.isNull()) {
        // no picture: a blank one, so the view keeps its placeholder without a warning for every such album
        image = QImage(1, 1, QImage::Format_ARGB32);
        image.fill(Qt::transparent);
    } else if (requestedSize.isValid()) {
        image = image.scaled(requestedSize, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
    }
    if (size)
        *size = image.size();
    return image;
}
