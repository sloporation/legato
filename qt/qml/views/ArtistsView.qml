import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

// Not built yet.
Item {
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 10
        Icon { name: "microphone-2"; size: 40; opacity: 0.4; Layout.alignment: Qt.AlignHCenter }
        Label { text: qsTr("Artists"); font.pixelSize: 16; font.bold: true; Layout.alignment: Qt.AlignHCenter }
        Label { text: qsTr("Coming soon."); opacity: 0.6; Layout.alignment: Qt.AlignHCenter }
    }
}
