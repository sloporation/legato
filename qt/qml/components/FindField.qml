import QtQuick
import QtQuick.Controls

// The find field at the right of the header, as Apple Music has it: a magnifying glass, the text, and a cross to clear it. Escape clears
// it too and gives the focus back to the page.
TextField {
    id: field

    implicitHeight: Theme.toggleSize
    leftPadding: 30
    rightPadding: clear.visible ? 28 : 10
    verticalAlignment: TextInput.AlignVCenter
    font.pixelSize: 13
    selectByMouse: true
    background: Rectangle {
        radius: height / 2
        color: Theme.tint(Theme.text, field.activeFocus ? 0.10 : Theme.hover)
        border.width: 1
        border.color: field.activeFocus ? Theme.accent : Theme.hairline
    }

    Icon {
        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
        name: "search"
        size: 14
        opacity: 0.6
    }
    Icon {
        id: clear
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        visible: field.text !== ""
        name: "x"
        size: 14
        opacity: clearHover.hovered ? 0.9 : 0.6
        HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { field.clear(); field.textEdited() } }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Clear")
    }

    Keys.onEscapePressed: { clear(); textEdited(); focus = false }
}
