#pragma once

#include <QPair>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <functional>

class DeviceStorage;

// What to put on a phone: the tracks (the Library's maps of them) and the playlists, already narrowed to what was chosen.
struct SyncJob {
    QVariantList tracks;
    QList<QPair<QString, QStringList>> playlists;     // name, and its tracks' paths in order
    QVariantMap chosen;       // the choice itself, kept in the manifest so the next sync (from any computer) starts from it
    QString source;           // "Legato on Jacob's MacBook"
    QStringList playable;     // the file types the phone can play (suffixes); the others are left off
};

struct SyncResult {
    bool ok = false;
    QString message;          // what happened, for the person
    int copied = 0;
    int removed = 0;
    int unplayable = 0;       // tracks left off because the phone can't play them
};

// done and total in bytes; what: what it is doing now. Returning false stops the sync, leaving the phone with what got there.
using SyncProgress = std::function<bool(qint64 done, qint64 total, const QString &what)>;

// Brings the phone's Legato/ folder in line with the job, as docs/sync.md says: the phone's manifest first loses the tracks about to be
// replaced or removed, then the files are copied and the leftovers deleted, and the new manifest goes last (as manifest.json.part,
// renamed over the old). However it ends, the manifest on the phone names only files that are there.
SyncResult runSync(DeviceStorage &device, const SyncJob &job, const SyncProgress &progress);

// what was chosen for the phone last time (the manifest's "chosen"), or an empty map
QVariantMap readChosen(DeviceStorage &device);

// a track's id on the phone: stable across syncs, from the path of its file here
QString syncId(const QString &path);
