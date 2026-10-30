import QtQuick
import App
import "../components"

// The tracks of one playlist (an .m3u file), in its order until a column is clicked.
TrackTable {
    required property string playlistPath

    sortKey: ""
    tracks: (Library.playlists.find(p => p.path === playlistPath)?.tracks ?? []).map(id => Library.tracks[id])
}
