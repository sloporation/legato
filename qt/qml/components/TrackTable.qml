import QtQuick
import QtQuick.Controls
import App

// A table of tracks, the way Apple Music shows them: a header to sort by (click again to reverse) and to resize the columns by their
// right edge, striped rows that carry on past the last track, and a row picked by click or the arrow keys. The play button at the left of
// a row, a double-click or Return plays from that track on: the Player gets the rows in the order they are shown. Right-click (or Cmd+I
// for the selected one) to edit a track's tags.
// When the columns are wider than the view, it scrolls sideways (trackpad, Shift+wheel, or the scroll bar), header and rows together.
// TrackTable { tracks: Library.tracks }
FocusScope {
    id: table

    required property var tracks

    function playFrom(index) { Player.playList(rows, index) }
    // the play button: the track playing pauses and goes on, any other starts there
    function playOrPause(index) {
        if (Player.current.path !== undefined && Player.current.path === rows[index]?.path)
            Player.toggle()
        else
            playFrom(index)
    }

    // Title (width 0) takes whatever room the others leave, until a column is resized: then every column keeps its width, and what is
    // left over at the right stays empty, as in Apple Music. A column with `onlyWhen` shows only while the table is sorted by that key
    // (the track number, beside the album when sorted by album); one with `sortable: false` does nothing when its heading is clicked.
    property var columns: [
        { key: "title",  title: qsTr("Title"),  width: 0,   align: Text.AlignLeft },
        { key: "duration", title: qsTr("Time"), width: 60,  align: Text.AlignRight },
        { key: "artist", title: qsTr("Artist"), width: 170, align: Text.AlignLeft },
        { key: "album",  title: qsTr("Album"),  width: 190, align: Text.AlignLeft },
        { key: "trackNumber", title: "#",       width: 36,  align: Text.AlignRight, onlyWhen: "album", sortable: false },
        { key: "genre",  title: qsTr("Genre"),  width: 100, align: Text.AlignLeft },
        { key: "year",   title: qsTr("Year"),   width: 60,  align: Text.AlignRight }
    ]
    readonly property int minColumn: 40
    readonly property int minTitle: 140
    function shown(i) { return columns[i].onlyWhen === undefined || columns[i].onlyWhen === sortKey }
    readonly property real fixedWidth: columns.reduce((sum, c, i) => sum + (shown(i) ? c.width : 0), 0)
    readonly property int leadWidth: 30      // the play button, before the first column
    function columnWidth(i) {
        if (!shown(i)) return 0
        return i === 0 && columns[0].width === 0 ? Math.max(minTitle, list.width - leadWidth - fixedWidth) : columns[i].width
    }
    function columnX(i) { let x = leadWidth; for (let k = 0; k < i; k++) x += columnWidth(k); return x }
    readonly property real columnsWidth: columnX(columns.length)
    readonly property real tableWidth: Math.max(list.width, columnsWidth)     // the rows' width: at least the view's
    function setWidth(i, w) {
        const c = columns.slice()
        c[i] = Object.assign({}, c[i], { width: Math.max(minColumn, w) })
        columns = c
    }

    // sorted by a column; a tie keeps album order (album, its artist, disc, then track number), as Apple Music does, and then the title
    // (for files with no track numbers). "" keeps the order given (a playlist's).
    property string sortKey: "artist"
    property bool ascending: true
    function sortBy(key) {
        if (sortKey === key) ascending = !ascending
        else { sortKey = key; ascending = true }
    }
    property string selectedPath: ""     // the selected track, by file, so it stays selected when the rows change
    readonly property var rows: {
        if (sortKey === "")
            return tracks
        const key = sortKey, dir = ascending ? 1 : -1
        // blanks (no artist, no year) go last either way, as in Apple Music
        const blank = v => v === "" || v === 0
        const cmp = (a, b) => typeof a === "string" ? a.localeCompare(b, undefined, { sensitivity: "base", numeric: true }) : a - b
        const byKey = (a, b) => blank(a) !== blank(b) ? (blank(a) ? 1 : -1) : dir * cmp(a, b)
        const albumArtist = t => t.albumArtist || t.artist
        // (numbered tracks before unnumbered ones, as blanks go last)
        const number = t => t.trackNumber > 0 ? t.trackNumber : Number.MAX_SAFE_INTEGER
        return tracks.slice().sort((a, b) => byKey(a[key], b[key]) || cmp(a.album, b.album) || cmp(albumArtist(a), albumArtist(b))
                                             || (a.discNumber || 1) - (b.discNumber || 1) || number(a) - number(b) || cmp(a.title, b.title))
    }
    function formatTime(seconds) {
        const s = Math.floor(seconds % 60)
        return Math.floor(seconds / 60) + ":" + (s < 10 ? "0" : "") + s
    }
    function cell(track, key) {
        if (!track)      // a row on its way out while the rows are swapped
            return ""
        if (key === "duration") return track.duration > 0 ? formatTime(track.duration) : ""    // 0: the file doesn't say (damaged, or written to a pipe)
        if (key === "year") return track.year > 0 ? track.year : ""
        if (key === "trackNumber") return track.trackNumber > 0 ? track.trackNumber : ""
        return track[key]
    }

    // ---- header
    Item {
        id: header
        width: parent.width
        height: Theme.tableHeaderHeight
        clip: true

        Item {
            id: headings
            x: -(list.contentX - list.originX)      // moves with the rows when they scroll sideways
            width: table.tableWidth
            height: parent.height

        Repeater {
            model: table.columns.length
            delegate: Item {
                id: head
                required property int index
                readonly property var column: table.columns[index]
                readonly property bool sorted: table.sortKey === column.key
                x: table.columnX(index)
                width: table.columnWidth(index)
                height: header.height
                visible: width > 0

                Rectangle {
                    anchors.fill: parent
                    color: headTap.pressed ? Theme.tint(Theme.text, Theme.selected) : headHover.hovered && head.column.sortable !== false ? Theme.tint(Theme.text, Theme.hover) : "transparent"
                }
                Row {
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8 }
                    layoutDirection: head.column.align === Text.AlignRight ? Qt.RightToLeft : Qt.LeftToRight
                    spacing: 4
                    Label {
                        text: head.column.title
                        font.pixelSize: 12
                        font.bold: head.sorted
                        opacity: head.sorted ? 1 : 0.65
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, head.width - 16 - (head.sorted ? 16 : 0))
                    }
                    Icon {
                        visible: head.sorted
                        name: table.ascending ? "chevron-up" : "chevron-down"
                        size: 12
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: 0.8
                    }
                }
                // the line after each heading
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height - 10; anchors.verticalCenter: parent.verticalCenter; color: Theme.hairline }

                HoverHandler { id: headHover }
                TapHandler { id: headTap; enabled: head.column.sortable !== false; onTapped: table.sortBy(head.column.key) }

                // drag the right edge to resize this column
                MouseArea {
                    x: parent.width - 4; width: 8; height: parent.height
                    z: 1
                    cursorShape: Qt.SplitHCursor
                    property real startX: 0
                    property real startWidth: 0
                    onPressed: mouse => {
                        // from now on Title keeps its width too, so the edge stays under the pointer
                        if (table.columns[0].width === 0)
                            table.setWidth(0, table.columnWidth(0))
                        startX = mapToItem(header, mouse.x, 0).x
                        startWidth = table.columnWidth(head.index)
                    }
                    onPositionChanged: mouse => {
                        if (!pressed) return
                        const dx = mapToItem(header, mouse.x, 0).x - startX
                        table.setWidth(head.index, Math.max(head.index === 0 ? table.minTitle : table.minColumn, startWidth + dx))
                    }
                }
            }
        }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.hairline }
    }

    // ---- rows
    Item {
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true

        // stripes behind the rows, which carry on below the last one
        Repeater {
            model: Math.ceil(parent.height / Theme.tableRowHeight) + 2
            delegate: Rectangle {
                required property int index
                width: parent.width
                height: Theme.tableRowHeight
                y: index * height - (list.contentY - list.originY) % (2 * height)
                color: index % 2 === 1 ? Theme.tint(Theme.text, Theme.stripe) : "transparent"
            }
        }

        ListView {
            id: list
            objectName: "trackList"
            anchors.fill: parent
            focus: true
            interactive: false
            keyNavigationEnabled: true
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: -1
            highlightMoveDuration: 0
            contentWidth: table.tableWidth
            flickableDirection: Flickable.HorizontalAndVerticalFlick
            // set by hand, not bound, so the scroll position and the selected track can be carried over when the rows change
            // (a rescan that found a new file, or a click on a heading): a new array would otherwise send the list back to the top
            property bool swapping: false
            Component.onCompleted: { swapping = true; model = table.rows; currentIndex = -1; swapping = false }    // (nothing selected to start with)
            Connections {
                target: table
                function onRowsChanged() {
                    const y = list.contentY
                    list.swapping = true
                    list.model = table.rows
                    list.currentIndex = table.selectedPath === "" ? -1 : table.rows.findIndex(t => t.path === table.selectedPath)
                    list.swapping = false
                    list.contentY = Math.max(list.originY, Math.min(y, list.originY + list.contentHeight - list.height))
                    if (list.currentIndex >= 0)
                        list.positionViewAtIndex(list.currentIndex, ListView.Contain)
                }
            }
            onCurrentIndexChanged: if (!swapping) table.selectedPath = table.rows[currentIndex]?.path ?? ""
            ScrollBar.vertical: ScrollBar {}
            ScrollBar.horizontal: ScrollBar {}
            WheelScroll { view: list }
            Keys.onReturnPressed: if (currentIndex >= 0) table.playFrom(currentIndex)

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool selected: ListView.isCurrentItem
                readonly property bool isPlaying: modelData !== undefined && Player.current.path === modelData.path
                readonly property color ink: selected && list.activeFocus ? Theme.accentText : Theme.text
                width: table.tableWidth
                height: Theme.tableRowHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 2
                    anchors.rightMargin: 2
                    radius: 4
                    color: row.selected ? (list.activeFocus ? Theme.accent : Theme.tint(Theme.text, Theme.selected))
                         : rowHover.hovered ? Theme.tint(Theme.text, Theme.hover) : "transparent"
                }
                Repeater {
                    model: table.columns.length
                    delegate: Label {
                        required property int index
                        readonly property var column: table.columns[index]
                        x: table.columnX(index) + 8
                        width: table.columnWidth(index) - 16
                        visible: width > 0
                        height: row.height
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: column.align
                        text: table.cell(row.modelData, column.key)
                        elide: Text.ElideRight
                        font.pixelSize: 13
                        font.features: column.align === Text.AlignRight ? { "tnum": 1 } : {}
                        color: row.ink
                        opacity: index === 0 || row.selected ? 1 : 0.8
                    }
                }

                // the play button: on hover, and (as a speaker) on the track that is playing
                Icon {
                    x: (table.leadWidth - width) / 2 + 2
                    anchors.verticalCenter: parent.verticalCenter
                    size: 15
                    visible: rowHover.hovered || row.isPlaying
                    name: !rowHover.hovered ? "volume" : row.isPlaying && Player.playing ? "player-pause" : "player-play"
                    color: row.isPlaying && !(row.selected && list.activeFocus) ? Theme.accent : row.ink
                    opacity: row.isPlaying && !Player.playing && !rowHover.hovered ? 0.5 : 1
                }
                MouseArea {
                    width: table.leadWidth
                    height: parent.height
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { list.currentIndex = row.index; table.playOrPause(row.index) }
                    Accessible.role: Accessible.Button
                    Accessible.name: row.isPlaying && Player.playing ? qsTr("Pause") : qsTr("Play")
                }

                HoverHandler { id: rowHover }
                TapHandler {
                    onTapped: { list.currentIndex = row.index; list.forceActiveFocus() }
                    onDoubleTapped: table.playFrom(row.index)
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: { list.currentIndex = row.index; list.forceActiveFocus(); rowMenu.popup() }
                }
                // (macOS: a Control-click is a right-click)
                TapHandler {
                    acceptedModifiers: Qt.ControlModifier
                    enabled: Qt.platform.os === "osx"
                    onTapped: { list.currentIndex = row.index; list.forceActiveFocus(); rowMenu.popup() }
                }
            }
        }

        Menu {
            id: rowMenu
            readonly property var track: table.rows[list.currentIndex]
            MenuItem {
                text: rowMenu.track && Player.current.path === rowMenu.track.path && Player.playing ? qsTr("Pause") : qsTr("Play")
                onTriggered: table.playOrPause(list.currentIndex)
            }
            MenuSeparator {}
            MenuItem { text: qsTr("Edit Info…"); onTriggered: info.edit(rowMenu.track.path) }
            MenuItem {
                text: Qt.platform.os === "osx" ? qsTr("Show in Finder") : qsTr("Show in Folder")
                onTriggered: Library.reveal(rowMenu.track.path)
            }
        }
        TrackInfoDialog { id: info; objectName: "trackInfo" }
        // Cmd+I (Ctrl+I elsewhere), as Get Info in Apple Music and Finder
        Shortcut {
            sequences: ["Ctrl+I"]
            enabled: list.currentIndex >= 0 && !info.visible
            onActivated: info.edit(table.rows[list.currentIndex].path)
        }

        Label {
            anchors.centerIn: parent
            visible: table.tracks.length === 0
            text: qsTr("No songs here yet")
            opacity: 0.55
        }
    }
}
