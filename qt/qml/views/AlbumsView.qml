import QtQuick
import QtQuick.Controls
import App
import "../components"

// Every album as a tile: the cover, then the album and its artist underneath. The tiles grow to fill each row. Clicking one opens it
// (activated); the play button on its cover plays it.
GridView {
    id: grid

    signal activated(var album)


    readonly property int padding: 20
    readonly property int columns: Math.max(1, Math.floor((width - 2 * padding) / (Theme.albumTileMin + Theme.gap * 2)))

    leftMargin: padding
    rightMargin: padding
    topMargin: padding
    bottomMargin: padding
    cellWidth: Math.floor((width - 2 * padding) / columns)
    cellHeight: cellWidth + Theme.albumTileText
    clip: true
    interactive: false
    boundsBehavior: Flickable.StopAtBounds
    model: Library.albums
    ScrollBar.vertical: ScrollBar {}
    WheelScroll { view: grid }

    delegate: AlbumTile {
        required property var modelData
        album: modelData
        width: grid.cellWidth
        height: grid.cellHeight
        onActivated: grid.activated(modelData)
    }
}
