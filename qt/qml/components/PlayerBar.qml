import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import App

// The now-playing bar under the page: what is playing (cover, title, artist), the controls (shuffle, previous, play/pause, next,
// repeat), where it is in the track, and the volume. It only shows the Player and tells it what was pressed.
Card {
    id: bar

    readonly property var track: Player.current
    readonly property bool loaded: track.path !== undefined || track.url !== undefined
    readonly property bool compact: width < 640       // narrow: just the controls and the seek bar

    implicitHeight: 72
    radius: Theme.cardRadius

    function formatTime(seconds) {
        seconds = Math.max(0, Math.floor(seconds))
        const s = seconds % 60
        return Math.floor(seconds / 60) + ":" + (s < 10 ? "0" : "") + s
    }

    component TransportButton: Rectangle {
        id: button
        required property string glyph
        required property string label
        property bool on: false          // shuffle or repeat is on
        property int glyphSize: 18
        signal clicked()

        implicitWidth: glyphSize + 16
        implicitHeight: glyphSize + 16
        radius: width / 2
        opacity: enabled ? 1 : 0.35
        color: tap.pressed ? Theme.tint(Theme.text, Theme.selected) : hover.hovered && enabled ? Theme.tint(Theme.text, Theme.hover) : "transparent"
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: button.clicked()

        Icon { anchors.centerIn: parent; name: button.glyph; size: button.glyphSize; color: button.on ? Theme.accent : Theme.text }
        // a dot under shuffle and repeat when they are on, as Apple Music has
        Rectangle {
            visible: button.on
            width: 4; height: 4; radius: 2
            color: Theme.accent
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 1 }
        }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tap; onTapped: button.clicked() }
        ToolTip.visible: hover.hovered
        ToolTip.delay: 500
        ToolTip.text: label
    }

    // a thin bar that thickens under the pointer; the filled part in the accent colour
    component BarSlider: Slider {
        id: slider
        padding: 0
        implicitHeight: 16
        background: Rectangle {
            x: slider.leftPadding
            y: (slider.height - height) / 2
            width: slider.availableWidth
            height: slider.hovered || slider.pressed ? 5 : 3
            radius: height / 2
            color: Theme.tint(Theme.text, 0.15)
            Rectangle {
                width: slider.visualPosition * parent.width
                height: parent.height
                radius: parent.radius
                color: slider.enabled ? Theme.accent : Theme.tint(Theme.text, 0.3)
            }
        }
        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: (slider.height - height) / 2
            width: 12; height: 12; radius: 6
            color: "white"
            border.width: 1
            border.color: Theme.tint("black", 0.2)
            visible: slider.enabled && (slider.hovered || slider.pressed)
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 16
        spacing: 16

        // what is playing
        RowLayout {
            visible: !bar.compact
            Layout.preferredWidth: 250
            Layout.maximumWidth: 250
            spacing: 10

            Rectangle {
                implicitWidth: 48; implicitHeight: 48
                radius: Theme.radius
                color: Theme.tint(Theme.text, 0.08)
                clip: true
                Icon { anchors.centerIn: parent; name: "music"; size: 20; opacity: 0.4; visible: cover.status !== Image.Ready || cover.implicitWidth <= 1 }
                Image {
                    id: cover
                    anchors.fill: parent
                    source: bar.track.path ? "image://cover/" + encodeURIComponent(bar.track.path) : ""
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Label {
                    Layout.fillWidth: true
                    text: bar.loaded ? bar.track.title : qsTr("Not playing")
                    font.bold: bar.loaded
                    elide: Text.ElideRight
                    opacity: bar.loaded ? 1 : 0.55
                }
                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: Player.error !== "" ? Player.error
                        : bar.loaded ? [bar.track.artist, bar.track.album].filter(s => s).join(" — ") : ""
                    color: Player.error !== "" ? "#d9534f" : Theme.text
                    opacity: Player.error !== "" ? 1 : 0.6
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
        }

        // the controls, and where it is in the track
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                TransportButton {
                    glyph: "arrows-shuffle"
                    label: Player.shuffle ? qsTr("Shuffle is on") : qsTr("Shuffle")
                    on: Player.shuffle
                    glyphSize: 16
                    onClicked: Player.shuffle = !Player.shuffle
                }
                TransportButton {
                    glyph: "player-track-prev"; label: qsTr("Previous"); enabled: bar.loaded
                    onClicked: Player.previous()
                }
                TransportButton {
                    glyph: Player.playing ? "player-pause" : "player-play"
                    label: Player.playing ? qsTr("Pause") : qsTr("Play")
                    glyphSize: 24
                    enabled: bar.loaded
                    onClicked: Player.toggle()
                }
                TransportButton {
                    glyph: "player-track-next"; label: qsTr("Next"); enabled: bar.loaded
                    onClicked: Player.next()
                }
                TransportButton {
                    glyph: Player.repeat === Player.RepeatOne ? "repeat-once" : "repeat"
                    label: Player.repeat === Player.RepeatOne ? qsTr("Repeating this song")
                         : Player.repeat === Player.RepeatAll ? qsTr("Repeating the list") : qsTr("Repeat")
                    on: Player.repeat !== Player.RepeatOff
                    glyphSize: 16
                    onClicked: Player.cycleRepeat()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Label {
                    text: bar.loaded ? bar.formatTime(seek.pressed ? seek.value : Player.position) : ""
                    font.pixelSize: 11
                    font.features: { "tnum": 1 }
                    opacity: 0.6
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: 38
                }
                BarSlider {
                    id: seek
                    Layout.fillWidth: true
                    enabled: bar.loaded
                    from: 0
                    to: Math.max(1, Player.duration)
                    // follows the track, except while it is being dragged; the jump happens on letting go
                    Binding on value { value: Player.position; when: !seek.pressed; restoreMode: Binding.RestoreNone }
                    onPressedChanged: if (!pressed) Player.seek(value)
                    Accessible.name: qsTr("Position")
                }
                Label {
                    text: bar.loaded ? "-" + bar.formatTime(Player.duration - (seek.pressed ? seek.value : Player.position)) : ""
                    font.pixelSize: 11
                    font.features: { "tnum": 1 }
                    opacity: 0.6
                    Layout.preferredWidth: 38
                }
            }
        }

        // the volume (kept in legato.yaml)
        RowLayout {
            visible: !bar.compact
            Layout.preferredWidth: 140
            spacing: 6
            Icon {
                name: Settings.volume === 0 ? "volume-3" : Settings.volume < 50 ? "volume-2" : "volume"
                size: 16
                opacity: 0.7
            }
            BarSlider {
                id: volume
                Layout.fillWidth: true
                from: 0
                to: 100
                stepSize: 1
                Binding on value { value: Settings.volume; when: !volume.pressed; restoreMode: Binding.RestoreNone }
                onMoved: Settings.volume = Math.round(value)
                Accessible.name: qsTr("Volume")
            }
        }
    }
}
