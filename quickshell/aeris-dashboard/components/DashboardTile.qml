import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    default property alias tileContent: contentItem.data
    property string title: ""
    property string eyebrow: ""
    property color accent: "#77d7cb"

    radius: 18
    color: "#dc151c29"
    border.color: "#4c4d5a70"
    border.width: 1

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            visible: root.title.length > 0 || root.eyebrow.length > 0
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 5
                Layout.preferredHeight: 18
                radius: 3
                color: root.accent
            }

            Text {
                Layout.fillWidth: true
                text: root.title
                color: "#eef3f8"
                font.family: "Noto Sans"
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }

            Text {
                text: root.eyebrow
                color: root.accent
                font.family: "Noto Sans"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.letterSpacing: 1.2
            }
        }

        Item {
            id: contentItem
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
