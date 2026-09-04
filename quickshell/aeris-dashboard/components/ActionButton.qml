import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    signal clicked()

    property string symbol: "◇"
    property string iconName: "star-four-points"
    property string label: "Action"
    property color accent: Theme.teal

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

        ThemeIcon {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            name: root.iconName
            color: root.accent
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            color: "#e7ecf2"
            font.family: Theme.fontFamily
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
