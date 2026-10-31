#include "devices.h"
#include "library.h"
#ifdef LEGATO_IPHONE
#include "iphonestorage.h"
#endif
#ifdef LEGATO_ANDROID
#include "androidstorage.h"
#endif

#include <QFileInfo>
#include <QHostInfo>
#include <QRegularExpression>
#include <QQmlEngine>
#include <QSet>
#include <QTimer>

namespace {

// what each phone's player can play (AVPlayer; Media3 ExoPlayer); the rest of what the library holds is converted to AAC on the way
const QStringList iphonePlays = { "mp3", "m4a", "mp4", "aac", "alac", "wav", "aif", "aiff", "flac" };
const QStringList androidPlays = { "mp3", "m4a", "mp4", "aac", "flac", "wav", "ogg", "oga", "opus", "mka", "webm" };
const QStringList anyAudio = { "mp3", "flac", "wav", "m4a", "mp4", "aac", "alac", "ogg", "oga", "opus", "spx", "aif", "aiff", "wma", "ape",
                               "wv", "mpc", "dsf", "dff", "mka", "webm" };

} // namespace

// the worker: on its own thread

QVariantMap DeviceWorker::look(const QString &id)
{
    QVariantMap d { { "id", id }, { "free", -1 } };
#ifdef LEGATO_IPHONE
    if (id.startsWith("iphone:")) {
        d["kind"] = "iphone";
        IPhoneStorage phone;
        const auto status = phone.open(id.mid(7));
        d["name"] = phone.name().isEmpty() ? tr("iPhone") : phone.name();
        d["status"] = QStringList { "ready", "trust", "locked", "noapp", "error" }[int(status)];
        d["message"] = status == IPhoneStorage::Ready ? QString() : phone.error();
        if (status == IPhoneStorage::Ready) {
            d["free"] = phone.freeSpace();
            d["chosen"] = readChosen(phone);
        }
    }
#endif
#ifdef LEGATO_ANDROID
    if (id.startsWith("android:")) {
        d["kind"] = "android";
        AndroidStorage phone;
        const bool ok = phone.open(id.mid(8));
        d["name"] = phone.name().isEmpty() ? tr("Android phone") : phone.name();
        d["status"] = ok ? "ready" : "error";
        d["message"] = ok ? QString() : phone.error();
        if (ok) {
            d["free"] = phone.freeSpace();
            d["chosen"] = readChosen(phone);
        }
    }
#endif
    return d;
}

void DeviceWorker::poll()
{
    QStringList now;
#ifdef LEGATO_IPHONE
    for (const QString &udid : IPhoneStorage::connected())
        now << "iphone:" + udid;
#endif
#ifdef LEGATO_ANDROID
    for (const QString &where : AndroidStorage::connected())
        now << "android:" + where;
#endif

    for (const QString &id : now) {
        // a phone is looked at when it arrives, and again while something is in the way (it isn't trusted yet, it's locked)
        const auto it = m_known.constFind(id);
        if (it != m_known.cend() && it->value("status") == "ready")
            continue;
        // (opening an MTP device takes a while, and holds it while it does: after the first few tries, only every fourth poll)
        const int tries = it == m_known.cend() ? 0 : it->value("tries").toInt();
        if (id.startsWith("android:") && tries >= 3 && tries % 4 != 0) {
            m_known[id]["tries"] = tries + 1;
            continue;
        }
        QVariantMap d = look(id);
        d["tries"] = tries + 1;
        QVariantMap before = it == m_known.cend() ? QVariantMap() : *it;
        before.remove("tries");
        m_known.insert(id, d);
        d.remove("tries");
        if (before != d)
            emit seen(d);
    }
    if (!m_phoneId.isEmpty() && !now.contains(m_phoneId)) {     // (unplugged with a sync's hold on it)
        m_phone.reset();
        m_phoneId.clear();
    }
    for (const QString &id : m_known.keys()) {
        if (!now.contains(id)) {
            m_known.remove(id);
            emit gone(id);
        }
    }
}

DeviceStorage *DeviceWorker::reach(const QString &id, QString *error)
{
    if (m_phone && m_phoneId == id)
        return m_phone.get();
    m_phone.reset();
#ifdef LEGATO_IPHONE
    if (id.startsWith("iphone:")) {
        auto phone = std::make_unique<IPhoneStorage>();
        if (phone->open(id.mid(7)) == IPhoneStorage::Ready)
            m_phone = std::move(phone);
        else
            *error = phone->error();
    }
#endif
#ifdef LEGATO_ANDROID
    if (id.startsWith("android:")) {
        auto phone = std::make_unique<AndroidStorage>();
        if (phone->open(id.mid(8)))
            m_phone = std::move(phone);
        else
            *error = phone->error();
    }
#endif
    m_phoneId = m_phone ? id : QString();
    return m_phone.get();
}

void DeviceWorker::collect(const QString &id)
{
    QVariantList changes;
    QString error;
    if (DeviceStorage *phone = reach(id, &error)) {
        if (!collectChanges(*phone, &changes)) {
            error = tr("Couldn't read the playlist changes on the phone: %1").arg(phone->error());
            m_phone.reset();
        }
    }
    emit collected(id, changes, error);
}

void DeviceWorker::sync(const QString &id, const SyncJob &job)
{
    stop = false;
    QVariantMap result;
    QString error;
    if (DeviceStorage *phone = reach(id, &error)) {
        const SyncResult r = runSync(*phone, job, [&](qint64 done, qint64 total, const QString &what) {
            emit progress(id, done, total, what);
            return !stop.load();
        });
        result = { { "ok", r.ok }, { "message", r.message }, { "copied", r.copied }, { "removed", r.removed },
                   { "converted", r.converted }, { "unplayable", r.unplayable }, { "free", phone->freeSpace() } };
    } else {
        result = { { "ok", false }, { "message", error } };
    }
    m_phone.reset();     // (let go of it: other apps, and the next look, can have it)
    m_phoneId.clear();
    emit synced(id, result);
}

// Devices: on the window's thread

Devices::Devices(Library *library, QObject *parent)
    : QObject(parent), m_library(library), m_worker(new DeviceWorker)
{
    qRegisterMetaType<SyncJob>();
    m_worker->moveToThread(&m_thread);
    connect(&m_thread, &QThread::finished, m_worker, &QObject::deleteLater);

    connect(m_worker, &DeviceWorker::seen, this, [this](const QVariantMap &d) {
        QVariantMap device = d;
        device.remove("tries");
        const int i = indexOf(d["id"].toString());
        if (i < 0) {
            device["syncing"] = false;
            m_devices << device;
        } else {
            QVariantMap old = m_devices[i].toMap();
            // a choice made here and not synced yet stays
            if (old.contains("chosen") && !old.value("chosenSaved", true).toBool())
                device["chosen"] = old["chosen"];
            for (auto it = device.cbegin(); it != device.cend(); ++it)
                old[it.key()] = it.value();
            m_devices[i] = old;
        }
        emit devicesChanged();
    });
    connect(m_worker, &DeviceWorker::gone, this, [this](const QString &id) {
        const int i = indexOf(id);
        if (i >= 0) {
            m_devices.removeAt(i);
            emit devicesChanged();
        }
    });
    connect(m_worker, &DeviceWorker::progress, this, [this](const QString &id, qint64 done, qint64 total, const QString &what) {
        update(id, { { "done", done }, { "total", total }, { "what", what } });
    });
    // the phone's playlist changes are made here, and then the music goes on with the playlists as they now are
    connect(m_worker, &DeviceWorker::collected, this, [this](const QString &id, const QVariantList &changes, const QString &error) {
        const int i = indexOf(id);
        if (i < 0)
            return;
        if (!error.isEmpty()) {
            update(id, { { "syncing", false }, { "result", QVariantMap { { "ok", false }, { "message", error } } } });
            emit synced(m_devices[i].toMap()["name"].toString(), error);
            return;
        }
        m_applied[id] = m_library->applyPhoneChanges(changes);
        const QVariantMap d = m_devices[i].toMap();
        SyncJob j = job(d["kind"].toString(), d["chosen"].toMap());
        j.clearChanges = !changes.isEmpty();
        QMetaObject::invokeMethod(m_worker, [w = m_worker, id, j] { w->sync(id, j); }, Qt::QueuedConnection);
    });
    connect(m_worker, &DeviceWorker::synced, this, [this](const QString &id, const QVariantMap &r) {
        QVariantMap changes { { "syncing", false }, { "result", r } };
        if (r["ok"].toBool())
            changes["chosenSaved"] = true;
        if (r.contains("free"))
            changes["free"] = r["free"];
        update(id, changes);
        const int i = indexOf(id);
        const QString name = i >= 0 ? m_devices[i].toMap()["name"].toString() : QString();
        QString message = r["message"].toString();
        if (r["ok"].toBool()) {
            const int copied = r["copied"].toInt(), converted = r["converted"].toInt(), removed = r["removed"].toInt(),
                      unplayable = r["unplayable"].toInt();
            message = copied == 0 && removed == 0 ? tr("Up to date")
                    : copied == 1 ? tr("Synced: 1 song copied") : tr("Synced: %1 songs copied").arg(copied);
            if (converted > 0)
                message += tr(" (%1 converted to AAC)").arg(converted);
            if (removed > 0)
                message += tr(", %1 removed").arg(removed);
            if (unplayable > 0)
                message += tr(". %1 left off: the phone can't play them, and there's no ffmpeg to convert them").arg(unplayable);
        }
        // and what came back from the phone
        const QVariantMap applied = m_applied.take(id);
        const int made = applied["made"].toInt();
        const QStringList skipped = applied["skipped"].toStringList();
        if (made > 0)
            message += made == 1 ? tr(". 1 playlist change from the phone") : tr(". %1 playlist changes from the phone").arg(made);
        if (!skipped.isEmpty())
            message += tr(" (left out: %1)").arg(skipped.join(", "));
        emit synced(name, message);
    });

    auto *timer = new QTimer;
    timer->setInterval(2500);
    timer->moveToThread(&m_thread);
    connect(timer, &QTimer::timeout, m_worker, &DeviceWorker::poll);
    connect(&m_thread, &QThread::started, timer, qOverload<>(&QTimer::start));
    connect(&m_thread, &QThread::started, m_worker, &DeviceWorker::poll);
    connect(&m_thread, &QThread::finished, timer, &QObject::deleteLater);
    m_thread.start();
}

Devices::~Devices()
{
    m_worker->stop = true;
    m_thread.quit();
    m_thread.wait();
}

Devices *Devices::create(QQmlEngine *qml, QJSEngine *)
{
    return new Devices(qml->singletonInstance<Library *>("App", "Library"));
}

int Devices::indexOf(const QString &id) const
{
    for (int i = 0; i < m_devices.size(); ++i)
        if (m_devices[i].toMap()["id"] == id)
            return i;
    return -1;
}

void Devices::update(const QString &id, const QVariantMap &changes)
{
    const int i = indexOf(id);
    if (i < 0)
        return;
    QVariantMap d = m_devices[i].toMap();
    for (auto it = changes.cbegin(); it != changes.cend(); ++it)
        d[it.key()] = it.value();
    m_devices[i] = d;
    emit devicesChanged();
}

void Devices::choose(const QString &id, const QVariantMap &chosen)
{
    update(id, { { "chosen", chosen }, { "chosenSaved", false } });
}

SyncJob Devices::job(const QString &kind, const QVariantMap &chosen) const
{
    SyncJob job;
    job.chosen = chosen;
    job.source = tr("Legato on %1").arg(QHostInfo::localHostName().remove(QRegularExpression("\\.local$")));
    job.playable = kind == "iphone" ? iphonePlays : androidPlays;
    job.convertible = anyAudio;
    static const QString ffmpeg = findFfmpeg();
    job.ffmpeg = ffmpeg;

    const QVariantList all = m_library->tracks();
    const bool everything = chosen["everything"].toBool();
    QSet<int> ids;
    auto add = [&](const QVariant &v) { ids.insert(v.toMap()["id"].toInt()); };

    const QStringList playlistNames = chosen["playlists"].toStringList();
    for (const QVariant &v : m_library->playlists()) {
        const QVariantMap p = v.toMap();
        if (!everything && !playlistNames.contains(p["name"].toString()))
            continue;
        QStringList paths;
        for (const QVariant &t : p["tracks"].toList()) {
            const int id = t.toInt();
            if (id >= 0 && id < all.size()) {
                ids.insert(id);
                paths << all[id].toMap()["path"].toString();
            }
        }
        job.playlists.append({ p["name"].toString(), paths });
    }
    if (everything) {
        job.tracks = all;
        return job;
    }
    for (const QString &key : chosen["albums"].toStringList())
        for (const QVariant &t : m_library->albumTracks(key))
            add(t);
    const QStringList artistNames = chosen["artists"].toStringList();
    for (const QVariant &v : m_library->artists()) {
        const QVariantMap a = v.toMap();
        if (!artistNames.contains(a["name"].toString()))
            continue;
        for (const QVariant &album : a["albums"].toList())
            for (const QVariant &t : m_library->albumTracks(album.toMap()["key"].toString()))
                add(t);
        for (const QVariant &album : a["appearsOn"].toList())
            for (const QVariant &t : album.toMap()["trackIds"].toList())
                ids.insert(t.toInt());
    }
    for (const QVariant &v : all)
        if (ids.contains(v.toMap()["id"].toInt()))
            job.tracks << v;
    return job;
}

QVariantMap Devices::measure(const QString &kind, const QVariantMap &chosen) const
{
    const SyncJob j = job(kind, chosen);
    int songs = 0, converted = 0, unplayable = 0;
    qint64 bytes = 0;
    for (const QVariant &v : j.tracks) {
        const QFileInfo info(v.toMap()["path"].toString());
        const QString suffix = info.suffix().toLower();
        if (j.playable.contains(suffix)) {
            songs++;
            bytes += info.size();
        } else if (!j.ffmpeg.isEmpty() && j.convertible.contains(suffix)) {
            songs++;
            converted++;
            bytes += info.size();     // (about what the AAC comes to: Opus and AAC at these rates are much of a size)
        } else {
            unplayable++;
        }
    }
    return { { "songs", songs }, { "bytes", bytes }, { "converted", converted }, { "unplayable", unplayable },
             { "ffmpeg", !j.ffmpeg.isEmpty() } };
}

void Devices::sync(const QString &id)
{
    const int i = indexOf(id);
    if (i < 0)
        return;
    const QVariantMap d = m_devices[i].toMap();
    if (d["syncing"].toBool() || d["status"] != "ready")
        return;
    update(id, { { "syncing", true }, { "done", 0 }, { "total", 0 }, { "what", tr("Starting") }, { "result", QVariant() } });
    QMetaObject::invokeMethod(m_worker, [w = m_worker, id] { w->collect(id); }, Qt::QueuedConnection);
}

void Devices::stopSync()
{
    m_worker->stop = true;
}
