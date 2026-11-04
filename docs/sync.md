# Syncing music to the phone and the watch

Legato Desktop puts the music you choose onto Legato for iPhone over USB. Legato for Mac does the same over Wi-Fi. Legato for iPhone
puts the music you choose from that onto Legato for Apple Watch. Over USB there is no server and no network: the desktop writes files
into the phone app's Documents folder, the way Finder's file sharing does, and the phone hands files to the watch with
WatchConnectivity.

## Desktop → iPhone (USB)

The desktop talks to the iPhone with libimobiledevice (through usbmuxd, the same system service Finder and Xcode use). The phone must
trust the computer once ("Trust This Computer?"). Legato for iPhone sets `UIFileSharingEnabled`, so its Documents folder can be written
over USB with the `house_arrest` service (`VendDocuments`), whether or not the app is running.

Everything Legato writes lives in one folder, `Documents/Legato/`:

```
Legato/
  manifest.json          what is synced: the tracks (with their tags) and the playlists
  Music/<id>.<ext>       one file per track, as it is on the desktop (or converted to .m4a, if the phone can't play the original)
  Covers/<hash>.jpg      album covers, extracted by the desktop (600 px)
```

A sync:

1. reads the phone's `Legato/manifest.json`, if there is one;
2. copies the files that are new or changed (by `id`, `size` and `modified`), and deletes the ones no longer wanted;
3. writes `manifest.json` last, as `manifest.json.part` renamed over the old one, so an unplugged cable never leaves a manifest that
   names files that aren't there.

The phone reads the manifest when it comes to the foreground, and when it changes while the app is open.

Legato Desktop shows a phone in its sidebar under Devices while it is plugged in. Its page chooses what goes on it: everything, or some
playlists, artists and albums; Sync does the rest. Files the phone can't play are converted to AAC (256 kbps `.m4a`) with ffmpeg on the way: on
the iPhone, anything but MP3, AAC/ALAC, WAV, AIFF and FLAC (so Opus, Ogg Vorbis and WebM/Matroska audio); on Android, the few formats
ExoPlayer doesn't take (WMA, APE, WavPack and the like). The converted file keeps the original's `id`, `size` and `modified` in the
manifest, so it is only converted again when the original changes. Without ffmpeg, those files are left off. Covers are named after a hash of the JPEG, so a changed cover arrives as a new
file. On Linux, iPhones need the `usbmuxd` service running. Windows can't sync yet.

## Legato for Mac → iPhone (Wi-Fi)

Legato for Mac is sandboxed for the Mac App Store, which rules out usbmuxd, so it syncs over the local network instead. The phone ends
up with the same `Legato/` folder, kept the same way, so it doesn't matter which app last synced it (both name tracks by the same hash
of the file's path).

Finding, pairing and connecting are [Tether](https://github.com/sloporation/tether)'s, which Liftbro uses too (its README has the
details). The Mac advertises `_legato._tcp` with Bonjour; Sync with Mac on the phone finds it. The first time, the phone pairs: a
Curve25519 key agreement, with the phone committing to its half first, gives both the same key and the same six-digit code, which the
Mac shows with "“iPhone” wants to sync with this Mac"; the person checks it and allows the phone. After that they connect over TLS 1.2
with that key (`TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256`), and the phone proves which phone it is. Both keep the keys in the
Keychain. If the Mac has forgotten the phone, the phone is told so and pairs again. Tether's configuration (`ios/Sync/SyncWire.swift`)
has the label `legato`.

Over that connection, each message is a 4-byte big-endian length and that much JSON; a reply that says `size` is followed by that many
bytes of a file. The phone asks and the Mac answers:

1. `{"op": "hello", "chosen": {…}, "batch": "…", "changes": […]}`. The Mac makes the playlist changes, then answers with the manifest
   of what the phone is to have (`{"ok": true, "manifest": {…}}`), its files named `Music/<id>.<ext>` and `Covers/<hash>.jpg`.
2. `{"op": "file", "path": "Music/<id>.flac"}` for each file the phone hasn't got (by `id`, `size` and `modified`, as over USB), and
   each cover. The phone writes it as `.part` and renames it into place.
3. The phone writes the manifest, deletes what it no longer names, and says `{"op": "done"}`; the Mac answers once it has noted it.

(Byte strings are base64 in the JSON.)

What a phone gets is chosen on the Mac, under Phones (everything, or playlists, artists and albums), starting from the manifest's
`chosen` the first time. Playlist changes go as over USB, except that the phone sends them: `changes.json` goes onto the end of
`changes.applying.json`, which has a `batch` name; the Mac remembers how many of a batch it has made, so a sync that didn't finish
never makes one twice. The phone deletes `changes.applying.json` once it has the new manifest.

## Desktop → Android (USB)

Android phones take files over USB as MTP (they show up as a drive), once their USB connection is set to "File transfer". The desktop
uses libmtp, so another program holding the phone (Android File Transfer, a photo importer) has to let go first. It writes the same `Legato/` folder as for the iPhone
into the phone's shared storage, at `Music/Legato/`, the same way: changed files first, `manifest.json` last. Android only lets an app
read such a folder once the person has chosen it in the system's folder picker, so Legato for Android asks once, on first launch (the
picker opens at Music › Legato), and keeps that permission. It reads the manifest when it comes to the foreground and every few seconds
while it's open, and plays the files where they are.

## `manifest.json`

```json
{
  "version": 1,
  "generated": "2026-10-30T12:00:00Z",
  "source": "Legato on Jacob's MacBook",
  "tracks": [
    {
      "id": "3f2a…",                       // stable across syncs: the desktop's hash of the source file's path
      "file": "Music/3f2a….opus",          // relative to Legato/
      "title": "Critical Acclaim",
      "artist": "Avenged Sevenfold",
      "album": "Avenged Sevenfold",
      "albumArtist": "Avenged Sevenfold",
      "genre": "Rock",
      "year": 2007,
      "trackNumber": 1,
      "discNumber": 1,
      "duration": 315.18,                  // seconds; 0 when the file doesn't say
      "size": 5223493,                     // bytes, and
      "modified": "2026-10-30T10:19:00Z",  // the source's modification time: together, whether the copy is out of date
      "cover": "Covers/9c1e….jpg"          // optional
    }
  ],
  "playlists": [
    { "name": "Rainy Day", "tracks": ["3f2a…", "…"] }    // in playlist order
  ],
  "chosen": {                              // what was chosen for this phone on the desktop's Devices page, so the next sync
    "everything": false,                   // (from any computer) starts from it; the phones ignore it
    "playlists": ["Rainy Day"],
    "artists": ["Avenged Sevenfold"],
    "albums": ["avenged sevenfold\u001favenged sevenfold"]   // album artist and title, case-folded, joined by U+001F
  }
}
```

Albums and artists are not listed: both apps group the tracks themselves, the same way the desktop does (album artist, else artist, and
the album title, ignoring case). Unknown keys are ignored and missing ones take their defaults, so either side can add fields.

## Phone → desktop: playlist changes

Playlists can be changed on the phone: made, renamed, deleted, and songs added, removed and moved. The phone doesn't touch the manifest
for that (the desktop owns it); it writes what was done to `Legato/changes.json`, and shows the manifest's playlists with those changes
made. The next sync takes them to the desktop's playlist files, before it works out what the phone is to have, so the new manifest has
them in.

```json
{
  "version": 1,
  "changes": [                                                          // in the order they were made
    { "op": "create", "playlist": "Gym",     "at": "2026-10-31T09:00:00Z" },
    { "op": "add",    "playlist": "Gym",     "track": "3f2a…" },        // onto the end
    { "op": "move",   "playlist": "Gym",     "track": "3f2a…", "after": "9c1e…" },   // no "after": to the top
    { "op": "remove", "playlist": "Gym",     "track": "9c1e…" },
    { "op": "rename", "playlist": "Gym",     "to": "Lifting" },
    { "op": "delete", "playlist": "Old" }
  ]
}
```

Playlists are named, tracks are ids. A change is made only as far as it still can be: `create` of a playlist that is there, `add` of a
song already in it, `remove` of one that isn't, `rename` or `delete` of a playlist that isn't there, do nothing. On the desktop that is also what happens to a change that no longer fits (the playlist was deleted there, the
song is no longer in the library): it is left out, and the sync says so. Songs in a desktop playlist that aren't on the phone stay where
they are; `move` places a song after the one named, wherever that is in the file. A playlist deleted on the phone goes to the desktop's
Trash.

So that nothing written on the phone during a sync is lost, the desktop first renames `changes.json` to `changes.applying.json` (adding
its changes to one left over from a sync that didn't finish), makes the changes, writes how many it made into it (`"applied": 11`), and
deletes it once the new manifest is written. A sync that finds `"applied"` in a left-over `changes.applying.json` makes only the changes
after those: making a change twice needn't come to the same thing (`create` a playlist that was then renamed makes it again). The phone
shows the manifest with the changes in `changes.applying.json` and then those in `changes.json` made.

## iPhone → Apple Watch (WatchConnectivity)

The iPhone app keeps its own choice of playlists, albums and artists for the watch. Sending:

- each track file not yet on the watch goes with `transferFile` (metadata `{"kind": "track", "file": "Music/<id>.<ext>"}`), and so does
  each cover (`"kind": "cover"`);
- then a manifest of just the chosen music, in the same format, goes as a file (`"kind": "manifest"`).

The watch keeps the files under its own `Documents/Legato/`, writes the manifest there, and deletes the files the manifest no longer
names. Transfers continue in the background and may arrive in any order, so the watch only shows tracks whose file has arrived. The
watch tells the phone what it has (`transferUserInfo`, `{"have": [ids]}`) so nothing is sent twice.

## The watch as a remote

While the iPhone is in reach (`WCSession.isReachable`), Legato on the watch is a remote for Legato on the iPhone: it shows the iPhone's
library, and what it chooses plays on the iPhone, through whatever the iPhone plays through (headphones go with the iPhone while it's
near). Out of reach for more than a few seconds, the watch shows and plays the music synced to it, as above. The two talk with
`sendMessage`, which wakes the iPhone app if it isn't running; every message from the watch gets an answer.

- `{"op": "catalog", "have": "<version>"}`: the iPhone's library, as a manifest of its tracks (without covers) and playlists, JSON
  compressed with LZFSE. The answer is `{"version": "<hash of it>", "pieces": n}`, with `n` 0 when the watch has that version
  already; the watch then asks `{"op": "piece", "version": …, "index": i}` for each, which answers `{"data": <up to 48 KB>}`. The
  watch keeps it, so it shows at once next time. The iPhone says `{"op": "catalog-changed"}` when its library changes.
- `{"op": "play", "source": "playlist" | "album" | "artist" | "songs", "name": "<playlist or artist name, or album id>", "track":
  "<id>", "shuffle": true}`: the iPhone makes the list from its own library (both group the tracks the same way) and plays it from
  that track, or shuffled.
- `{"op": "toggle"}`, `{"op": "next"}`, `{"op": "previous"}`, `{"op": "state"}`.

Each of those but the catalog's answers with what's playing: `{"track": <the track, as JSON>, "playing": true, "position": 12.5,
"duration": 200, "at": <seconds since 1970>, "problem": "…"}`, and the cover (`"art"`, a small JPEG, with `"artFor"`, the track's
id) when the watch hasn't got it: each message says which track's cover it has (`"art": "<id>"`). The iPhone also sends the state
(`"op": "state"`) when the track changes or it starts or stops, while the watch app is open; the watch asks every few seconds too, and
counts the position on in between. The crown sets the iPhone's volume.
