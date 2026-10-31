import QtQuick
import QtQuick.Controls

// The little circle that folds the sidebar away, or brings it back: PanelToggle { glyph: "layout-sidebar"; label: qsTr("Library") }.
Rectangle {
    id: toggle

    required property string glyph
    required property string label
    property bool active: false      // the panel it controls is showing
    signal clicked()

    implicitWidth: Theme.toggleSize
    implicitHeight: Theme.toggleSize
    radius: width / 2
    color: tap.pressed ? Theme.tint(Theme.text, Theme.selected) : hover.hovered ? Theme.tint(Theme.text, Theme.hover) : "transparent"
    border.width: 1
    border.color: Theme.hairline

    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: toggle.clicked()

    Icon { anchors.centerIn: parent; name: toggle.glyph; size: 16; opacity: toggle.active ? 1 : 0.6 }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; onTapped: toggle.clicked() }
    ToolTip.visible: hover.hovered
    ToolTip.delay: 500
    ToolTip.text: label
}
