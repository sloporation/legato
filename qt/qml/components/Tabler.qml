pragma Singleton
import QtQuick

// Loads the Tabler icon font once and maps icon names to codepoints.
// To add an icon, find its name on tabler.io/icons and its codepoint with:
//   grep -A1 '^\.ti-NAME:before' tabler-icons.css
QtObject {
    readonly property FontLoader loader: FontLoader {
        source: "../../fonts/tabler-icons.ttf"
    }
    readonly property string family: loader.name

    readonly property var glyphs: ({
        "alert-circle":      "",
        "arrows-shuffle":    "",
        "chevron-down":      "",
        "chevron-left":      "",
        "chevron-up":        "",
        "circle-check":      "",
        "device-mobile":     "",
        "disc":              "",
        "file-text":         "",
        "folder":            "",
        "layout-sidebar":    "",
        "lock":              "",
        "microphone-2":      "",
        "minus":             "",
        "music":             "",
        "player-pause":      "",
        "player-play":       "",
        "player-stop":       "",
        "player-track-next": "",
        "player-track-prev": "",
        "playlist":          "",
        "plus":              "",
        "refresh":           "",
        "repeat":            "",
        "repeat-once":       "",
        "search":            "",
        "settings":          "",
        "usb":               "",
        "vinyl":             "",
        "volume":            "",
        "volume-2":          "",
        "volume-3":          "",
        "x":                 ""
    })
}
