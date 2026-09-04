import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    default property alias tileContent: contentItem.data
    property string title: ""
    property string eyebrow: ""
    property color accent: Theme.teal
    property real contentMargin: 18

    radius: Theme.radius
    color: Theme.surface
    border.color: Theme.border
    border.width: 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.contentMargin
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
