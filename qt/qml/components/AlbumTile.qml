import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import App

// An album as a tile: the cover, then the album and its artist underneath, Theme.albumTileText tall. Clicking it opens it (activated);
// the play button on its cover plays it.
Item {
    id: tile
    required property var album
    signal activated()

    // a stable number from a string, for the colour of a cover that has no picture
    function hash(s) {
        let h = 2166136261
        for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619)
        return h >>> 0
    }

    // the picture from the files, over a cover in a colour of its own (from the album's name) while it loads or when there is none
    Rectangle {
        id: cover
        x: Theme.gap
        width: parent.width - 2 * Theme.gap
        height: width
        radius: Theme.radius
        readonly property real hue: (tile.hash(tile.album.artist + tile.album.title) >>> 20) % 360 / 360
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.hsla(cover.hue, 0.45, 0.55, 1) }
            GradientStop { position: 1; color: Qt.hsla((cover.hue + 0.08) % 1, 0.55, 0.32, 1) }
        }
        border.width: 1
        border.color: Theme.hairline

        // (the provider answers with a 1×1 transparent image when the files have no picture)
        readonly property bool hasArt: art.status === Image.Ready && art.implicitWidth > 1
        Icon { anchors.centerIn: parent; name: "vinyl"; size: cover.width * 0.36; color: "white"; opacity: 0.35; visible: !cover.hasArt }
        Image {
            id: art
            anchors.fill: parent
            source: tile.album.cover ?? ""
            sourceSize: Qt.size(512, 512)     // fixed, so resizing the window does not load every cover again
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false      // drawn through the rounded mask below
        }
        Rectangle { id: artMask; anchors.fill: parent; radius: cover.radius; visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            source: art
            maskEnabled: true
            maskSource: artMask
            visible: cover.hasArt
        }

        // on hover: a play button, as Apple Music has
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Qt.rgba(0, 0, 0, 0.25)
            visible: hover.hovered
        }
        Rectangle {
            visible: hover.hovered
            anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
            width: 32; height: 32; radius: 16
            color: Qt.rgba(1, 1, 1, playHover.hovered ? 0.95 : 0.85)
            Icon { anchors.centerIn: parent; anchors.horizontalCenterOffset: 1; name: "player-play"; size: 16; color: "black" }
            HoverHandler { id: playHover; cursorShape: Qt.PointingHandCursor }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Play %1").arg(tile.album.title)
            MouseArea { anchors.fill: parent; onClicked: Player.playList(Library.albumTracks(tile.album.key), 0) }
        }
    }

    Label {
        id: title
        anchors { top: cover.bottom; topMargin: 6; left: cover.left; right: cover.right }
        text: tile.album.title
        elide: Text.ElideRight
        font.pixelSize: 13
    }
    Label {
        anchors { top: title.bottom; topMargin: 1; left: cover.left; right: cover.right }
        text: tile.album.artist
        elide: Text.ElideRight
        font.pixelSize: 12
        opacity: 0.6
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: tile.activated() }
}
