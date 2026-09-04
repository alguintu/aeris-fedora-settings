import QtQuick

Rectangle {
    id: root

    signal clicked()

    property string iconKind: "aeris"
    property color accent: Theme.teal
    property bool selected: false
    property bool available: true
    property bool busy: false
    property bool flat: false
    readonly property bool hovered: touchArea.containsMouse
    readonly property bool pressed: touchArea.pressed
    property bool componentReady: false

    implicitWidth: 112
    implicitHeight: 112
    radius: Theme.radius
    color: root.flat ? "transparent" : (root.selected ? Theme.raised : (touchArea.pressed ? Theme.inset : Theme.surface))
    border.color: root.selected ? root.accent : (touchArea.containsMouse ? root.accent : Theme.border)
    border.width: root.flat ? 0 : (root.selected ? 2 : 1)
    opacity: root.available ? 1.0 : 0.48

    Behavior on color {
        ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
    Behavior on border.color {
        ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
    Behavior on border.width {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
    Behavior on opacity {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    onIconKindChanged: {
        if (componentReady) {
            iconSwap.stop()
            iconSwap.start()
        }
    }

    Component.onCompleted: {
        componentReady = true
        iconState.displayedIconKind = iconKind
    }

    Item {
        id: iconState
        property string displayedIconKind: root.iconKind
        property color iconColor: root.selected ? root.accent : Theme.inactive
        scale: root.selected ? 1.0 : 0.88

        Behavior on iconColor {
            ColorAnimation { duration: 240; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }
    }

    ThemeIcon {
        anchors.centerIn: parent
        width: 64
        height: 64
        name: iconState.displayedIconKind === "aeris" ? "aeris"
            : iconState.displayedIconKind === "night" ? "reference-moon"
            : iconState.displayedIconKind === "day" ? "white-balance-sunny"
            : iconState.displayedIconKind === "off" ? "lights-off" : "star-four-points"
        color: iconState.iconColor
        scale: iconState.scale
        opacity: iconState.opacity
    }

    SequentialAnimation {
        id: iconSwap

        NumberAnimation {
            target: iconState
            property: "opacity"
            to: 0
            duration: 80
            easing.type: Easing.InCubic
        }
        ScriptAction {
            script: {
                iconState.displayedIconKind = root.iconKind
            }
        }
        NumberAnimation {
            target: iconState
            property: "opacity"
            to: 1
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    MouseArea {
        id: touchArea
        anchors.fill: parent
        enabled: root.available && !root.busy
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
