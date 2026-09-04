import QtQuick
import "WeatherScene.js" as WeatherScene

ShaderEffect {
    id: root
    property real elapsed: 0
    property real strength: 1
    readonly property real hazeX: 175 + Math.sin(elapsed * 0.30) * 65
    readonly property var shafts: WeatherScene.sunShafts(elapsed)
    function vector(s) { return Qt.vector4d(s.x, s.slope, s.spread, s.light) }
    readonly property vector4d shaft0: vector(shafts[0])
    readonly property vector4d shaft1: vector(shafts[1])
    readonly property vector4d shaft2: vector(shafts[2])
    readonly property vector4d shaft3: vector(shafts[3])
    readonly property vector4d shaft4: vector(shafts[4])
    readonly property vector4d shaft5: vector(shafts[5])
    fragmentShader: Qt.resolvedUrl("../shaders/daylight.frag.qsb")
    onStatusChanged: if (status === ShaderEffect.Error) console.warn("Daylight shader:", log)
}
