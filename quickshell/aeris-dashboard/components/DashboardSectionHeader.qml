import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    property string title: ""
    property string iconName: ""
    property string detail: ""
    property string eyebrow: ""
    property color accent: Theme.teal

    spacing: 6

    Rectangle {
        visible: root.iconName.length === 0
        Layout.preferredWidth: 5
        Layout.preferredHeight: 20
        radius: 3
        color: root.accent
    }

    DashboardHeaderLabel {
        visible: root.iconName.length === 0
        Layout.fillWidth: root.detail.length === 0
        text: root.title
        font.pixelSize: 20
    }

    ThemeIcon {
        visible: root.iconName.length > 0
        Layout.preferredWidth: 26
        Layout.preferredHeight: 26
        name: root.iconName
        color: root.accent
    }

    Text {
        visible: root.detail.length > 0
        Layout.fillWidth: true
        text: root.detail
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 18
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    Text {
        text: root.eyebrow
        color: root.accent
        font.family: Theme.fontFamily
        font.pixelSize: 18
        font.weight: Font.DemiBold
    }
}
