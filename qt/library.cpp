#include "library.h"
#include "settings.h"

#include <QCollator>
#include <QDesktopServices>
#include <QProcess>
#include <QDataStream>
#include <QDir>
#include <QDirIterator>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QImage>
#include <QQmlEngine>
#include <QRegularExpression>
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
    int year = tag ? int(tag->year()) : 0;
    while (year > 9999)      // a whole date (20171030, as yt-dlp writes it): the year is its first four digits
        year /= 10;
    t["year"] = year;
    t["trackNumber"] = tag ? int(tag->track()) : 0;
    t["discNumber"] = leadingNumber(props, "DISCNUMBER");
    const TagLib::StringList albumArtist = props["ALBUMARTIST"];
    t["albumArtist"] = albumArtist.isEmpty() ? QString() : qs(albumArtist.front()).trimmed();
    QStringList artists;     // (Picard and others write one name per value)
    for (const TagLib::String &name : props["ARTISTS"])
        if (!qs(name).trimmed().isEmpty())
            artists << qs(name).trimmed();
    t["artists"] = artists;
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
    static constexpr qint32 version = 3;           // bump when the tags kept (or how they are read) change

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
        m_artists.clear();
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

namespace {

// which album a track is on: its album artist (else its artist) and album title, ignoring case
QString albumArtistOf(const QVariantMap &t)
{
    return t["albumArtist"].toString().isEmpty() ? t["artist"].toString() : t["albumArtist"].toString();
}
QString albumKey(const QVariantMap &t)
{
    return albumArtistOf(t).toCaseFolded() + QChar(0x1f) + t["album"].toString().toCaseFolded();
}

} // namespace

QVariantList Library::albumTracks(const QString &key) const
{
    QVariantList tracks;
    for (const QVariant &v : std::as_const(m_tracks))
        if (albumKey(v.toMap()) == key)
            tracks << v;
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    collator.setNumericMode(true);
    std::stable_sort(tracks.begin(), tracks.end(), [&](const QVariant &a, const QVariant &b) {
        const QVariantMap x = a.toMap(), y = b.toMap();
        const int dx = qMax(1, x["discNumber"].toInt()), dy = qMax(1, y["discNumber"].toInt());
        if (dx != dy) return dx < dy;
        // (numbered tracks first)
        const uint tx = x["trackNumber"].toInt() > 0 ? x["trackNumber"].toUInt() : UINT_MAX;
        const uint ty = y["trackNumber"].toInt() > 0 ? y["trackNumber"].toUInt() : UINT_MAX;
        if (tx != ty) return tx < ty;
        return collator.compare(x["title"].toString(), y["title"].toString()) < 0;
    });
    return tracks;
}

void Library::rebuildAlbums()
{
    struct Album { QVariantMap info; int disc = INT_MAX, track = INT_MAX; };
    QHash<QString, Album> byKey;
    QList<QString> order;
    for (const QVariant &v : std::as_const(m_tracks)) {
        const QVariantMap t = v.toMap();
        const QString artist = albumArtistOf(t);
        const QString title = t["album"].toString().isEmpty() ? tr("Unknown Album") : t["album"].toString();
        const QString key = albumKey(t);
        auto it = byKey.find(key);
        if (it == byKey.end()) {
            order << key;
            it = byKey.insert(key, Album());
            it->info["key"] = key;
            it->info["title"] = title;
            it->info["artist"] = artist.isEmpty() ? tr("Unknown Artist") : artist;
            it->info["genre"] = t["genre"];
            it->info["year"] = 0;
            it->info["trackCount"] = 0;
            it->info["duration"] = 0.0;
        }
        it->info["trackCount"] = it->info["trackCount"].toInt() + 1;
        if (it->info["genre"].toString().isEmpty())     // the first track that has one
            it->info["genre"] = t["genre"];
        it->info["duration"] = it->info["duration"].toDouble() + t["duration"].toDouble();
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
    rebuildArtists();
}

namespace {

// The artists a credit names: lead (whose track or album it is) and featured. "A feat. B", "A ft. B", "A featuring B", "A with B" and
// "A (feat. B)" feature B. "A; B", "A / B", "A vs. B" and "A x B" are always two artists. "A & B" and "A, B" are two only when the
// whole is not a name in its own right, that is an album artist or an ARTISTS value somewhere (Simon & Garfunkel; Earth, Wind & Fire).
// Nothing checks the names: it is only what the tags say.
struct Credit { QStringList lead, featured; };

const QRegularExpression bracketedFeature(R"(\s*[(\[]\s*(?:feat\.?|ft\.?|featuring|with)\s+([^)\]]+)[)\]])",
                                          QRegularExpression::CaseInsensitiveOption);
const QRegularExpression featuring(R"(\s+(?:feat\.?|ft\.?|featuring|with)\s+)", QRegularExpression::CaseInsensitiveOption);
const QRegularExpression together(R"(\s*;\s*|\s+/\s+|\s+vs\.?\s+|\s+x\s+|\s+(?:feat\.?|ft\.?|featuring|with)\s+)",
                                  QRegularExpression::CaseInsensitiveOption);
const QRegularExpression andOrComma(R"(\s*,\s*|\s+&\s+)");

void addNames(const QString &part, const QSet<QString> &known, QStringList &out)
{
    for (const QString &piece : part.split(together, Qt::SkipEmptyParts)) {
        const QString whole = piece.simplified();
        if (whole.isEmpty())
            continue;
        if (known.contains(whole.toCaseFolded())) {
            out << whole;
            continue;
        }
        for (const QString &name : whole.split(andOrComma, Qt::SkipEmptyParts))
            if (!name.simplified().isEmpty())
                out << name.simplified();
    }
}

// who "(feat. B)" in a title or credit names
QStringList bracketedFeatures(const QString &text, const QSet<QString> &known)
{
    QStringList names;
    for (auto it = bracketedFeature.globalMatch(text); it.hasNext();)
        addNames(it.next().captured(1), known, names);
    return names;
}

Credit splitCredit(QString credit, const QSet<QString> &known)
{
    Credit c;
    credit = credit.simplified();
    if (credit.isEmpty())
        return c;
    c.featured = bracketedFeatures(credit, known);
    credit.remove(bracketedFeature);
    const QRegularExpressionMatch m = featuring.match(credit);
    addNames(m.hasMatch() ? credit.left(m.capturedStart()) : credit, known, c.lead);
    if (m.hasMatch())
        addNames(credit.mid(m.capturedEnd()), known, c.featured);
    return c;
}

// "The Beatles" sorts with the Bs, as in Apple Music
QString artistSortName(const QString &name)
{
    return name.startsWith("The ", Qt::CaseInsensitive) && name.size() > 4 ? name.mid(4) : name;
}

} // namespace

void Library::rebuildArtists()
{
    QSet<QString> known;     // names that are not split at "&" or ","
    for (const QVariant &v : std::as_const(m_tracks)) {
        const QVariantMap t = v.toMap();
        if (!t["albumArtist"].toString().isEmpty())
            known << t["albumArtist"].toString().simplified().toCaseFolded();
        for (const QString &name : t["artists"].toStringList())
            known << name.simplified().toCaseFolded();
    }
    QHash<QString, int> albumIndex;
    for (int i = 0; i < m_albums.size(); i++)
        albumIndex.insert(m_albums[i].toMap()["key"].toString(), i);

    struct Artist { QString name; QSet<int> own; QHash<int, QVariantList> other; int songs = 0; };     // other: album -> their track ids
    QHash<QString, Artist> byName;     // case-folded name -> artist, spelt as first seen
    for (const QVariant &v : std::as_const(m_tracks)) {
        const QVariantMap t = v.toMap();
        const int album = albumIndex.value(albumKey(t), -1);
        QSet<QString> credited;
        const auto credit = [&](const QString &name, bool own) {
            const QString key = name.toCaseFolded();
            auto it = byName.find(key);
            if (it == byName.end())
                it = byName.insert(key, Artist { name });
            if (own)
                it->own.insert(album);
            else if (!it->other[album].contains(t["id"]))
                it->other[album] << t["id"];
            credited << key;
        };
        const QString albumArtist = albumArtistOf(t);
        if (albumArtist.isEmpty()) {
            credit(tr("Unknown Artist"), true);
        } else {
            const Credit c = splitCredit(albumArtist, known);
            for (const QString &name : c.lead) credit(name, true);
            for (const QString &name : c.featured) credit(name, false);
        }
        const Credit c = splitCredit(t["artist"].toString(), known);
        for (const QString &name : c.lead + c.featured + bracketedFeatures(t["title"].toString(), known) + t["artists"].toStringList())
            credit(name.simplified(), false);
        for (const QString &key : std::as_const(credited))
            byName[key].songs++;
    }

    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    collator.setNumericMode(true);
    const auto albumList = [&](const QList<int> &indexes, const QHash<int, QVariantList> &trackIds) {
        QVariantList albums;
        for (const int i : indexes) {
            if (i < 0)
                continue;
            QVariantMap album = m_albums[i].toMap();
            if (trackIds.contains(i))
                album["trackIds"] = trackIds[i];
            albums << album;
        }
        std::sort(albums.begin(), albums.end(), [&](const QVariant &a, const QVariant &b) {
            const QVariantMap x = a.toMap(), y = b.toMap();
            if (x["year"].toInt() != y["year"].toInt()) return x["year"].toInt() > y["year"].toInt();
            return collator.compare(x["title"].toString(), y["title"].toString()) < 0;
        });
        return albums;
    };
    QList<Artist> artists = byName.values();
    std::sort(artists.begin(), artists.end(), [&](const Artist &a, const Artist &b) {
        return collator.compare(artistSortName(a.name), artistSortName(b.name)) < 0;
    });
    m_artists.clear();
    for (const Artist &a : std::as_const(artists)) {
        QList<int> others;
        for (auto it = a.other.cbegin(); it != a.other.cend(); ++it)
            if (!a.own.contains(it.key()))
                others << it.key();
        const QVariantList albums = albumList(a.own.values(), {}), appearsOn = albumList(others, a.other);
        const QVariantList &first = albums.isEmpty() ? appearsOn : albums;
        m_artists << QVariantMap {
            { "name", a.name }, { "albums", albums }, { "appearsOn", appearsOn }, { "songCount", a.songs },
            { "featuredOnly", albums.isEmpty() }, { "cover", first.isEmpty() ? QVariant() : first.front().toMap()["cover"] },
        };
    }
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

namespace {

// the edit window's names, and the tag each one is (TagLib's names, which it maps onto ID3v2 frames, Vorbis comments, MP4 atoms, …)
const QList<QPair<QString, const char *>> editableTags = {
    { "title", "TITLE" }, { "artist", "ARTIST" }, { "album", "ALBUM" }, { "albumArtist", "ALBUMARTIST" },
    { "genre", "GENRE" }, { "date", "DATE" },
};

QString firstValue(const TagLib::PropertyMap &props, const char *key)
{
    const TagLib::StringList values = props[key];
    return values.isEmpty() ? QString() : qs(values.front());
}

// "3/12" -> ("3", "12")
QPair<QString, QString> numberAndTotal(const TagLib::PropertyMap &props, const char *key)
{
    const QString value = firstValue(props, key);
    return { value.section('/', 0, 0).trimmed(), value.section('/', 1).trimmed() };
}

} // namespace

QVariantMap Library::tagsForEditing(const QString &path) const
{
    QVariantMap out;
    TagLib::FileRef file = openFile(path, true);
    if (file.isNull())
        return out;
    const TagLib::PropertyMap props = file.properties();
    for (const auto &[name, key] : editableTags)
        out[name] = firstValue(props, key);
    const auto track = numberAndTotal(props, "TRACKNUMBER"), disc = numberAndTotal(props, "DISCNUMBER");
    out["trackNumber"] = track.first;
    out["trackTotal"] = track.second;
    out["discNumber"] = disc.first;
    out["discTotal"] = disc.second;
    // also the totals some formats keep apart (Vorbis comments: TRACKTOTAL, DISCTOTAL)
    if (track.second.isEmpty())
        out["trackTotal"] = firstValue(props, "TRACKTOTAL");
    if (disc.second.isEmpty())
        out["discTotal"] = firstValue(props, "DISCTOTAL");

    out["format"] = QFileInfo(path).suffix().toUpper();
    if (const TagLib::AudioProperties *audio = file.audioProperties()) {
        out["bitrate"] = audio->bitrate();
        out["sampleRate"] = audio->sampleRate();
        out["channels"] = audio->channels();
        out["duration"] = audio->lengthInMilliseconds() / 1000.0;
    }
    return out;
}

QString Library::writeTags(const QString &path, const QVariantMap &tags)
{
    const QString error = saveTags(path, tags);
    if (error.isEmpty())
        showEdits({ path });
    return error;
}

QString Library::writeTagsMany(const QStringList &paths, const QVariantMap &tags)
{
    QStringList saved, failed;
    QString why;
    for (const QString &path : paths) {
        const QString error = saveTags(path, tags);
        if (error.isEmpty()) {
            saved << path;
        } else {
            failed << QFileInfo(path).fileName();
            why = error;
        }
    }
    showEdits(saved);
    if (failed.isEmpty())
        return QString();
    if (failed.size() == 1)
        return tr("%1: %2").arg(failed.front(), why);
    return tr("%n file(s) couldn't be changed (%1, …): %2", nullptr, failed.size()).arg(failed.front(), why);
}

QString Library::saveTags(const QString &path, const QVariantMap &tags)
{
    TagLib::FileRef file = openFile(path, false);
    if (file.isNull())
        return tr("Legato can't read the tags of this file.");
    if (file.file()->readOnly())
        return tr("The file can't be changed (it is read-only, or on a disk that is).");

    TagLib::PropertyMap props = file.properties();     // everything already there, so only what was edited changes
    const auto put = [&](const char *key, const QString &value) {
        if (value.trimmed().isEmpty())
            props.erase(key);
        else
            props.replace(key, TagLib::StringList(TagLib::String(value.trimmed().toStdString(), TagLib::String::UTF8)));
    };
    for (const auto &[name, key] : editableTags)
        if (tags.contains(name))
            put(key, tags[name].toString());
    // numbers as "n/total", the form every format's readers understand; a separate total (Vorbis) goes, so it can't disagree
    const auto numbered = [&](const char *key, const char *totalKey, const QString &number, const QString &total) {
        put(key, number.trimmed().isEmpty() ? QString() : total.trimmed().isEmpty() ? number : number.trimmed() + "/" + total.trimmed());
        props.erase(totalKey);
    };
    // a number or a total on its own (edited across several tracks at once) goes with the file's own other half
    const auto numbers = [&](const char *key, const char *totalKey, const QString &numberName, const QString &totalName) {
        if (!tags.contains(numberName) && !tags.contains(totalName))
            return;
        const QString now = props[key].isEmpty() ? QString() : qs(props[key].front());
        const QString nowTotal = now.contains('/') ? now.section('/', 1, 1).trimmed() : props[totalKey].isEmpty() ? QString() : qs(props[totalKey].front());
        numbered(key, totalKey, tags.contains(numberName) ? tags[numberName].toString() : now.section('/', 0, 0).trimmed(),
                 tags.contains(totalName) ? tags[totalName].toString() : nowTotal);
    };
    numbers("TRACKNUMBER", "TRACKTOTAL", "trackNumber", "trackTotal");
    numbers("DISCNUMBER", "DISCTOTAL", "discNumber", "discTotal");

    const TagLib::PropertyMap refused = file.setProperties(props);
    for (const auto &[name, key] : editableTags)
        if (tags.contains(name) && !tags[name].toString().trimmed().isEmpty() && refused.contains(key))
            qWarning().noquote() << "legato:" << path << "can't hold" << key;
    if (!file.save())
        return tr("Couldn't save the tags into the file.");
    return QString();
}

// show the files' new tags now rather than at the next scan (which will find them changed and read them again anyway)
void Library::showEdits(const QStringList &paths)
{
    if (paths.isEmpty())
        return;
    QHash<QString, QVariantMap> fresh;
    for (const QString &path : paths)
        fresh.insert(pathKey(path), readTags(path));
    QVariantList edited;
    for (int i = 0; i < m_tracks.size(); i++) {
        QVariantMap track = m_tracks[i].toMap();
        const auto it = fresh.constFind(pathKey(track["path"].toString()));
        if (it == fresh.cend())
            continue;
        for (auto tag = it->cbegin(); tag != it->cend(); ++tag)
            track[tag.key()] = tag.value();
        m_tracks[i] = track;
        edited << track;
    }
    rebuildAlbums();
    emit tracksChanged();
    for (const QVariant &track : std::as_const(edited))
        emit trackEdited(track.toMap());
}

void Library::reveal(const QString &path) const
{
#if defined(Q_OS_MACOS)
    QProcess::startDetached("open", { "-R", path });
#elif defined(Q_OS_WIN)
    QProcess::startDetached("explorer", { "/select,", QDir::toNativeSeparators(path) });
#else
    QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(path).absolutePath()));     // file managers differ in how to select one
#endif
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
