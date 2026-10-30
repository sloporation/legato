import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import App
import "components"

// The settings, in a window of their own (Cmd+, on macOS, Ctrl+, elsewhere). Everything here is in legato.yaml too, which can be edited
// by hand: Legato picks the changes up when the file is saved.
Window {
    id: win

    title: qsTr("Settings")
    width: 600
    height: 460
    minimumWidth: 460
    minimumHeight: 360
    color: Theme.canvas
    palette.windowText: Theme.text
    palette.text: Theme.text
    palette.buttonText: Theme.text
    palette.highlight: Theme.accent

    Shortcut { sequences: [StandardKey.Close]; onActivated: win.close() }

    component Heading: Label { font.bold: true; font.pixelSize: 13 }
    component Note: Label { Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.6; font.pixelSize: 12 }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 8

        Heading { text: qsTr("Music folders") }
        Note { text: qsTr("Legato finds the music in these folders and keeps the tags in its files up to date. Playlists are the .m3u files in them; new ones go in the first folder.") }

        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 4
            radius: Theme.radius * 2

            ListView {
                id: dirs
                anchors.fill: parent
                anchors.margins: 6
                clip: true
                interactive: false
                boundsBehavior: Flickable.StopAtBounds
                model: Settings.musicDirs
                ScrollBar.vertical: ScrollBar {}
                WheelScroll { view: dirs }

                delegate: Rectangle {
                    id: dirRow
                    required property string modelData
                    required property int index
                    width: ListView.view.width
                    height: 34
                    radius: Theme.radius
                    color: rowHover.hovered ? Theme.tint(Theme.text, Theme.hover) : "transparent"

                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 6 }
                        spacing: 10
                        Icon { name: "folder"; color: Theme.accent }
                        Label { text: dirRow.modelData; elide: Text.ElideMiddle; Layout.fillWidth: true }
                        Rectangle {
                            implicitWidth: 24; implicitHeight: 24; radius: 12
                            visible: rowHover.hovered
                            color: removeHover.hovered ? Theme.tint(Theme.text, Theme.selected) : "transparent"
                            Icon { anchors.centerIn: parent; name: "minus"; size: 15 }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Remove %1").arg(dirRow.modelData)
                            HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Settings.removeMusicDir(dirRow.index) }
                            ToolTip.visible: removeHover.hovered
                            ToolTip.delay: 500
                            ToolTip.text: qsTr("Stop looking after this folder (the files stay where they are)")
                        }
                    }
                    HoverHandler { id: rowHover }
                }

                Label {
                    anchors.centerIn: parent
                    visible: dirs.count === 0
                    text: qsTr("No folders yet")
                    opacity: 0.55
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Button { text: qsTr("Add Folder…"); onClicked: folderDialog.open() }
            Button { text: qsTr("Rescan"); enabled: !Library.scanning && Settings.musicDirs.length > 0; onClicked: Library.rescan() }
            Label {
                Layout.fillWidth: true
                opacity: 0.6
                elide: Text.ElideRight
                text: Library.scanning ? qsTr("Scanning… %1 songs so far").arg(Library.tracks.length)
                                       : qsTr("%1 songs, %2 playlists").arg(Library.tracks.length).arg(Library.playlists.length)
            }
        }

        Heading { text: qsTr("Settings file"); Layout.topMargin: 16 }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            TextEdit {
                Layout.fillWidth: true
                text: Settings.configPath
                readOnly: true
                selectByMouse: true
                color: Theme.text
                font.family: Qt.platform.os === "osx" ? "Menlo" : Qt.platform.os === "windows" ? "Consolas" : "monospace"
                font.pixelSize: 12
                wrapMode: TextEdit.WrapAnywhere
            }
            Button { text: qsTr("Open in Editor"); onClicked: Settings.openConfigFile() }
        }
        Note { text: qsTr("You can edit it by hand: Legato picks up the changes when it is saved.") }

        Label {
            id: error
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: "#d9534f"
            visible: text !== ""
        }
    }

    Connections {
        target: Settings
        function onFailed(message) { error.text = message }
        function onMusicDirsChanged() { error.text = "" }
    }

    FolderDialog {
        id: folderDialog
        title: qsTr("Choose a music folder")
        onAccepted: Settings.addMusicDir(selectedFolder)
    }
}
