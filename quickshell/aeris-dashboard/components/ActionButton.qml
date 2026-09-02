import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    signal clicked()

    property string symbol: "◇"
    property string label: "Action"
    property color accent: "#77d7cb"

    implicitWidth: 104
    implicitHeight: 88
    radius: 15
    color: touchArea.pressed ? "#4a344158" : "#29313f"
    border.color: touchArea.containsMouse ? root.accent : "#3b4657"
    border.width: 1

    Behavior on color { ColorAnimation { duration: 100 } }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 7

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.symbol
            color: root.accent
            font.family: "Noto Sans Symbols 2"
            font.pixelSize: 28
            font.weight: Font.DemiBold
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            color: "#e7ecf2"
            font.family: "Noto Sans"
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }

    MouseArea {
        id: touchArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
