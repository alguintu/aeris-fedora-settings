import QtQuick
import "WeatherScene.js" as Scene

// Design-space scene: cached soft textures and inexpensive moving geometry.
// Only daylight needs a custom shader; none of these textures repaint per frame.
Item {
    id: root
    property string condition: "unknown"
    property bool isDay: true
    property real moonPhase: 0.75
    property real moonIllumination: 0.5
    property real elapsed: 0
    readonly property bool storm: condition === "storm"
    readonly property bool broken: condition === "partly-cloudy"
    readonly property bool daylight: condition === "clear" || (broken && isDay)
    // Night illumination is the background state, not a competing condition.
    // Weather layers remain in front, naturally obscuring it when dense.
    readonly property bool night: condition === "night" || (!isDay && condition !== "unknown")
    readonly property bool deck: ["partly-cloudy", "cloudy", "rain", "storm", "snow"].indexOf(condition) >= 0
    readonly property bool shaderFailed: sun.item !== null && sun.item.status === ShaderEffect.Error
    width: 480
    height: 206

    Loader {
        id: sun
        anchors.fill: parent
        active: root.daylight
        sourceComponent: WeatherDaylight {
            elapsed: root.elapsed
            strength: root.broken ? 0.7 : 1
        }
    }

    Loader {
        anchors.fill: parent
        active: root.night
        sourceComponent: Item {
            Repeater {
                // Three cached textures provide a fuller sky while only three
                // scene-graph opacities breathe per frame.
                model: 3
                Canvas {
                    required property int index
                    anchors.fill: parent
                    opacity: (0.76 + 0.1 * Math.sin(root.elapsed * (0.42 + index * 0.09)
                                                     + index * 2.1))
                        * (0.94 - root.moonIllumination * 0.22)
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        Scene.starLayer(ctx, index, 3, 39)
                    }
                }
            }
            Canvas {
                anchors.fill: parent
                onMoonPhaseChanged: requestPaint()
                property real moonPhase: root.moonPhase
                property real moonIllumination: root.moonIllumination
                onMoonIlluminationChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    Scene.moon(ctx, 286, 42, 29, moonPhase, moonIllumination)
                }
            }
        }
    }

    Repeater {
        model: root.condition === "fog" ? 18 : 0
        WeatherMist {
            required property int index
            readonly property int depth: Math.floor(index / 6)
            readonly property int i: index % 6
            readonly property int n: i + depth * 9
            width: (145 + Scene.seed(n) * 100) * 2
            height: (34 + Scene.seed(n + 30) * 38) * 2
            x: ((i * 163 + root.elapsed * (7 + depth * 5) + depth * 103) % 1000) - 250 - width / 2
            y: 55 + depth * 66 + Math.sin(root.elapsed * 0.24 + n) * 16 - height / 2
            intensity: 0.065 + depth * 0.018
        }
    }

    Repeater {
        model: root.condition === "rain" || root.storm ? (root.storm ? 90 : 52) : 0
        Rectangle {
            required property int index
            readonly property real depth: Scene.seed(index + 7)
            readonly property real slant: root.storm ? 0.44 : 0.18
            readonly property real speed: (root.storm ? 235 : 145) + depth * 100
            readonly property real travel: (Scene.seed(index + 70) * 272 + root.elapsed * speed) % 272
            readonly property real dropY: travel - 24
            readonly property real length: 6 + depth * (root.storm ? 13 : 9)
            width: 0.6 + depth * 0.7
            height: length * Math.sqrt(1 + slant * slant)
            x: Scene.seed(index + 130) * 640 - 25 - travel * slant
            y: dropY - height
            rotation: Math.atan(slant) * 180 / Math.PI
            transformOrigin: Item.BottomLeft
            radius: width / 2
            color: "#bccfe2"
            opacity: (0.07 + depth * 0.12) * Math.min(1, Math.max(0, (dropY - 18) / 40))
            antialiasing: true
        }
    }

    Loader {
        active: root.storm
        sourceComponent: WeatherMist {
            x: -100; y: 140; width: 660; height: 100
            rgb: "161,179,202"; intensity: 0.06; density: 0.1
        }
    }

    Repeater {
        model: root.condition === "snow" ? 38 : 0
        Rectangle {
            required property int index
            readonly property real depth: Scene.seed(index + 40)
            readonly property real radiusValue: 0.7 + depth * 1.5
            x: Scene.seed(index + 84) * 500 + Math.sin(root.elapsed * 0.8 + index) * (4 + depth * 8) - 10 - radiusValue
            y: (Scene.seed(index + 4) * 248 + root.elapsed * (13 + depth * 22)) % 248 - 20 - radiusValue
            width: radiusValue * 2; height: width; radius: radiusValue
            color: "#e1e9f3"; opacity: 0.1 + depth * 0.17
            antialiasing: true
        }
    }

    Loader {
        active: root.storm
        sourceComponent: Canvas {
            // Build one texture per strike. Animate its opacity, not its paths.
            width: 480; height: 206
            readonly property var strike: Scene.lightningState(root.elapsed)
            readonly property int cycle: strike.cycle
            opacity: strike.strength
            onCycleChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                Scene.lightning(ctx, cycle * 14 + 2.2 + Scene.seed(cycle + 501) * 3.6 + 0.09)
            }
        }
    }

    Repeater {
        model: root.deck ? (root.broken ? 3 : 5) : 0
        Canvas {
            required property int index
            readonly property real speed: (root.storm ? 25 : root.broken ? 14 : 18) + index * 2.5
            readonly property real cloudScale: root.broken ? 0.7 + index * 0.15 : 1 + (index % 2) * 0.22
            readonly property real ink: root.storm ? 0.2 : root.broken ? 0.105 : 0.13
            readonly property bool dark: root.storm
            width: 380; height: 240
            scale: cloudScale
            transformOrigin: Item.TopLeft
            x: ((index * 257 + root.elapsed * speed + 200) % 1000) - 260 - 170 * cloudScale
            y: (root.broken ? 110 + (index % 2) * 48 : 28 + (index % 3) * 39) - 120 * cloudScale
            onInkChanged: requestPaint()
            onDarkChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset(); ctx.translate(170, 120)
                Scene.cloud(ctx, 0, 0, 1, ink, dark)
            }
        }
    }
}
