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
    QStringList playable;     // the file types the phone can play (suffixes)
    QStringList convertible;  // the ones it can't that are converted to AAC (.m4a) on the way, when there is an ffmpeg
    QString ffmpeg;           // ffmpeg's path (findFfmpeg), or "" to leave those off too
    bool clearChanges = false;  // the phone's playlist changes were taken (collectChanges): delete them once the new manifest is there
};

struct SyncResult {
    bool ok = false;
    QString message;          // what happened, for the person
    int copied = 0;
    int removed = 0;
    int converted = 0;        // of the copied, how many were converted to AAC
    int unplayable = 0;       // tracks left off because the phone can't play them and they couldn't be converted
};

// done and total in bytes; what: what it is doing now. Returning false stops the sync, leaving the phone with what got there.
using SyncProgress = std::function<bool(qint64 done, qint64 total, const QString &what)>;

// Brings the phone's Legato/ folder in line with the job, as docs/sync.md says: the phone's manifest first loses the tracks about to be
// replaced or removed, then the files are copied and the leftovers deleted, and the new manifest goes last (as manifest.json.part,
// renamed over the old). However it ends, the manifest on the phone names only files that are there.
SyncResult runSync(DeviceStorage &device, const SyncJob &job, const SyncProgress &progress);

// what was chosen for the phone last time (the manifest's "chosen"), or an empty map
QVariantMap readChosen(DeviceStorage &device);

// The playlist changes made on the phone (docs/sync.md, "Phone → desktop"): changes.json becomes changes.applying.json (added to one left
// from a sync that didn't finish), so changes made from now on aren't lost, and its changes come back in order. False if the phone
// couldn't be read or written; no changes is an empty list.
bool collectChanges(DeviceStorage &device, QVariantList *changes);

// a track's id on the phone: stable across syncs, from the path of its file here
QString syncId(const QString &path);

// ffmpeg, if it's installed: on the PATH, or where Homebrew and the Linux distributions put it (an app started from the Dock or Finder
// doesn't get the shell's PATH); "" if not
QString findFfmpeg();
