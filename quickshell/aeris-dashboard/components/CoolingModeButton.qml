import QtQuick

Rectangle {
    id: root

    signal clicked()

    property string iconKind: "default"
    property color accent: Theme.teal
    property bool selected: false
    property bool available: true
    property bool busy: false
    property bool flat: false
    readonly property bool hovered: touchArea.containsMouse
    readonly property bool pressed: touchArea.pressed

    implicitWidth: 112
    implicitHeight: 112
    radius: Theme.radius
    color: root.flat ? "transparent" : (root.selected ? Theme.raised : (touchArea.pressed ? Theme.inset : Theme.surface))
    border.color: root.selected ? root.accent : (touchArea.containsMouse ? root.accent : Theme.border)
    border.width: root.flat ? 0 : (root.selected ? 2 : 1)
    opacity: root.available ? 1.0 : 0.48

    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on border.width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    ThemeIcon {
        anchors.centerIn: parent
        width: 64
        height: 64
        name: root.iconKind === "default" ? "fan"
            : root.iconKind === "quiet" ? "weather-windy"
            : root.iconKind === "performance" ? "lightning-bolt" : "chip"
        color: root.selected ? root.accent : Theme.inactive
        scale: root.selected ? 1.0 : 0.9
        Behavior on color { ColorAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: touchArea
        anchors.fill: parent
        enabled: root.available && !root.busy
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
