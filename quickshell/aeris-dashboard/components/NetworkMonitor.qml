import QtQuick
import QtQuick.Controls as Controls

Item {
    id: root
    property bool presentationActive: true
    property bool healthy: false
    property var sample: ({})
    property var shownSample: ({})
    Binding on shownSample {
        when: root.presentationActive
        value: root.sample
        restoreMode: Binding.RestoreNone
    }
    readonly property bool ready: healthy && shownSample.ok === true && shownSample.ready === true
    readonly property real receiveTarget: ready ? intensity(shownSample.rxBytesPerSecond) : 0
    readonly property real sendTarget: ready ? intensity(shownSample.txBytesPerSecond) : 0
    property real receiveLevel: 0
    property real sendLevel: 0
    property real elapsed: 0
    readonly property bool animationRegistered: tick.registered
    readonly property int shaderStatus: wave.status

    function intensity(bytes) {
        // Perceptual, not a bandwidth percentage: log scaling leaves room for
        // both background activity and large transfers, without peak rescaling.
        return Math.max(0, Math.min(1, Math.log(1 + Math.max(0, Number(bytes) || 0) / 2048) / Math.log(1 + 104857600 / 2048)))
    }
    function rate(bytes) {
        const value = Math.max(0, Number(bytes) || 0)
        if (value >= 1048576) return (value / 1048576).toFixed(1) + " MiB/s"
        if (value >= 1024) return (value / 1024).toFixed(1) + " KiB/s"
        return Math.round(value) + " B/s"
    }

    DashboardHeaderLabel {
        id: label
        objectName: "network-header"
        anchors.top: parent.top
        anchors.left: parent.left
        text: "NETWORK"
        color: root.ready ? Theme.teal : Theme.inactive
    }
    Row {
        objectName: "network-rates"
        anchors.right: parent.right
        anchors.baseline: label.baseline
        baselineOffset: receiveRate.baselineOffset
        spacing: Theme.spacingUnit
        TransferRateLabel {
            id: receiveRate
            objectName: "network-receive-rate"
            direction: "↓"
            bytesPerSecond: root.ready ? root.shownSample.rxBytesPerSecond : null
            color: root.ready ? Theme.teal : Theme.inactive
        }
        TransferRateLabel {
            objectName: "network-send-rate"
            direction: "↑"
            bytesPerSecond: root.ready ? root.shownSample.txBytesPerSecond : null
            color: root.ready ? Theme.mauve : Theme.inactive
        }
    }

    DecorativeTick {
        id: tick
        running: root.presentationActive && root.visible
            && Math.max(root.receiveTarget, root.sendTarget, root.receiveLevel, root.sendLevel) > 0.005
        onTick: deltaMs => {
            const blend = 1 - Math.exp(-deltaMs / 650)
            root.receiveLevel += (root.receiveTarget - root.receiveLevel) * blend
            root.sendLevel += (root.sendTarget - root.sendLevel) * blend
            if (root.receiveTarget === 0 && root.receiveLevel < 0.006) root.receiveLevel = 0
            if (root.sendTarget === 0 && root.sendLevel < 0.006) root.sendLevel = 0
            root.elapsed += deltaMs / 1000
        }
    }
    ShaderEffect {
        id: wave
        objectName: "network-wave"
        anchors.top: label.bottom
        anchors.topMargin: Theme.spacingUnit
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        property vector2d size: Qt.vector2d(width, height)
        property real time: root.elapsed
        property real receive: root.receiveLevel
        property real send: root.sendLevel
        property color receiveColor: Theme.teal
        property color sendColor: Theme.mauve
        opacity: root.ready ? 1 : 0.35
        fragmentShader: "../shaders/network-wave.frag.qsb"
        onStatusChanged: if (status === ShaderEffect.Error) console.warn("Network shader:", log)
    }
    HoverHandler { id: hover }
    Controls.ToolTip.visible: hover.hovered
    Controls.ToolTip.text: !root.healthy || root.shownSample.ok !== true ? "Network telemetry unavailable"
        : !root.ready ? "Waiting for a network sample"
        : "Receive " + rate(root.shownSample.rxBytesPerSecond) + " · Send " + rate(root.shownSample.txBytesPerSecond)
            + "\n" + (root.shownSample.interfaces || []).join(", ") + " · Soft activity display, not a time-series graph"
}
