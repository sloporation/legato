#include "sync.h"
#include "devicestorage.h"
#include "library.h"

#include <QBuffer>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QHash>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>

namespace {

QString hash16(const QByteArray &data)
{
    return QString::fromLatin1(QCryptographicHash::hash(data, QCryptographicHash::Sha1).toHex().left(16));
}

QString isoTime(const QDateTime &t)
{
    return t.toUTC().toString(Qt::ISODate);
}

// the album's cover as the phones want it: a 600 px square JPEG
QByteArray coverJpeg(const QString &trackPath)
{
    QImage image = coverImage(trackPath);
    if (image.isNull())
        return {};
    image = image.scaled(600, 600, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
    image = image.copy((image.width() - 600) / 2, (image.height() - 600) / 2, 600, 600);
    QByteArray jpeg;
    QBuffer buffer(&jpeg);
    buffer.open(QIODevice::WriteOnly);
    image.convertToFormat(QImage::Format_RGB32).save(&buffer, "JPEG", 88);
    return jpeg;
}

QByteArray manifestJson(const QString &source, const QJsonArray &tracks, const QList<QPair<QString, QStringList>> &playlists,
                        const QHash<QString, QString> &idOfPath, const QSet<QString> &present, const QVariantMap &chosen)
{
    QJsonArray lists;
    for (const auto &[name, paths] : playlists) {
        QJsonArray ids;
        for (const QString &path : paths) {
            const QString id = idOfPath.value(path);
            if (present.contains(id))
                ids.append(id);
        }
        lists.append(QJsonObject { { "name", name }, { "tracks", ids } });
    }
    QJsonArray kept;
    for (const QJsonValue &t : tracks)
        if (present.contains(t.toObject()["id"].toString()))
            kept.append(t);
    const QJsonObject manifest {
        { "version", 1 },
        { "generated", isoTime(QDateTime::currentDateTimeUtc()) },
        { "source", source },
        { "tracks", kept },
        { "playlists", lists },
        { "chosen", QJsonObject::fromVariantMap(chosen) },
    };
    return QJsonDocument(manifest).toJson(QJsonDocument::Indented);
}

} // namespace

QString syncId(const QString &path)
{
    return hash16(QDir::cleanPath(path).normalized(QString::NormalizationForm_C).toUtf8());
}

QVariantMap readChosen(DeviceStorage &device)
{
    QByteArray data;
    if (!device.read("manifest.json", &data))
        return {};
    return QJsonDocument::fromJson(data).object()["chosen"].toObject().toVariantMap();
}

SyncResult runSync(DeviceStorage &device, const SyncJob &job, const SyncProgress &progress)
{
    SyncResult result;
    auto failed = [&](const QString &what) {
        result.message = what + (device.error().isEmpty() ? QString() : ": " + device.error());
        return result;
    };

    // what is on the phone now
    QStringList musicFiles, coverFiles;
    if (!device.list("Music", &musicFiles) || !device.list("Covers", &coverFiles))
        return failed(QObject::tr("Couldn't open the Legato folder on the phone"));
    const QSet<QString> onPhone(musicFiles.begin(), musicFiles.end());
    QHash<QString, QJsonObject> before;     // id → its entry in the phone's manifest
    QByteArray oldManifest;
    if (device.read("manifest.json", &oldManifest))
        for (const QJsonValue &v : QJsonDocument::fromJson(oldManifest).object()["tracks"].toArray())
            before.insert(v.toObject()["id"].toString(), v.toObject());

    // what it should have
    struct Copy { QString id, local, file, title; qint64 size; };
    QList<Copy> copies;
    QJsonArray tracks;
    QHash<QString, QString> idOfPath;
    QSet<QString> wanted, keep;     // keep: already there as it should be
    QHash<QString, QString> coverOfAlbum;     // album key → the track to take its cover from
    QHash<QString, QString> idCover;          // track id → its album key
    qint64 total = 0;
    for (const QVariant &v : job.tracks) {
        const QVariantMap t = v.toMap();
        const QString path = t["path"].toString();
        const QFileInfo info(path);
        if (!job.playable.contains(info.suffix().toLower())) {
            result.unplayable++;
            continue;
        }
        const QString id = syncId(path);
        if (wanted.contains(id))
            continue;
        const QString file = "Music/" + id + "." + info.suffix().toLower();
        const QString modified = isoTime(info.lastModified());
        QJsonObject entry {
            { "id", id }, { "file", file },
            { "title", t["title"].toString() }, { "artist", t["artist"].toString() }, { "album", t["album"].toString() },
            { "albumArtist", t["albumArtist"].toString() }, { "genre", t["genre"].toString() },
            { "year", t["year"].toInt() }, { "trackNumber", t["trackNumber"].toInt() }, { "discNumber", t["discNumber"].toInt() },
            { "duration", t["duration"].toDouble() }, { "size", info.size() }, { "modified", modified },
        };
        const QJsonObject old = before.value(id);
        if (onPhone.contains(file.mid(6)) && old["file"].toString() == file && old["size"].toInteger() == info.size()
            && old["modified"].toString() == modified) {
            keep.insert(id);
        } else {
            copies.append({ id, path, file, t["title"].toString().isEmpty() ? info.completeBaseName() : t["title"].toString(), info.size() });
            total += info.size();
        }
        const QString album = albumKey(t);
        if (!coverOfAlbum.contains(album))
            coverOfAlbum.insert(album, path);
        idCover.insert(id, album);
        idOfPath.insert(path, id);
        wanted.insert(id);
        tracks.append(entry);
    }

    const qint64 free = device.freeSpace();
    if (free >= 0) {
        qint64 freed = 0;
        for (auto it = before.cbegin(); it != before.cend(); ++it)
            if (!keep.contains(it.key()))
                freed += it.value()["size"].toInteger();
        if (total > free + freed - 50'000'000)     // (and leave the phone some room)
            return failed(QObject::tr("Not enough space on the phone: this needs %1 MB more")
                              .arg((total - free - freed + 50'000'000) / 1'000'000));
    }

    // 1. the manifest loses whatever is about to change, so the phone never plays a file half-way through being replaced
    QSet<QString> present = keep;
    if (!before.isEmpty() && before.size() != keep.size()) {
        QJsonArray unchanged;
        for (const QString &id : std::as_const(keep))
            unchanged.append(before.value(id));
        if (!device.write("manifest.json.part", manifestJson(job.source, unchanged, job.playlists, idOfPath, keep, job.chosen))
            || !device.rename("manifest.json.part", "manifest.json"))
            return failed(QObject::tr("Couldn't update the phone's list of music"));
    }

    // 2. the files no longer wanted go first, to make room
    const QSet<QString> wantedFiles = [&] {
        QSet<QString> names;
        for (const QJsonValue &t : tracks)
            names.insert(t.toObject()["file"].toString().mid(6));
        return names;
    }();
    for (const QString &name : musicFiles) {
        if (!wantedFiles.contains(name)) {
            if (!device.remove("Music/" + name))
                return failed(QObject::tr("Couldn't delete a file on the phone"));
            if (!name.endsWith(".part"))
                result.removed++;
        }
    }

    // 3. the new and changed files, each as .part, renamed into place once it is all there
    qint64 done = 0;
    bool stopped = false;
    for (const Copy &c : copies) {
        if (!progress(done, total, c.title)) {
            stopped = true;
            break;
        }
        const qint64 start = done;
        const bool ok = device.upload(c.local, c.file + ".part", [&](qint64 sent) {
            return progress(start + sent, total, c.title);
        });
        if (!ok || !device.rename(c.file + ".part", c.file)) {
            device.remove(c.file + ".part");
            if (!progress(start, total, c.title)) {
                stopped = true;
                break;
            }
            // the phone keeps what it had; this one file is missing until the next sync
            result.message = QObject::tr("Couldn't copy “%1”: %2").arg(c.title, device.error());
            done = start + c.size;
            continue;
        }
        done = start + c.size;
        present.insert(c.id);
        result.copied++;
    }

    // 4. the covers, named after what is in them, so a changed cover is a new file
    QHash<QString, QString> coverFile;     // album key → Covers/<hash>.jpg
    if (!stopped) {
        progress(total, total, QObject::tr("Covers"));
        const QSet<QString> coversThere(coverFiles.begin(), coverFiles.end());
        QSet<QString> coversWanted;
        for (auto it = coverOfAlbum.cbegin(); it != coverOfAlbum.cend(); ++it) {
            const QByteArray jpeg = coverJpeg(it.value());
            if (jpeg.isEmpty())
                continue;
            const QString name = hash16(jpeg) + ".jpg";
            if (!coversThere.contains(name) && !coversWanted.contains(name) && !device.write("Covers/" + name, jpeg))
                continue;     // no cover is better than no sync
            coversWanted.insert(name);
            coverFile.insert(it.key(), "Covers/" + name);
        }
        for (const QString &name : coverFiles)
            if (!coversWanted.contains(name))
                device.remove("Covers/" + name);
    } else {
        // keep the covers that are there for the albums that are
        for (auto it = coverOfAlbum.cbegin(); it != coverOfAlbum.cend(); ++it) {
            const QByteArray jpeg = coverJpeg(it.value());
            const QString name = hash16(jpeg) + ".jpg";
            if (!jpeg.isEmpty() && coverFiles.contains(name))
                coverFile.insert(it.key(), "Covers/" + name);
        }
    }

    // 5. the manifest, last
    for (QJsonValueRef v : tracks) {
        QJsonObject t = v.toObject();
        const QString cover = coverFile.value(idCover.value(t["id"].toString()));
        if (!cover.isEmpty())
            t["cover"] = cover;
        v = t;
    }
    if (!device.write("manifest.json.part", manifestJson(job.source, tracks, job.playlists, idOfPath, present, job.chosen))
        || !device.rename("manifest.json.part", "manifest.json"))
        return failed(QObject::tr("Couldn't write the phone's list of music"));

    result.ok = !stopped && result.message.isEmpty();
    if (stopped)
        result.message = QObject::tr("Stopped. The phone has what was copied so far.");
    return result;
}
