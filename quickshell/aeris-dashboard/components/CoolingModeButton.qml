import QtQuick
import QtQuick.Effects

Rectangle {
    id: root

    signal clicked()

    property string iconKind: "default"
    property color accent: "#77d7cb"
    property bool selected: false
    property bool available: true
    property bool busy: false
    property bool flat: false
    readonly property bool hovered: touchArea.containsMouse
    readonly property bool pressed: touchArea.pressed

    implicitWidth: 112
    implicitHeight: 112
    radius: 16
    color: root.flat ? "transparent" : (root.selected ? "#e632293d" : (touchArea.pressed ? "#e62b3442" : "#dc151c29"))
    border.color: root.selected ? root.accent : (touchArea.containsMouse ? root.accent : "#4c4d5a70")
    border.width: root.flat ? 0 : (root.selected ? 2 : 1)
    opacity: root.available ? 1.0 : 0.48

    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on border.width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    Item {
        id: icon
        anchors.centerIn: parent
        width: 64
        height: 64
        readonly property string iconPath: root.iconKind === "default" ? "icons/fan"
            : root.iconKind === "quiet" ? "feather/wind"
            : root.iconKind === "performance" ? "feather/zap" : "feather/cpu"
        property color color: root.selected ? root.accent : "#6f7b8b"
        scale: root.selected ? 1.0 : 0.9
        Behavior on color { ColorAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Image {
            id: artwork
            anchors.fill: parent
            source: "../assets/" + icon.iconPath + ".svg"
            sourceSize.width: 128
            sourceSize.height: 128
            visible: false
        }
        MultiEffect {
            anchors.fill: artwork
            source: artwork
            colorization: 1
            colorizationColor: icon.color
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
