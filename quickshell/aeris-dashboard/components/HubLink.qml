import QtQuick
import QtQuick.Controls as Controls

Controls.AbstractButton {
    id: root
    property string label: ""
    property string detail: ""
    property color accent: Theme.teal
    property string hint: ""
    implicitHeight: 42
    Accessible.name: label
    background: Rectangle {
        radius: Theme.radius / 2
        color: root.down ? Theme.tintedSurface(root.accent, 0.24) : root.hovered ? Theme.raised : "transparent"
    }
    contentItem: Item {
        opacity: root.enabled ? 1 : 0.45
        Text {
            anchors.left: parent.left; anchors.right: arrow.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.detail ? -12 : 0
            text: root.label; elide: Text.ElideRight; color: root.accent
            font.family: Theme.fontFamily; font.pixelSize: Theme.sectionTitleSize
        }
        Text {
            anchors.left: parent.left; anchors.right: arrow.left
            anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: 12
            visible: root.detail.length > 0
            text: root.detail; elide: Text.ElideRight; color: Theme.muted
            font.family: Theme.fontFamily; font.pixelSize: Theme.headerDetailSize
        }
        Text {
            id: arrow
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: "↗"; color: Theme.muted; width: 24
            font.family: Theme.fontFamily; font.pixelSize: 22
        }
    }
    Controls.ToolTip.visible: hovered && hint.length > 0
    Controls.ToolTip.text: hint
    Controls.ToolTip.delay: 600
}
