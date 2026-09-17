import QtQuick

Item {
    id: root
    property bool running: visible
    property bool pixelMode: false
    // Reuse the CH260 perforations as noninteractive, animated card decoration.
    property bool backdropMode: false
    property real elapsed: 0
    readonly property bool animationRegistered: tick.registered || pixelTick.running
    readonly property int blendStatus: wave.status
    // Match the shader's eleven square-cell columns and full chase traversal.
    readonly property int backdropRows: Math.max(Math.floor(height / Math.max(width / 11, 1)), 1)
    readonly property int backdropCycleMs: (11 * backdropRows + 12) * 250
    readonly property int backdropAnimationIndex: Math.floor(elapsed / backdropCycleMs) % 3
    readonly property string backdropAnimationName: ["Pixel rain", "Chasing trail", "Blinking stars"][backdropAnimationIndex]

    function nextBackdropAnimation() {
        if (!backdropMode) return
        elapsed = ((backdropAnimationIndex + 1) % 3) * backdropCycleMs
        if (pixelTick.running) pixelTick.restart()
    }

    DecorativeTick {
        id: tick
        running: root.running && root.visible && !root.backdropMode && !root.pixelMode
        // Keep phase continuous. The frequencies in the shader intentionally do
        // not share a short loop, so wrapping here would create a visible hitch.
        onTick: deltaMs => root.elapsed += deltaMs
    }

    // Pixel art advances in held frames, not a 60Hz interpolated light field.
    // One low-frequency timer for the entire grid; no per-cell timers.
    Timer {
        id: pixelTick
        interval: 250
        repeat: true
        running: root.running && root.visible && root.backdropMode
        onTriggered: root.elapsed += interval
    }

    ShaderEffect {
        id: wave
        anchors.fill: parent
        property vector2d size: Qt.vector2d(width, height)
        property real elapsedSeconds: root.elapsed / 1000
        property real pixelMix: root.pixelMode ? 1 : 0
        property real backdropMix: root.backdropMode ? 1 : 0
        Behavior on pixelMix {
            NumberAnimation { duration: 220; easing.type: Easing.InOutCubic }
        }
        fragmentShader: "../shaders/media-wave.frag.qsb"
        onStatusChanged: if (status === ShaderEffect.Error) console.warn("Media wave shader:", log)
    }

    Accessible.role: Accessible.Button
    Accessible.ignored: root.backdropMode
    Accessible.name: root.pixelMode ? "Show chromatic waves" : "Show CH260 pixel music"
    Accessible.onPressAction: if (!root.backdropMode) root.pixelMode = !root.pixelMode
    TapHandler { enabled: !root.backdropMode; onTapped: root.pixelMode = !root.pixelMode }
}
