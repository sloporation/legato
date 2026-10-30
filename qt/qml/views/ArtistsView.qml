import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import App
import "../components"

// The artists, as Apple Music has them: a column of every artist at the left, and the one chosen at the right with their albums, then
// the albums they appear on (a feature, or a track on someone else's album). Artists who are only ever featured say so in the column.
Item {
    id: page

    // the artist showing (kept by the window, so coming back from an album returns to them); the first one when it is not in the library
    property string artistName: ""
    signal selected(string name)
    signal activated(var album)

    readonly property int current: Math.max(0, Library.artists.findIndex(a => a.name === artistName))
    readonly property var artist: Library.artists[current] ?? null

    function count(n, one, many) { return n + " " + (n === 1 ? one : many) }
    // an album's tracks as this page lists them: all of their own album, just theirs on someone else's
    function tracksOf(album) {
        const tracks = Library.albumTracks(album.key)
        return album.trackIds === undefined ? tracks : tracks.filter(t => album.trackIds.includes(t.id))
    }
    function allTracks() {
        if (!artist) return []
        return artist.albums.concat(artist.appearsOn).reduce((all, album) => all.concat(tracksOf(album)), [])
    }
    function formatTime(seconds) {
        const s = Math.floor(seconds % 60)
        return Math.floor(seconds / 60) + ":" + (s < 10 ? "0" : "") + s
    }

    // a round button in the header, as Apple Music has: the accent colour for Play
    component RoundButton: Rectangle {
        id: button
        required property string glyph
        required property string label
        property bool primary: false
        signal clicked()
        implicitWidth: 32
        implicitHeight: 32
        radius: 16
        enabled: page.artist !== null
        color: buttonTap.pressed ? Theme.tint(Theme.text, Theme.selected) : buttonHover.hovered ? Theme.tint(Theme.text, 0.12) : Theme.tint(Theme.text, Theme.hover)
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: button.clicked()
        Icon {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: button.glyph === "player-play" ? 1 : 0
            name: button.glyph
            size: 16
            color: button.primary ? Theme.accent : Theme.text
        }
        HoverHandler { id: buttonHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: buttonTap; onTapped: button.clicked() }
    }

    // one album on the artist's page: the cover (click it to open the album), and beside it the title, genre and year, then its tracks.
    // A double-click on a track plays the album's tracks from it.
    component ArtistAlbum: GridLayout {
        id: block
        required property var album
        readonly property var tracks: page.tracksOf(album)
        width: parent?.width ?? 0
        columns: detail.narrow ? 1 : 2
        columnSpacing: 30
        rowSpacing: 16

        Item { implicitHeight: 30; Layout.columnSpan: block.columns; Layout.fillWidth: true }      // between albums

        Rectangle {
            id: cover
            Layout.alignment: Qt.AlignTop
            implicitWidth: detail.coverSize
            implicitHeight: detail.coverSize
            radius: Theme.radius
            color: Theme.tint(Theme.text, 0.08)
            border.width: 1
            border.color: Theme.hairline
            readonly property bool hasArt: art.status === Image.Ready && art.implicitWidth > 1
            Icon { anchors.centerIn: parent; name: "vinyl"; size: cover.width * 0.36; opacity: 0.3; visible: !cover.hasArt }
            Image {
                id: art
                anchors.fill: parent
                source: block.album.cover ?? ""
                sourceSize: Qt.size(512, 512)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false      // drawn through the rounded mask below
            }
            Rectangle { id: artMask; anchors.fill: parent; radius: cover.radius; visible: false; layer.enabled: true }
            MultiEffect { anchors.fill: parent; source: art; maskEnabled: true; maskSource: artMask; visible: cover.hasArt }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: page.activated(block.album) }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Open %1").arg(block.album.title)
        }

        Column {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Label {
                width: parent.width
                text: block.album.title
                font.pixelSize: 17
                font.bold: true
                elide: Text.ElideRight
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: page.activated(block.album) }
            }
            Label {
                width: parent.width
                topPadding: 4
                bottomPadding: 14
                // on someone else's album: whose it is
                text: [block.album.trackIds !== undefined ? block.album.artist : "", block.album.genre,
                       block.album.year > 0 ? block.album.year : ""].filter(s => s).join(" · ")
                font.pixelSize: 12
                opacity: 0.6
                elide: Text.ElideRight
            }
            Rectangle { width: parent.width; height: 1; color: Theme.hairline }
            Repeater {
                model: block.tracks
                Rectangle {
                    id: trackRow
                    required property var modelData
                    required property int index
                    readonly property bool isPlaying: Player.current.path === modelData.path
                    width: parent.width
                    height: 44
                    color: trackHover.hovered ? Theme.tint(Theme.text, Theme.hover) : "transparent"
                    radius: Theme.radius

                    Item {
                        id: number
                        width: 34
                        height: parent.height
                        Label {
                            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                            visible: !trackRow.isPlaying
                            text: trackRow.modelData.trackNumber > 0 ? trackRow.modelData.trackNumber : ""
                            opacity: 0.6
                        }
                        Icon {
                            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                            visible: trackRow.isPlaying
                            name: Player.playing ? "volume" : "player-pause"
                            size: 14
                            color: Theme.accent
                        }
                    }
                    Column {
                        anchors { left: number.right; right: time.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        Label {
                            width: parent.width
                            text: trackRow.modelData.title
                            elide: Text.ElideRight
                            color: trackRow.isPlaying ? Theme.accent : Theme.text
                        }
                        // a track by someone else as well (a feature, a compilation)
                        Label {
                            width: parent.width
                            readonly property string credit: trackRow.modelData.artist ?? ""
                            visible: credit !== "" && credit !== block.album.artist
                            text: credit
                            font.pixelSize: 11
                            opacity: 0.6
                            elide: Text.ElideRight
                        }
                    }
                    Label {
                        id: time
                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        text: trackRow.modelData.duration > 0 ? page.formatTime(trackRow.modelData.duration) : ""
                        opacity: 0.6
                        font.features: { "tnum": 1 }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.hairline }

                    HoverHandler { id: trackHover }
                    TapHandler { onDoubleTapped: { Player.shuffle = false; Player.playList(block.tracks, trackRow.index) } }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: trackRow.modelData.title
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        ListView {
            id: list
            Layout.preferredWidth: Math.min(Theme.artistListWidth, page.width * 0.4)
            Layout.fillHeight: true
            topMargin: 8
            bottomMargin: 8
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            focus: true
            keyNavigationEnabled: false     // (the arrows choose the artist below, so the list only follows the page)
            model: Library.artists
            currentIndex: page.current
            function step(by) {
                const i = Math.max(0, Math.min(count - 1, page.current + by))
                if (Library.artists[i]) page.selected(Library.artists[i].name)
                positionViewAtIndex(i, ListView.Contain)
            }
            Keys.onUpPressed: step(-1)
            Keys.onDownPressed: step(1)
            ScrollBar.vertical: ScrollBar {}
            WheelScroll { view: list }

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool isCurrent: ListView.isCurrentItem
                x: 8
                width: list.width - 16
                height: 40
                radius: Theme.radius
                color: isCurrent ? Theme.accent
                     : tap.pressed ? Theme.tint(Theme.text, Theme.selected)
                     : hover.hovered ? Theme.tint(Theme.text, Theme.hover) : "transparent"
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.name

                // their first album's cover in a circle, or the first letter of their name
                Rectangle {
                    id: avatar
                    anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 28; height: 28; radius: 14
                    color: Theme.tint(row.isCurrent ? Theme.accentText : Theme.text, 0.12)
                    readonly property bool hasArt: art.status === Image.Ready && art.implicitWidth > 1
                    Label {
                        anchors.centerIn: parent
                        visible: !avatar.hasArt
                        text: row.modelData.name.charAt(0).toUpperCase()
                        font.bold: true
                        color: row.isCurrent ? Theme.accentText : Theme.text
                        opacity: 0.7
                    }
                    Image {
                        id: art
                        anchors.fill: parent
                        source: row.modelData.cover ?? ""
                        sourceSize: Qt.size(64, 64)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false      // drawn through the round mask below
                    }
                    Rectangle { id: artMask; anchors.fill: parent; radius: avatar.radius; visible: false; layer.enabled: true }
                    MultiEffect { anchors.fill: parent; source: art; maskEnabled: true; maskSource: artMask; visible: avatar.hasArt }
                }
                Column {
                    anchors { left: avatar.right; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    Label {
                        width: parent.width
                        text: row.modelData.name
                        elide: Text.ElideRight
                        color: row.isCurrent ? Theme.accentText : Theme.text
                    }
                    Label {
                        width: parent.width
                        visible: row.modelData.featuredOnly
                        text: qsTr("Featured")
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        color: row.isCurrent ? Theme.accentText : Theme.text
                        opacity: 0.6
                    }
                }

                HoverHandler { id: hover }
                TapHandler { id: tap; onTapped: { list.forceActiveFocus(); page.selected(row.modelData.name) } }
            }
        }

        Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.hairline }

        // the artist chosen: Play and Shuffle for everything of theirs, then each album of theirs with its tracks beside the cover, then
        // the albums they appear on with just their tracks
        Flickable {
            id: detail
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            contentHeight: content.implicitHeight + 2 * padding
            ScrollBar.vertical: ScrollBar {}
            WheelScroll { view: detail }
            // a different artist starts at the top
            Connections { target: page; function onArtistChanged() { detail.contentY = 0 } }

            readonly property int padding: 30
            readonly property bool narrow: width < 640     // the cover goes above the tracks
            readonly property int coverSize: narrow ? 160 : Math.min(240, Math.round(width * 0.28))

            Column {
                id: content
                x: detail.padding
                y: detail.padding
                width: detail.width - 2 * detail.padding
                spacing: 0
                visible: page.artist !== null

                RowLayout {
                    width: parent.width
                    spacing: 12
                    Label {
                        Layout.fillWidth: true
                        text: page.artist?.name ?? ""
                        font.pixelSize: page.width < 600 ? 20 : 26
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    RoundButton {
                        glyph: "player-play"; label: qsTr("Play"); primary: true
                        onClicked: { Player.shuffle = false; Player.playList(page.allTracks(), 0) }
                    }
                    RoundButton {
                        glyph: "arrows-shuffle"; label: qsTr("Shuffle")
                        onClicked: { const t = page.allTracks(); Player.shuffle = true; Player.playList(t, Math.floor(Math.random() * t.length)) }
                    }
                }
                Item { width: 1; height: 12 }
                Rectangle { width: parent.width; height: 1; color: Theme.hairline }
                Label {
                    topPadding: 8
                    text: page.artist ? [page.artist.albums.length > 0 ? page.count(page.artist.albums.length, qsTr("album"), qsTr("albums")) : "",
                                         page.count(page.artist.songCount, qsTr("song"), qsTr("songs"))].filter(s => s).join(", ") : ""
                    font.pixelSize: 12
                    opacity: 0.6
                }

                Repeater {
                    model: page.artist?.albums ?? []
                    ArtistAlbum { required property var modelData; album: modelData }
                }
                Label {
                    visible: (page.artist?.appearsOn.length ?? 0) > 0
                    topPadding: 40
                    text: qsTr("Appears On")
                    font.pixelSize: 20
                    font.bold: true
                }
                Repeater {
                    model: page.artist?.appearsOn ?? []
                    ArtistAlbum { required property var modelData; album: modelData }
                }
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        visible: Library.artists.length === 0
        spacing: 10
        Icon { name: "microphone-2"; size: 40; opacity: 0.4; Layout.alignment: Qt.AlignHCenter }
        Label { text: Library.scanning ? qsTr("Looking for music…") : qsTr("No artists yet."); opacity: 0.6; Layout.alignment: Qt.AlignHCenter }
    }
}
