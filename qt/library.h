#pragma once

#include <QObject>
#include <QQuickImageProvider>
#include <QThread>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>
#include <atomic>

#include "folderwatcher.h"

class Settings;

// The music in the folders Legato looks after, for QML as the `Library` singleton. The files are the library: the tags in them say what a
// track is, and the playlists are the .m3u/.m3u8 files beside them. Nothing else is stored.
//
// A scan runs on a thread of its own. When the folders themselves change (in the settings window or in legato.yaml) it starts afresh and
// hands the tracks over in batches as it finds them, so the table fills while it works. Otherwise it looks again quietly and swaps the
// result in only if something is different: when the folders' contents change (a few seconds after the last change), every so often in
// case a change went unnoticed (network drives often send no events), and on rescan().
class Library : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // [{ id, path, title, artist, artists (the ARTISTS tag's names, if any), album, albumArtist, genre, year, trackNumber, discNumber,
    //    duration (seconds) }], id = index
    Q_PROPERTY(QVariantList tracks READ tracks NOTIFY tracksChanged)
    // [{ key, title, artist, year, genre, trackCount, duration (s), cover (an image: URL) }], by artist then title
    Q_PROPERTY(QVariantList albums READ albums NOTIFY tracksChanged)
    // [{ name, albums: [as in albums], appearsOn: [as in albums], songCount, featuredOnly, cover (its first album's) }], by name with any
    // leading "The" aside. Anyone a track credits is an artist: the album artist, the track's artists, and anyone featured in its title.
    // albums are the ones they are the album artist of, newest first; appearsOn the others they are on, each with trackIds: the tracks
    // on it that credit them.
    Q_PROPERTY(QVariantList artists READ artists NOTIFY tracksChanged)
    // [{ name, path, tracks: [track ids], missing (entries not found in the library) }], by name
    Q_PROPERTY(QVariantList playlists READ playlists NOTIFY playlistsChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged)
public:
    explicit Library(Settings *settings, QObject *parent = nullptr);
    ~Library() override;
    static Library *create(QQmlEngine *qml, QJSEngine *js);

    QVariantList tracks() const { return m_tracks; }
    QVariantList albums() const { return m_albums; }
    QVariantList artists() const { return m_artists; }
    QVariantList playlists() const { return m_playlists; }
    bool scanning() const { return m_thread != nullptr && m_showScan; }     // a scan nobody asked for runs unannounced

    Q_INVOKABLE void rescan();
    // an empty playlist file in the first music folder; returns its index in playlists, or -1
    Q_INVOKABLE int createPlaylist(const QString &name);

    // A file's tags as text, for the edit window: title, artist, album, albumArtist, genre, date, trackNumber, trackTotal, discNumber,
    // discTotal; and about the file: format, bitrate (kbps), sampleRate (Hz), channels, duration (s).
    Q_INVOKABLE QVariantMap tagsForEditing(const QString &path) const;
    // Writes those tags (the same keys; "" removes one) into the file, leaving every other tag and the pictures as they were. The library
    // shows the change at once. Returns "" when it worked, else why not.
    Q_INVOKABLE QString writeTags(const QString &path, const QVariantMap &tags);
    // the same tags into several files at once (each keeps its own track and disc numbers unless they are among the tags); "" when
    // every file took them, else which did not and why
    Q_INVOKABLE QString writeTagsMany(const QStringList &paths, const QVariantMap &tags);
    // the file in Finder (Explorer, the file manager), selected where the system allows it
    Q_INVOKABLE void reveal(const QString &path) const;
    // an album's tracks (by its `key` from albums), in disc and track order, then by title for tracks with no number
    Q_INVOKABLE QVariantList albumTracks(const QString &key) const;

signals:
    void tracksChanged();
    void playlistsChanged();
    void scanningChanged();
    void failed(const QString &message);
    void trackEdited(const QVariantMap &track);     // its tags were rewritten: anything holding a copy of it can refresh

private:
    // fresh: start from an empty library and show tracks as they are found. Otherwise build it aside and swap it in at the end.
    void startScan(bool fresh, bool shown);
    void lookAgain();     // a change was seen, or it is time: a quiet scan, now or once the running one ends
    void stopScan();
    void addTracks(const QVariantList &batch);
    void setPlaylists(QVariantList playlists);
    QString saveTags(const QString &path, const QVariantMap &tags);     // into the file only; "" or why not
    void showEdits(const QStringList &paths);     // the library takes the files' new tags
    void rebuildAlbums();     // (and the artists, which are made of the albums)
    void rebuildArtists();

    Settings *m_settings;
    QVariantList m_tracks;
    QVariantList m_albums;
    QVariantList m_artists;
    QVariantList m_playlists;
    QThread *m_thread = nullptr;
    bool m_showScan = false;
    bool m_lookAgain = false;      // something changed while a scan was running
    FolderWatcher m_watcher;
    QTimer m_settle;               // waits for a burst of changes (an album being copied in) to finish
    QTimer m_periodic;
    std::atomic<int> m_generation { 0 };   // bumped to tell a running scan its results are no longer wanted
};

// image://cover/<percent-encoded path of a track>: the picture embedded in the file, or a cover.jpg/folder.jpg beside it.
class CoverProvider : public QQuickImageProvider {
public:
    CoverProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};
