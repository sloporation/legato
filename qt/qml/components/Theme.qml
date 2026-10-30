pragma Singleton
import QtQuick

// Every colour, size and gap the window is built from, in one place to tweak.
// Colours follow the system's light or dark palette; tint() lays a see-through shade of one over the background (hover, selection, stripes).
QtObject {
    readonly property SystemPalette system: SystemPalette { colorGroup: SystemPalette.Active }
    readonly property bool dark: system.window.hslLightness < 0.5

    // ---- surfaces: the page sits straight on the canvas, the sidebar floats on it as a card
    readonly property color canvas: dark ? Qt.darker(system.window, 1.35) : Qt.darker(system.window, 1.05)
    readonly property color card: dark ? system.window : Qt.lighter(system.window, 1.12)
    readonly property color text: system.windowText
    readonly property color accent: system.highlight
    readonly property color accentText: system.highlightedText
    readonly property color hairline: tint(text, 0.12)

    // ---- shades of the text colour laid over the background
    readonly property real hover: 0.07
    readonly property real selected: 0.14
    readonly property real stripe: 0.035              // every other row of the track table
    function tint(base, alpha) { return Qt.rgba(base.r, base.g, base.b, alpha) }

    // ---- layout
    readonly property int wideBreakpoint: 720         // narrower than this the sidebar becomes a drawer over the page
    readonly property int gap: 10                     // between the card and the page, and around the window's edge
    readonly property int cardRadius: 16
    readonly property int sidebarWidth: 230
    readonly property int headerHeight: 48
    readonly property int sidebarRowHeight: 32
    readonly property int tableRowHeight: 26
    readonly property int tableHeaderHeight: 28
    readonly property int albumTileMin: 160          // albums grid: tiles grow from this to fill the row
    readonly property int radius: 6
    readonly property int toggleSize: 28

    readonly property int iconSize: 18
    readonly property int wheelStep: 60               // pixels for one notch of a mouse wheel
}
