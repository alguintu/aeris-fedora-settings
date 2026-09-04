import QtQuick
import "WeatherScene.js" as WeatherScene

// Paint only when the texture changes. Position/opacity are GPU scene-graph work.
Canvas {
    id: root
    property string rgb: "201,211,222"
    property real intensity: 0.1
    property real density: 0.08
    onRgbChanged: requestPaint()
    onIntensityChanged: requestPaint()
    onDensityChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        WeatherScene.mist(ctx, width / 2, height / 2, width / 2, height / 2,
                          rgb, intensity, density)
    }
}
