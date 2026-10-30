import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import App
import "../components"

// A phone on USB: what goes on it, and Sync. It gets everything, or the playlists, artists and albums ticked here (the find field
// narrows the list). Above, what that comes to and the room on the phone; while it syncs, how far it has got, and Stop.
Item {
    id: view

    required property var device
    property string filter: ""

    readonly property bool ready: device?.status === "ready"
    readonly property var chosen: device?.chosen ?? ({})
    readonly property bool everything: chosen.everything ?? false
    readonly property string kindName: device?.kind === "iphone" ? qsTr("iPhone") : qsTr("phone")

    function size(bytes) {
        return bytes >= 1e9 ? (bytes / 1e9).toFixed(1) + " GB" : Math.round(bytes / 1e6) + " MB"
    }
    function choose(changes) {
        const c = Object.assign({ everything: false, playlists: [], artists: [], albums: [] }, chosen, changes)
        Devices.choose(device.id, c)
    }
    function picked(kind, value) { return (chosen[kind] ?? []).includes(value) }
    function pick(kind, value, on) {
        const list = (chosen[kind] ?? []).filter(v => v !== value)
        if (on) list.push(value)
        choose({ [kind]: list })
    }

    // what the choice comes to, worked out again only when the choice or the library changes (not at every step of a sync)
    readonly property string chosenKey: JSON.stringify(chosen) + "|" + Library.tracks.length
    property var measured: ({ songs: 0, bytes: 0, unplayable: 0 })
    onChosenKeyChanged: if (device) measured = Devices.measure(device.kind, chosen)
    Component.onCompleted: if (device) measured = Devices.measure(device.kind, chosen)

    // something in the way: not trusted, locked, Legato not installed
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 380)
        visible: !view.ready
        spacing: 10
        Icon {
            name: view.device?.status === "locked" ? "lock" : view.device?.status === "error" ? "alert-circle" : "device-mobile"
            size: 40
            opacity: 0.4
            Layout.alignment: Qt.AlignHCenter
        }
        Label {
            text: view.device?.message ?? ""
            font.pixelSize: 16
            font.bold: true
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }
        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            opacity: 0.6
            text: ({
                trust: qsTr("The iPhone asks whether to trust this computer. Once it does, Legato can put music on it."),
                locked: qsTr("Legato can reach the iPhone once it's unlocked."),
                noapp: qsTr("Legato puts the music in Legato for iPhone's own folder. Once it's installed on the iPhone, this page carries on."),
                error: view.device?.kind === "android"
                       ? qsTr("Unlock the phone, and in its USB notification choose “File transfer”.")
                       : ""
            })[view.device?.status] ?? ""
        }
    }

    ColumnLayout {
        anchors.fill: parent
        visible: view.ready
        spacing: 0

        // what it comes to, and Sync
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 20
            Layout.bottomMargin: 12
            spacing: 16
            Icon { name: "device-mobile"; size: 34; color: Theme.accent }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.bold: true
                    font.pixelSize: 14
                    text: view.device?.syncing ? qsTr("Syncing “%1”").arg(view.device.what ?? "")
                        : view.measured.songs === 1 ? qsTr("1 song, %1").arg(view.size(view.measured.bytes))
                        : qsTr("%1 songs, %2").arg(view.measured.songs).arg(view.size(view.measured.bytes))
                }
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    opacity: 0.6
                    text: view.device?.syncing && view.device.total > 0
                          ? qsTr("%1 of %2").arg(view.size(view.device.done)).arg(view.size(view.device.total))
                          : [view.device?.free >= 0 ? qsTr("%1 free on the %2").arg(view.size(view.device.free)).arg(view.kindName) : "",
                             view.measured.unplayable > 0 ? qsTr("%1 more the %2 can't play").arg(view.measured.unplayable).arg(view.kindName) : ""]
                                .filter(s => s !== "").join(" · ")
                }
                ProgressBar {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    visible: view.device?.syncing ?? false
                    from: 0
                    to: Math.max(1, view.device?.total ?? 1)
                    value: view.device?.done ?? 0
                    indeterminate: (view.device?.total ?? 0) === 0
                }
            }
            Button {
                text: view.device?.syncing ? qsTr("Stop") : qsTr("Sync")
                highlighted: !(view.device?.syncing ?? false)
                onClicked: view.device.syncing ? Devices.stopSync() : Devices.sync(view.device.id)
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.bottomMargin: 8
            visible: text !== "" && !(view.device?.syncing ?? false)
            wrapMode: Text.Wrap
            opacity: 0.7
            color: view.device?.result?.ok === false ? "#d9534f" : Theme.text
            text: view.device?.result?.ok === false ? view.device.result.message
                : view.device?.chosenSaved === false ? qsTr("Sync to put this choice on the %1.").arg(view.kindName) : ""
        }

        CheckBox {
            Layout.leftMargin: 14
            text: qsTr("Everything in the library")
            checked: view.everything
            onToggled: view.choose({ everything: checked })
        }
        Rectangle { Layout.fillWidth: true; Layout.topMargin: 6; implicitHeight: 1; color: Theme.hairline }

        // the playlists, artists and albums to tick
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            enabled: !view.everything
            opacity: view.everything ? 0.45 : 1
            ScrollBar.vertical: ScrollBar {}
            WheelScroll { view: list }

            model: {
                const f = view.filter.trim().toLowerCase()
                const has = s => f === "" || (s ?? "").toLowerCase().includes(f)
                const songs = n => n === 1 ? qsTr("1 song") : qsTr("%1 songs").arg(n)
                const out = []
                for (const p of Library.playlists)
                    if (has(p.name)) out.push({ section: qsTr("Playlists"), kind: "playlists", value: p.name, label: p.name, detail: songs(p.tracks.length) })
                for (const a of Library.artists)
                    if (has(a.name)) out.push({ section: qsTr("Artists"), kind: "artists", value: a.name, label: a.name, detail: songs(a.songCount) })
                for (const a of Library.albums)
                    if (has(a.title) || has(a.artist)) out.push({ section: qsTr("Albums"), kind: "albums", value: a.key, label: a.title || qsTr("Unknown Album"), detail: a.artist })
                return out
            }
            section.property: "section"
            section.delegate: Label {
                required property string section
                leftPadding: 20
                topPadding: 14
                bottomPadding: 4
                text: section
                font.pixelSize: 11
                font.bold: true
                font.capitalization: Font.AllUppercase
                opacity: 0.55
            }
            delegate: Rectangle {
                id: row
                required property var modelData
                width: ListView.view.width
                height: 30
                color: hover.hovered ? Theme.tint(Theme.text, Theme.hover) : "transparent"
                readonly property bool on: view.picked(modelData.kind, modelData.value)
                RowLayout {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 20 }
                    spacing: 6
                    CheckBox {
                        checked: row.on
                        onToggled: view.pick(row.modelData.kind, row.modelData.value, checked)
                    }
                    Label { text: row.modelData.label; elide: Text.ElideRight; Layout.fillWidth: true }
                    Label { text: row.modelData.detail ?? ""; opacity: 0.5; elide: Text.ElideRight; Layout.maximumWidth: 260 }
                }
                HoverHandler { id: hover }
                TapHandler { onTapped: view.pick(row.modelData.kind, row.modelData.value, !row.on) }
            }
        }
    }
}
