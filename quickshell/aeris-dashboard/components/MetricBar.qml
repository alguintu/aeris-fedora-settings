import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string label: ""
    property string valueText: "--"
    property real progress: 0
    property color accent: Theme.teal

    implicitHeight: 34

    RowLayout {
        anchors.fill: parent
        spacing: 10

        Text {
            Layout.preferredWidth: 46
            text: root.label
            color: "#cbd3dd"
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 7
            radius: 4
            color: "#2e3746"

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, root.progress))
                height: parent.height
                radius: parent.radius
                color: root.accent

                Behavior on width {
                    NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                }
            }
        }

        Text {
            Layout.preferredWidth: 80
            horizontalAlignment: Text.AlignRight
            text: root.valueText
            color: "#f4f7fa"
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }
}
