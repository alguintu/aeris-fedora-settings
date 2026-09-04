import QtQuick
import Quickshell.Widgets
import "WeatherScene.js" as WeatherScene

// Accelerated atmosphere, with the reference Canvas renderer retained for A/B checks.

ClippingRectangle {
    id: root
    property string condition: "unknown"
    property bool isDay: true
    property bool animationEnabled: true
    property bool useCanvasRenderer: false
    property real fixedTime: -1
    property real elapsed: 0
    readonly property real sceneTime: fixedTime >= 0 ? fixedTime : elapsed
    readonly property bool softwareDaylight: GraphicsInfo.api === GraphicsInfo.Software
        && (condition === "clear" || (condition === "partly-cloudy" && isDay))
    readonly property bool fallback: useCanvasRenderer || softwareDaylight || accelerated.shaderFailed
    onConditionChanged: elapsed = 0
    readonly property bool moving: animationEnabled && visible && fixedTime < 0 && condition !== "unknown"
    color: "transparent"
    radius: Theme.radius

    // Pause in place off-page; never catch up elapsed time after sleep/restore.
    Timer {
        interval: 33
        repeat: true
        running: root.moving
        onTriggered: {
            root.elapsed += interval / 1000
            if (root.fallback) atmosphere.requestPaint()
        }
    }

    WeatherAtmosphere {
        id: accelerated
        visible: !root.fallback
        condition: root.useCanvasRenderer || root.softwareDaylight ? "unknown" : root.condition
        isDay: root.isDay
        elapsed: root.sceneTime
        transform: Scale { xScale: root.width / 480; yScale: root.height / 206 }
    }

    Canvas {
        id: atmosphere
        anchors.fill: parent
        visible: root.fallback
        onVisibleChanged: if (visible) requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: root
            function onConditionChanged() { atmosphere.requestPaint() }
            function onIsDayChanged() { atmosphere.requestPaint() }
            function onFixedTimeChanged() { atmosphere.requestPaint() }
        }
        onPaint: WeatherScene.paint(getContext("2d"), width, height,
                                    root.condition, root.isDay, root.sceneTime)
    }
}
