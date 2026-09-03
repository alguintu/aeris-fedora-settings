import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    property string title: ""
    property string eyebrow: ""
    property color accent: "#77d7cb"

    spacing: 10

    Rectangle {
        Layout.preferredWidth: 5
        Layout.preferredHeight: 18
        radius: 3
        color: root.accent
    }

    DashboardHeaderLabel {
        Layout.fillWidth: true
        text: root.title
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
