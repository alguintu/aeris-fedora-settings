import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

RowLayout {
    id: root

    property string title: ""
    property string iconName: ""
    property string detail: ""
    property string detailHint: ""
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
        font.pixelSize: Theme.sectionTitleSize
    }

    ThemeIcon {
        visible: root.iconName.length > 0
        Layout.preferredWidth: Theme.headerIconSize
        Layout.preferredHeight: Theme.headerIconSize
        name: root.iconName
        color: root.accent
    }

    Text {
        visible: root.detail.length > 0
        Layout.fillWidth: true
        text: root.detail
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.headerDetailSize
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        Accessible.description: root.detailHint
        HoverHandler { id: detailHover }
        Controls.ToolTip.visible: detailHover.hovered && root.detailHint.length > 0
        Controls.ToolTip.delay: 700
        Controls.ToolTip.text: root.detailHint
    }

    Text {
        text: root.eyebrow
        color: root.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.headerDetailSize
        font.weight: Font.DemiBold
    }
}
