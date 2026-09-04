import QtQuick

Item {
    id: root
    property bool running: visible
    property bool pixelMode: false
    property real elapsed: 0
    readonly property bool animationRegistered: tick.registered
    readonly property int blendStatus: wave.status

    DecorativeTick {
        id: tick
        running: root.running && !root.pixelMode
        // Keep phase continuous. The frequencies in the shader intentionally do
        // not share a short loop, so wrapping here would create a visible hitch.
        onTick: deltaMs => root.elapsed += deltaMs
    }

    ShaderEffect {
        id: wave
        anchors.fill: parent
        property vector2d size: Qt.vector2d(width, height)
        property real elapsedSeconds: root.elapsed / 1000
        property real pixelMix: root.pixelMode ? 1 : 0
        Behavior on pixelMix {
            NumberAnimation { duration: 220; easing.type: Easing.InOutCubic }
        }
        fragmentShader: "../shaders/media-wave.frag.qsb"
        onStatusChanged: if (status === ShaderEffect.Error) console.warn("Media wave shader:", log)
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.pixelMode ? "Show chromatic waves" : "Show CH260 pixel music"
    Accessible.onPressAction: root.pixelMode = !root.pixelMode
    TapHandler { onTapped: root.pixelMode = !root.pixelMode }
}
