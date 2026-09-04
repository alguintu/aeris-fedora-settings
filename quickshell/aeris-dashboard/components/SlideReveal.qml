import QtQuick

// Keep layout dimensions fixed; only move the finished panel. No layer at rest.
Item {
    id: root
    default property alias content: panel.data
    property bool collapsed: false
    property real reveal: collapsed ? 0 : 1
    readonly property bool moving: motion.running
    readonly property bool fullyHidden: reveal === 0 && !moving
    readonly property bool interactive: !collapsed && !moving && reveal === 1
    readonly property bool presentationActive: interactive && visible
    readonly property real panelOffset: (1 - reveal) * height
    clip: true

    Behavior on reveal {
        NumberAnimation {
            id: motion
            duration: root.collapsed ? 220 : 260
            easing.type: root.collapsed ? Easing.InCubic : Easing.OutCubic
        }
    }

    Item {
        id: panel
        width: root.width
        height: root.height
        y: root.panelOffset
        visible: root.reveal > 0
        enabled: root.interactive
        // A restrained fade while sliding, not a dissolve of individual widgets.
        opacity: 0.8 + 0.2 * root.reveal
        layer.enabled: root.moving
        layer.smooth: true
    }
}
