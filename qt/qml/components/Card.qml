import QtQuick

// A panel that floats on the window's canvas: rounded, a hairline around it.
Rectangle {
    color: Theme.card
    radius: Theme.cardRadius
    border.width: 1
    border.color: Theme.hairline
}
