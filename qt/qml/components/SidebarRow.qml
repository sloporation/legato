import QtQuick
import QtQuick.Controls

// One line of the sidebar: an icon and a name, filled with the accent colour when it is the page showing.
Rectangle {
    id: row

    required property string glyph
    required property string label
    property bool selected: false
    signal clicked()

    height: Theme.sidebarRowHeight
    radius: Theme.radius
    color: selected ? Theme.accent
         : tap.pressed ? Theme.tint(Theme.text, Theme.selected)
         : hover.hovered ? Theme.tint(Theme.text, Theme.hover) : "transparent"

    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: row.clicked()

    Icon {
        id: icon
        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
        name: row.glyph
        color: row.selected ? Theme.accentText : Theme.accent
    }
    Label {
        anchors { left: icon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        text: row.label
        elide: Text.ElideRight
        color: row.selected ? Theme.accentText : Theme.text
    }

    HoverHandler { id: hover }
    TapHandler { id: tap; onTapped: row.clicked() }
}
