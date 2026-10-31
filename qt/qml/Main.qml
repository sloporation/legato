import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt.labs.platform as Platform
import App
import "components"
import "views"

// The window: a canvas with the page straight on it, and the sidebar floating at the left as a card. The circle at the top of the page
// folds the sidebar away (Ctrl/Cmd+B). When the window is narrow the page has it all, and the sidebar slides in over it as a drawer.
ApplicationWindow {
    id: root
    width: 1100
    height: 700
    minimumWidth: 420
    minimumHeight: 320
    visible: true
    title: "Legato"
    color: Theme.canvas
    palette.windowText: Theme.text
    palette.text: Theme.text
    palette.buttonText: Theme.text
    palette.highlight: Theme.accent

    // "artists" (showing artistName), "albums", "songs", "album" (the one at albumKey, opened from albumFrom), "playlist" (the .m3u at
    // playlistPath) or "device" (the phone deviceId)
    property string page: "songs"
    property string playlistPath: ""
    property string albumKey: ""
    property string albumFrom: "albums"
    property string artistName: ""
    property string deviceId: ""
    // what the find field in the header holds, on the pages of tracks (songs, a playlist); a new page starts without it
    property string filter: ""
    readonly property bool canFilter: !noFolders && (page === "songs" || page === "playlist" || page === "device")
    function openPage(name) { drawer.close(); filter = ""; page = name }
    function openAlbum(key, from) { albumKey = key; albumFrom = from; page = "album" }
    function back() { if (page === "album") page = albumFrom }
    function openPlaylist(path) { drawer.close(); filter = ""; playlistPath = path; page = "playlist" }
    function openDevice(id) { drawer.close(); filter = ""; deviceId = id; page = "device" }
    function newPlaylist() {
        const index = Library.createPlaylist(qsTr("New Playlist"))
        if (index >= 0) openPlaylist(Library.playlists[index].path)
    }

    function openSettings() { drawer.close(); settingsWindow.show(); settingsWindow.raise(); settingsWindow.requestActivate() }
    SettingsWindow { id: settingsWindow }
    // Cmd+, on macOS (also in the app menu, below); Ctrl+, on Linux and Windows, as VS Code, GNOME apps and Windows Terminal have it
    Shortcut { sequences: [Qt.platform.os === "osx" ? StandardKey.Preferences : "Ctrl+,"]; onActivated: root.openSettings() }
    Shortcut { sequences: [StandardKey.New]; onActivated: root.newPlaylist() }
    // playing: Space, and Cmd+→ / Cmd+← (Ctrl elsewhere) as in Apple Music
    Shortcut { sequences: ["Space"]; enabled: Player.queue.length > 0; onActivated: Player.toggle() }
    Shortcut { sequences: ["Ctrl+Right"]; enabled: Player.queue.length > 0; onActivated: Player.next() }
    Shortcut { sequences: ["Ctrl+Left"]; enabled: Player.queue.length > 0; onActivated: Player.previous() }

    // macOS: the menu bar, where Settings… goes in the app menu
    Instantiator {
        active: Qt.platform.os === "osx"
        delegate: Platform.MenuBar {
            window: root
            Platform.Menu {
                title: qsTr("File")
                Platform.MenuItem { text: qsTr("New Playlist"); shortcut: StandardKey.New; onTriggered: root.newPlaylist() }
                Platform.MenuItem { text: qsTr("Settings…"); role: Platform.MenuItem.PreferencesRole; onTriggered: root.openSettings() }
            }
            Platform.Menu {
                title: qsTr("Library")
                Platform.MenuItem { text: qsTr("Rescan Music Folders"); enabled: !Library.scanning; onTriggered: Library.rescan() }
            }
        }
    }

    readonly property bool wide: width >= Theme.wideBreakpoint
    property bool showSidebar: true
    readonly property bool sidebarOpen: wide ? showSidebar : drawer.opened
    function toggleSidebar() {
        if (wide) showSidebar = !showSidebar
        else if (drawer.opened) drawer.close()
        else drawer.open()
    }
    Shortcut { sequences: ["Ctrl+B"]; onActivated: root.toggleSidebar() }
    // back from an album to the page it was opened from, as Cmd+[ in Apple Music and Finder
    Shortcut { sequences: ["Ctrl+["]; enabled: root.page === "album"; onActivated: root.back() }

    readonly property var playlist: page === "playlist" ? Library.playlists.find(p => p.path === playlistPath) ?? null : null
    readonly property var album: page === "album" ? Library.albums.find(a => a.key === albumKey) ?? null : null
    readonly property var device: page === "device" ? Devices.devices.find(d => d.id === deviceId) ?? null : null
    // unplugged while its page was showing
    onDeviceChanged: if (page === "device" && !device) openPage("songs")
    readonly property string pageTitle: ({ artists: qsTr("Artists"), albums: qsTr("Albums"), songs: qsTr("Songs") })[page] ?? playlist?.name ?? album?.title ?? device?.name ?? ""
    function count(n, one, many) { return n + " " + (n === 1 ? one : many) }
    // (filtered: how many of them are showing)
    readonly property string shownOf: canFilter && filter.trim() !== "" && pageLoader.item?.matching ? pageLoader.item.matching.length + " " + qsTr("of") + " " : ""
    readonly property string pageDetail: noFolders ? "" : shownOf + (page === "songs" ? count(Library.tracks.length, qsTr("song"), qsTr("songs"))
                                        : page === "albums" ? count(Library.albums.length, qsTr("album"), qsTr("albums"))
                                        : page === "artists" ? count(Library.artists.length, qsTr("artist"), qsTr("artists"))
                                        : playlist ? count(playlist.tracks.length, qsTr("song"), qsTr("songs"))
                                        : album ? album.artist
                                        : device ? (device.kind === "iphone" ? qsTr("iPhone") : qsTr("Android")) : "")
                                       + (Library.scanning ? " · " + qsTr("scanning…") : "")
    readonly property bool noFolders: Settings.musicDirs.length === 0

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.gap
        spacing: 0

        // the sidebar, when the window is wide enough to have it beside the page
        Item {
            // (an invisible item gets no width from the layout, so it is shown while it opens)
            visible: root.wide && (root.showSidebar || slideWidth > 0)
            clip: true
            // the width is animated here, not on the layout's attached property
            property real slideWidth: root.wide && root.showSidebar ? Theme.sidebarWidth + Theme.gap : 0
            Behavior on slideWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Layout.fillHeight: true
            Layout.preferredWidth: slideWidth
            Loader {
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                width: Theme.sidebarWidth
                active: root.wide
                sourceComponent: sidebar
            }
        }

        // the page, straight on the canvas
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Item {
                Layout.fillWidth: true
                implicitHeight: Theme.headerHeight
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 12
                    PanelToggle {
                        glyph: "layout-sidebar"
                        label: qsTr("Library")
                        active: root.sidebarOpen
                        onClicked: root.toggleSidebar()
                    }
                    PanelToggle {
                        visible: root.page === "album"
                        glyph: "chevron-left"
                        label: root.albumFrom === "artists" ? qsTr("Back to Artists") : qsTr("Back to Albums")
                        active: true
                        onClicked: root.back()
                    }
                    Label { text: root.pageTitle; font.bold: true; font.pixelSize: 15; elide: Text.ElideRight }
                    Label { text: root.pageDetail; opacity: 0.55; Layout.fillWidth: true; elide: Text.ElideRight }
                    FindField {
                        id: findField
                        visible: root.canFilter
                        Layout.preferredWidth: Math.min(240, root.width * 0.3)
                        placeholderText: root.page === "playlist" ? qsTr("Find in Playlist") : root.page === "device" ? qsTr("Find") : qsTr("Find in Songs")
                        text: root.filter
                        onTextEdited: root.filter = text
                    }
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.hairline }
            }

            Loader {
                id: pageLoader
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: root.noFolders ? noFoldersPage
                               : ({ artists: artistsPage, albums: albumsPage, songs: songsPage, album: albumPage, playlist: playlistPage,
                                    device: devicePage })[root.page]
            }

            PlayerBar {
                Layout.fillWidth: true
                Layout.topMargin: Theme.gap
            }
        }
    }

    Component {
        id: artistsPage
        ArtistsView {
            artistName: root.artistName
            onSelected: name => root.artistName = name
            onActivated: album => root.openAlbum(album.key, "artists")
        }
    }
    Component { id: albumsPage; AlbumsView { onActivated: album => root.openAlbum(album.key, "albums") } }
    Component { id: albumPage; AlbumView { albumKey: root.albumKey } }
    Component { id: songsPage; SongsView { filter: root.filter; onFilterRequested: f => root.filter = f } }
    Component { id: devicePage; DeviceView { device: root.device; filter: root.filter } }
    Component { id: playlistPage; PlaylistView { playlistPath: root.playlistPath; filter: root.filter; onFilterRequested: f => root.filter = f } }
    // Cmd+F (Ctrl+F) to find, as everywhere
    Shortcut { sequences: [StandardKey.Find]; enabled: root.canFilter; onActivated: { findField.forceActiveFocus(); findField.selectAll() } }

    // first run: nothing to show until Legato is given a folder to look after
    Component {
        id: noFoldersPage
        Item {
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 380)
                spacing: 10
                Icon { name: "folder"; size: 40; opacity: 0.4; Layout.alignment: Qt.AlignHCenter }
                Label { text: qsTr("Where is your music?"); font.pixelSize: 16; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    opacity: 0.6
                    text: qsTr("Choose the folders Legato looks after. It finds the music in them and keeps its tags up to date.")
                }
                Button { text: qsTr("Choose Folder…"); Layout.alignment: Qt.AlignHCenter; onClicked: folderDialog.open() }
            }
        }
    }
    FolderDialog {
        id: folderDialog
        title: qsTr("Choose a music folder")
        onAccepted: Settings.addMusicDir(selectedFolder)
    }

    Component {
        id: sidebar
        Sidebar {
            page: root.page === "album" ? root.albumFrom : root.page     // (an album belongs to the page it was opened from)
            playlistPath: root.playlistPath
            deviceId: root.deviceId
            onOpenPage: name => root.openPage(name)
            onOpenPlaylist: path => root.openPlaylist(path)
            onOpenDevice: id => root.openDevice(id)
            onNewPlaylist: root.newPlaylist()
            onOpenSettings: root.openSettings()
        }
    }

    // when the window is narrow: slides in over the page
    Drawer {
        id: drawer
        edge: Qt.LeftEdge
        width: Theme.sidebarWidth + 2 * Theme.gap
        height: root.height
        dragMargin: 0   // opened by its button, not by dragging in from the edge
        modal: true
        padding: 0
        background: null
        Loader {
            anchors.fill: parent
            anchors.margins: Theme.gap
            active: !root.wide
            sourceComponent: sidebar
        }
    }

    // a short message at the bottom, when something could not be done
    Connections { target: Settings; function onFailed(message) { toast.show(message) } }
    Connections { target: Library; function onFailed(message) { toast.show(message) } }
    Connections { target: Devices; function onSynced(name, message) { toast.show(name + ": " + message) } }
    // a track's tags were edited: the player's copy of it (in the now-playing bar) takes the change too
    Connections { target: Library; function onTrackEdited(track) { Player.updateTrack(track) } }
    Rectangle {
        id: toast
        property string message: ""
        function show(text) { message = text; opacity = 1; hideTimer.restart() }
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        width: Math.min(parent.width - 32, toastLabel.implicitWidth + 32)
        height: toastLabel.implicitHeight + 20
        radius: 8
        color: "#323232"
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Label { id: toastLabel; anchors.centerIn: parent; width: parent.width - 32; text: toast.message; color: "white"; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter }
        Timer { id: hideTimer; interval: 4000; onTriggered: toast.opacity = 0 }
    }
}
