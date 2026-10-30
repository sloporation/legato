# Syncing music to the phone and the watch

Legato Desktop puts the music you choose onto Legato for iPhone over USB. Legato for iPhone puts the music you choose from that onto
Legato for Apple Watch. There is no server and no network: the desktop writes files into the phone app's Documents folder, the way
Finder's file sharing does, and the phone hands files to the watch with WatchConnectivity.

## Desktop → iPhone (USB)

The desktop talks to the iPhone with libimobiledevice (through usbmuxd, the same system service Finder and Xcode use). The phone must
trust the computer once ("Trust This Computer?"). Legato for iPhone sets `UIFileSharingEnabled`, so its Documents folder can be written
over USB with the `house_arrest` service (`VendDocuments`), whether or not the app is running.

Everything Legato writes lives in one folder, `Documents/Legato/`:

```
Legato/
  manifest.json          what is synced: the tracks (with their tags) and the playlists
  Music/<id>.<ext>       one file per track, as it is on the desktop (or converted, if the phone can't play the original)
  Covers/<hash>.jpg      album covers, extracted by the desktop (600 px)
```

A sync:

1. reads the phone's `Legato/manifest.json`, if there is one;
2. copies the files that are new or changed (by `id`, `size` and `modified`), and deletes the ones no longer wanted;
3. writes `manifest.json` last, as `manifest.json.part` renamed over the old one, so an unplugged cable never leaves a manifest that
   names files that aren't there.

The phone reads the manifest when it comes to the foreground, and when it changes while the app is open.

Legato Desktop shows a phone in its sidebar under Devices while it is plugged in. Its page chooses what goes on it: everything, or some
playlists, artists and albums; Sync does the rest. Files the phone can't play are left off (the iPhone takes MP3, AAC/ALAC, WAV, AIFF and
FLAC; Android also Ogg Vorbis, Opus and Matroska audio). Covers are named after a hash of the JPEG, so a changed cover arrives as a new
file. On Linux, iPhones need the `usbmuxd` service running. Windows can't sync yet.

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

## iPhone → Apple Watch (WatchConnectivity)

The iPhone app keeps its own choice of playlists, albums and artists for the watch. Sending:

- each track file not yet on the watch goes with `transferFile` (metadata `{"kind": "track", "file": "Music/<id>.<ext>"}`), and so does
  each cover (`"kind": "cover"`);
- then a manifest of just the chosen music, in the same format, goes as a file (`"kind": "manifest"`).

The watch keeps the files under its own `Documents/Legato/`, writes the manifest there, and deletes the files the manifest no longer
names. Transfers continue in the background and may arrive in any order, so the watch only shows tracks whose file has arrived. The
watch tells the phone what it has (`transferUserInfo`, `{"have": [ids]}`) so nothing is sent twice.
