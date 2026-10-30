import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import App

// Edit a track's tags (right-click › Edit Info…, or Cmd+I). Saving writes them into the file itself; the library shows the change at
// once. Only the fields that were changed are written, so nothing else in the file is touched.
// TrackInfoDialog { id: info }  …  info.edit(track.path)
Dialog {
    id: dialog

    property string path: ""
    property var original: ({})       // the tags as they were opened (Library.tagsForEditing)
    property string error: ""

    function edit(path) {
        dialog.path = path
        original = Library.tagsForEditing(path)
        for (const f of fields)
            f.text = original[f.key] ?? ""
        error = ""
        open()
        titleField.forceActiveFocus()
        titleField.selectAll()
    }
    readonly property var fields: [titleField, artistField, albumField, albumArtistField, genreField, dateField,
                                   trackField, trackTotalField, discField, discTotalField]
    readonly property bool changed: fields.some(f => f.text !== (original[f.key] ?? ""))
    function save() {
        if (!changed) { close(); return }
        const tags = {}
        for (const f of fields)
            if (f.text !== (original[f.key] ?? "")) tags[f.key] = f.text
        // a number and its total are written together
        if ("trackTotal" in tags) tags.trackNumber = trackField.text
        if ("discTotal" in tags) tags.discNumber = discField.text
        if ("trackNumber" in tags) tags.trackTotal = trackTotalField.text
        if ("discNumber" in tags) tags.discTotal = discTotalField.text
        error = Library.writeTags(path, tags)
        if (error === "") close()
    }

    function formatTime(seconds) {
        const s = Math.floor(seconds % 60)
        return Math.floor(seconds / 60) + ":" + (s < 10 ? "0" : "") + s
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(520, parent.width - 40)
    modal: true
    padding: 20
    topPadding: 20
    closePolicy: Popup.CloseOnEscape
    palette.windowText: Theme.text
    palette.text: Theme.text
    palette.buttonText: Theme.text

    background: Card { radius: Theme.cardRadius }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.45) }

    component FieldLabel: Label {
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        opacity: 0.6
        font.pixelSize: 12
    }
    component Field: TextField {
        required property string key
        Layout.fillWidth: true
        selectByMouse: true
        color: Theme.text
        placeholderTextColor: Theme.tint(Theme.text, 0.35)
        leftPadding: 8
        rightPadding: 8
        background: Rectangle {
            implicitHeight: 28
            radius: Theme.radius
            color: Theme.tint(Theme.text, 0.05)
            border.width: parent.activeFocus ? 2 : 1
            border.color: parent.activeFocus ? Theme.accent : Theme.hairline
        }
        onAccepted: dialog.save()
    }
    component NumberField: Field {
        Layout.fillWidth: false
        Layout.preferredWidth: 52
        horizontalAlignment: Text.AlignRight
        validator: RegularExpressionValidator { regularExpression: /\d{0,4}/ }
    }

    contentItem: ColumnLayout {
        spacing: 14

        // the cover and what it is, as Apple Music's Get Info has
        RowLayout {
            spacing: 14
            Rectangle {
                implicitWidth: 64; implicitHeight: 64
                radius: Theme.radius
                color: Theme.tint(Theme.text, 0.08)
                clip: true
                Icon { anchors.centerIn: parent; name: "music"; size: 24; opacity: 0.4; visible: cover.status !== Image.Ready || cover.implicitWidth <= 1 }
                Image {
                    id: cover
                    anchors.fill: parent
                    source: dialog.path ? "image://cover/" + encodeURIComponent(dialog.path) : ""
                    sourceSize: Qt.size(128, 128)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label { Layout.fillWidth: true; text: titleField.text || qsTr("Untitled"); font.bold: true; font.pixelSize: 15; elide: Text.ElideRight }
                Label { Layout.fillWidth: true; text: [artistField.text, albumField.text].filter(s => s).join(" — "); opacity: 0.6; elide: Text.ElideRight; visible: text !== "" }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 8

            FieldLabel { text: qsTr("Title") }
            Field { id: titleField; key: "title" }
            FieldLabel { text: qsTr("Artist") }
            Field { id: artistField; key: "artist" }
            FieldLabel { text: qsTr("Album") }
            Field { id: albumField; key: "album" }
            FieldLabel { text: qsTr("Album Artist") }
            Field { id: albumArtistField; key: "albumArtist"; placeholderText: artistField.text }
            FieldLabel { text: qsTr("Genre") }
            Field { id: genreField; key: "genre" }
            FieldLabel { text: qsTr("Year") }
            Field {
                id: dateField; key: "date"
                Layout.fillWidth: false
                Layout.preferredWidth: 110
                ToolTip.visible: activeFocus && text.length > 4
                ToolTip.text: qsTr("A year, or a full date (2017-10-30)")
            }
            FieldLabel { text: qsTr("Track") }
            RowLayout {
                spacing: 6
                NumberField { id: trackField; key: "trackNumber" }
                Label { text: qsTr("of"); opacity: 0.6 }
                NumberField { id: trackTotalField; key: "trackTotal" }
                Item { Layout.preferredWidth: 18 }
                FieldLabel { text: qsTr("Disc") }
                NumberField { id: discField; key: "discNumber" }
                Label { text: qsTr("of"); opacity: 0.6 }
                NumberField { id: discTotalField; key: "discTotal" }
            }
        }

        // the file itself
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.hairline }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Label {
                Layout.fillWidth: true
                font.pixelSize: 12
                opacity: 0.6
                text: [dialog.original.format,
                       dialog.original.duration > 0 ? dialog.formatTime(dialog.original.duration) : "",
                       dialog.original.bitrate > 0 ? qsTr("%1 kbps").arg(dialog.original.bitrate) : "",
                       dialog.original.sampleRate > 0 ? qsTr("%1 kHz").arg(dialog.original.sampleRate / 1000) : "",
                       dialog.original.channels === 1 ? qsTr("mono") : dialog.original.channels === 2 ? qsTr("stereo")
                           : dialog.original.channels > 2 ? qsTr("%1 channels").arg(dialog.original.channels) : ""].filter(s => s).join(" · ")
            }
            RowLayout {
                Layout.fillWidth: true
                Label { Layout.fillWidth: true; text: dialog.path; elide: Text.ElideMiddle; font.pixelSize: 12; opacity: 0.6 }
                Label {
                    text: Qt.platform.os === "osx" ? qsTr("Show in Finder") : qsTr("Show in Folder")
                    font.pixelSize: 12
                    color: Theme.accent
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Library.reveal(dialog.path) }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: dialog.error !== ""
            text: dialog.error
            color: "#d9534f"
            wrapMode: Text.Wrap
        }
    }

    // (plain buttons, not a DialogButtonBox, which would close the dialog before the file is written: a failure stays open and says why)
    footer: Item {
        implicitHeight: buttons.implicitHeight + 20
        RowLayout {
            id: buttons
            anchors { right: parent.right; rightMargin: 20; top: parent.top }
            spacing: 8
            Button { text: qsTr("Cancel"); onClicked: dialog.close() }
            Button { text: qsTr("Save"); highlighted: true; enabled: dialog.changed; onClicked: dialog.save() }
        }
    }
}
