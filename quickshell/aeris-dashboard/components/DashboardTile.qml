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

        DashboardSectionHeader {
            Layout.fillWidth: true
            visible: root.title.length > 0 || root.eyebrow.length > 0
            title: root.title
            eyebrow: root.eyebrow
            accent: root.accent
        }

        Item {
            id: contentItem
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
