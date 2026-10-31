import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import App
import "../components"

// One album: its cover and what it is, Play and Shuffle, then its tracks in album order (disc, then track number).
Item {
    id: page

    required property string albumKey        // from Library.albums
    readonly property var album: Library.albums.find(a => a.key === albumKey) ?? null
    readonly property var tracks: album ? Library.albumTracks(albumKey) : []

    function formatLength(seconds) {
        const minutes = Math.round(seconds / 60)
        if (minutes < 60)
            return minutes === 1 ? qsTr("1 minute") : qsTr("%1 minutes").arg(minutes)
        return qsTr("%1 hr %2 min").arg(Math.floor(minutes / 60)).arg(minutes % 60)
    }

    component PillButton: Rectangle {
        id: pill
        required property string glyph
        required property string label
        property bool primary: false
        signal clicked()

        implicitWidth: row.implicitWidth + 28
        implicitHeight: 32
        radius: height / 2
        color: primary ? (tap.pressed ? Qt.darker(Theme.accent, 1.2) : hover.hovered ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
                       : (tap.pressed ? Theme.tint(Theme.text, Theme.selected) : hover.hovered ? Theme.tint(Theme.text, 0.12) : Theme.tint(Theme.text, Theme.hover))
        opacity: enabled ? 1 : 0.4
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: pill.clicked()
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6
            Icon { name: pill.glyph; size: 16; color: pill.primary ? Theme.accentText : Theme.text; anchors.verticalCenter: parent.verticalCenter }
            Label { text: pill.label; font.bold: true; color: pill.primary ? Theme.accentText : Theme.text; anchors.verticalCenter: parent.verticalCenter }
        }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tap; onTapped: pill.clicked() }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        visible: page.album !== null

        // the cover and what the album is
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 20
            spacing: 20
            readonly property int coverSize: page.width < 600 ? 120 : 180

            Rectangle {
                id: cover
                implicitWidth: parent.coverSize
                implicitHeight: parent.coverSize
                radius: Theme.radius
                color: Theme.tint(Theme.text, 0.08)
                border.width: 1
                border.color: Theme.hairline
                readonly property bool hasArt: art.status === Image.Ready && art.implicitWidth > 1
                Icon { anchors.centerIn: parent; name: "vinyl"; size: cover.width * 0.36; opacity: 0.3; visible: !cover.hasArt }
                Image {
                    id: art
                    anchors.fill: parent
                    source: page.album?.cover ?? ""
                    sourceSize: Qt.size(512, 512)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false      // drawn through the rounded mask below
                }
                Rectangle { id: artMask; anchors.fill: parent; radius: cover.radius; visible: false; layer.enabled: true }
                MultiEffect { anchors.fill: parent; source: art; maskEnabled: true; maskSource: artMask; visible: cover.hasArt }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBottom
                spacing: 4
                Label {
                    Layout.fillWidth: true
                    text: page.album?.title ?? ""
                    font.pixelSize: page.width < 600 ? 20 : 26
                    font.bold: true
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    text: page.album?.artist ?? ""
                    font.pixelSize: 17
                    color: Theme.accent
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    text: [page.album?.genre, page.album?.year > 0 ? page.album.year : ""].filter(s => s).join(" · ")
                    visible: text !== ""
                    font.pixelSize: 12
                    opacity: 0.6
                }
                Label {
                    Layout.fillWidth: true
                    text: [page.tracks.length === 1 ? qsTr("1 song") : qsTr("%1 songs").arg(page.tracks.length),
                           page.album?.duration > 0 ? page.formatLength(page.album.duration) : ""].filter(s => s).join(", ")
                    font.pixelSize: 12
                    opacity: 0.6
                }
                RowLayout {
                    Layout.topMargin: 10
                    spacing: 10
                    PillButton {
                        glyph: "player-play"; label: qsTr("Play"); primary: true
                        enabled: page.tracks.length > 0
                        onClicked: { Player.shuffle = false; Player.playList(page.tracks, 0) }
                    }
                    PillButton {
                        glyph: "arrows-shuffle"; label: qsTr("Shuffle")
                        enabled: page.tracks.length > 0
                        onClicked: { Player.shuffle = true; Player.playList(page.tracks, Math.floor(Math.random() * page.tracks.length)) }
                    }
                }
            }
        }

        TrackTable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            tracks: page.tracks
            sortKey: ""      // album order, until a heading is clicked
            columns: [
                { key: "trackNumber", title: "#",           width: 44,  align: Text.AlignRight, sortable: false },
                { key: "title",       title: qsTr("Title"), width: 0,   align: Text.AlignLeft },
                { key: "artist",      title: qsTr("Artist"), width: 200, align: Text.AlignLeft },
                { key: "duration",    title: qsTr("Time"),  width: 60,  align: Text.AlignRight }
            ]
        }
    }

    // the album went away (its tracks were retagged onto another, or the files are gone)
    ColumnLayout {
        anchors.centerIn: parent
        visible: page.album === null
        spacing: 10
        Icon { name: "disc"; size: 40; opacity: 0.4; Layout.alignment: Qt.AlignHCenter }
        Label { text: qsTr("This album is no longer in your library."); opacity: 0.6; Layout.alignment: Qt.AlignHCenter }
    }
}
