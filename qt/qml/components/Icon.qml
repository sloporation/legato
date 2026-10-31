import QtQuick

// A Tabler icon by name, e.g. Icon { name: "disc"; color: "red"; size: 24 }
Text {
    property string name
    property int size: Theme.iconSize

    text: Tabler.glyphs[name] ?? ""
    color: Theme.text
    font.family: Tabler.family
    font.pixelSize: size
}
