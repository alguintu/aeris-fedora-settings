import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Quickshell
import "components" as Components

// Run on Wayland with QSG_RHI_BACKEND=vulkan or opengl, not software/offscreen.
// No live services. Exercises the shipped shaders, texture upload, clipping and blur.
ShellRoot {
    id: root
    property int step: 0
    function check(ok, message) {
        if (!ok) { console.error("RENDERER_TEST_FAILED: " + message); Qt.exit(1) }
    }
    Window {
        visible: true; width: 640; height: 240
        color: "#303640"
        Components.FrameProbe { id: probe }
        Components.SlideReveal {
            id: slide
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: "#303640" }
            Components.WeatherPattern {
                id: weather
                x: 320; width: 320; height: 240
                condition: "clear"
            }
            Components.HeatmapSurface {
                id: heatmap
                width: 310; height: 116; columns: 2; rows: 2
                cellColors: [Qt.rgba(0.53, 0.68, 0.69, 1), Qt.rgba(0.92, 0.80, 0.55, 1),
                    Qt.rgba(0.75, 0.38, 0.42, 1), Qt.rgba(0.71, 0.56, 0.68, 1)]
            }
            Components.HeatmapSurface {
                id: cpu
                y: 124; width: 310; height: 116; cpuLayout: true
                cellColors: Array.from({length: 32}, (_, i) => Qt.rgba(0.3 + i / 64, 0.5, 0.6, 1))
            }
            Rectangle {
                x: 280; y: 70; width: 80; height: 80; radius: 16; color: "#a3be8c"
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blur: 0.5 }
            }
        }
    }
    Timer {
        interval: 400; repeat: true; running: true
        onTriggered: {
            root.step++
            root.check(slide.GraphicsInfo.api !== GraphicsInfo.Software, "must be hardware rendering")
            const expected = Quickshell.env("QSG_RHI_BACKEND") === "vulkan" ? GraphicsInfo.Vulkan : GraphicsInfo.OpenGL
            root.check(slide.GraphicsInfo.api === expected, "requested RHI must actually be selected")
            root.check(!heatmap.fallback && !cpu.fallback && !weather.fallback, "shaders must not fall back")
            if (root.step === 1) {
                console.info("RENDERER_API " + slide.GraphicsInfo.api)
                probe.start()
                heatmap.cellColors = [Qt.rgba(0.92, 0.80, 0.55, 1), Qt.rgba(0.75, 0.38, 0.42, 1),
                    Qt.rgba(0.71, 0.56, 0.68, 1), Qt.rgba(0.53, 0.68, 0.69, 1)]
                weather.condition = "storm"
            } else if (root.step === 2) {
                root.check(probe.stop().intervals > 0, "frame timing receives actual window swaps")
                slide.collapsed = true
            } else if (root.step === 3) {
                root.check(slide.fullyHidden, "collapse completes under hardware renderer")
                slide.collapsed = false
                weather.condition = "fog"
            } else if (root.step === 4) {
                root.check(slide.interactive, "restore completes under hardware renderer")
                weather.condition = "clear"
                weather.fixedTime = 7
            } else if (root.step === 5) {
                const snapshot = Quickshell.env("AERIS_RENDER_SNAPSHOT")
                if (snapshot) {
                    slide.grabToImage(result => {
                        root.check(result.saveToFile(snapshot), "save deterministic rendering comparison")
                        console.info("RENDERER_TEST_PASSED")
                        Qt.quit()
                    })
                } else {
                    console.info("RENDERER_TEST_PASSED")
                    Qt.quit()
                }
            }
        }
    }
}
