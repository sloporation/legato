import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import App

// The left-hand card: the library (artists, albums, songs), then the playlists (the .m3u files in the music folders). A "+" makes a new
// playlist. At the bottom, the settings.
Card {
    id: bar

    // what the page is showing: "artists", "albums", "songs" or "playlist" (the one at playlistPath)
    property string page: ""
    property string playlistPath: ""
    signal openPage(string page)
    signal openPlaylist(string path)
    signal newPlaylist()
    signal openSettings()

    component SectionLabel: Label {
        Layout.leftMargin: 18
        Layout.topMargin: 14
        Layout.bottomMargin: 4
        font.pixelSize: 11
        font.bold: true
        font.capitalization: Font.AllUppercase
        opacity: 0.55
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.bottomMargin: 8
        spacing: 2

        Item {
            Layout.fillWidth: true
            implicitHeight: Theme.headerHeight
            Label {
                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                text: qsTr("Legato")
                font.bold: true
                font.pixelSize: 15
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.hairline }
        }

        SectionLabel { text: qsTr("Library") }
        Repeater {
            model: [
                ["artists", "microphone-2", qsTr("Artists")],
                ["albums",  "disc",         qsTr("Albums")],
                ["songs",   "music",        qsTr("Songs")]
            ]
            delegate: SidebarRow {
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                glyph: modelData[1]
                label: modelData[2]
                selected: bar.page === modelData[0]
                onClicked: bar.openPage(modelData[0])
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: 12
            SectionLabel { text: qsTr("Playlists"); Layout.fillWidth: true }
            Rectangle {
                Layout.topMargin: 10
                implicitWidth: 22; implicitHeight: 22; radius: 11
                color: addHover.hovered ? Theme.tint(Theme.text, Theme.hover) : "transparent"
                Icon { anchors.centerIn: parent; name: "plus"; size: 15; opacity: 0.7 }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("New playlist")
                HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: bar.newPlaylist() }
                ToolTip.visible: addHover.hovered
                ToolTip.delay: 500
                ToolTip.text: qsTr("New playlist")
            }
        }

        ListView {
            id: playlists
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            spacing: 2
            model: Library.playlists
            ScrollBar.vertical: ScrollBar {}
            WheelScroll { view: playlists }
            delegate: SidebarRow {
                required property var modelData
                width: ListView.view.width
                glyph: "playlist"
                label: modelData.name
                selected: bar.page === "playlist" && bar.playlistPath === modelData.path
                onClicked: bar.openPlaylist(modelData.path)
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.hairline }
        SidebarRow {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 6
            glyph: "settings"
            label: Qt.platform.os === "osx" ? qsTr("Settings…") : qsTr("Settings")
            onClicked: bar.openSettings()
        }
    }
}
