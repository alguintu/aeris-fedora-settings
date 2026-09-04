import QtQuick
import QtQuick.Window
import Quickshell
import "components" as Components

// Isolated presentation-only smoke test. No daemon, media, or hardware services.
ShellRoot {
    id: root
    property int step: 0
    property real pausedTime: 0
    property real pausedRam: 0
    property int pausedGpu: 0
    property real pausedBlend: 0
    function check(ok, message) {
        if (!ok) {
            console.error("PRESENTATION_TEST_FAILED: " + message)
            Qt.exit(1)
        }
    }
    Components.MemoryHeatmap {
        id: ram
        width: 180; height: 132
        field: "ram"; ramUtilization: 37; animationEnabled: false
    }
    Components.MemoryHeatmap {
        id: vram
        width: 180; height: 132
        field: "vram"; vramUtilization: 50; smoothedVram: 50
    }
    Components.GpuHeatmap {
        id: gpu
        width: 280; height: 132
        utilization: 99; smoothedUtilization: 99; animationEnabled: false
    }
    Components.WeatherPattern {
        id: weather
        width: 480; height: 206
        condition: "clear"; animationEnabled: false; useCanvasRenderer: true
    }
    Window {
        visible: true; width: 100; height: 20
        Components.HeatmapSurface {
            id: swatches
            anchors.fill: parent; columns: 2; rows: 1
            transitionMs: 1500
            cellColors: [Qt.rgba(0, 0, 0, 1), Qt.rgba(0, 0, 0, 1)]
        }
        Components.HeatmapSurface {
            id: twin
            anchors.fill: parent; columns: 2; rows: 1
            transitionMs: swatches.transitionMs
            cellColors: swatches.cellColors
            animationEnabled: swatches.animationEnabled
        }
    }
    Timer {
        interval: 300; repeat: true; running: true
        onTriggered: {
            root.step++
            if (root.step === 1) {
                root.check(swatches.frames.length === 2, "software heatmap receives its initial frame")
                swatches.cellColors = [Qt.rgba(1, 0, 0, 1), Qt.rgba(0, 1, 0, 1)]
                root.check(ram.smoothedRam === 0, "hidden RAM must not tick")
                root.check(gpu.activeCount === 0, "hidden GPU must not tick")
                root.check(weather.elapsed === 0, "hidden atmosphere must not tick")
                root.check(vram.settled, "unchanged VRAM must stop its timer")
                vram.vramUtilization = 80
                root.check(!vram.settled, "new telemetry must wake settled VRAM")
                ram.animationEnabled = true
                gpu.animationEnabled = true
                weather.animationEnabled = true
            } else if (root.step === 2) {
                root.check(swatches.elapsedMs > 0, "software blend must not wait for a hidden GPU atlas")
                root.check(swatches.elapsedMs === twin.elapsedMs, "grids must advance on the same shared tick")
                root.pausedBlend = swatches.elapsedMs
                swatches.animationEnabled = false
                root.check(ram.smoothedRam > 0 && ram.ramActiveCount > 0, "RAM must resume")
                root.check(gpu.activeCount > 0, "GPU must resume")
                root.check(weather.elapsed > 0, "atmosphere must resume")
                root.check(vram.smoothedVram > 50, "VRAM must follow fresh telemetry")
                root.pausedTime = weather.elapsed
                root.pausedRam = ram.smoothedRam
                root.pausedGpu = gpu.activeCount
                ram.animationEnabled = false
                gpu.animationEnabled = false
                weather.animationEnabled = false
            } else if (root.step === 3) {
                root.check(swatches.elapsedMs === root.pausedBlend, "heatmap blend pauses off-page")
                swatches.animationEnabled = true
                root.check(ram.smoothedRam === root.pausedRam, "RAM must pause in place")
                root.check(gpu.activeCount === root.pausedGpu, "GPU must pause in place")
                root.check(weather.elapsed === root.pausedTime, "weather must pause in place")
                weather.fixedTime = 7
                weather.animationEnabled = true
            } else {
                root.check(swatches.elapsedMs > root.pausedBlend, "heatmap blend resumes")
                root.check(weather.sceneTime === 7, "fixed-time A/B must be deterministic")
                root.check(weather.elapsed === root.pausedTime, "fixed-time A/B must not tick")
                root.check(ram.fittedCellSize(180, 132) > 0, "memory cells retain valid sizing")
                swatches.animationEnabled = false
                vram.animationEnabled = false
                console.warn("PRESENTATION_TEST_PASSED")
                finish.start()
            }
        }
    }
    // Quickshell logs asynchronously; let the success marker flush before exit.
    Timer {
        id: finish; interval: 100
        onTriggered: {
            root.check(Components.DecorativeClock.users === 0, "decorative clock must stop when all clients pause")
            Qt.quit()
        }
    }
    Timer { interval: 5000; running: true; onTriggered: Qt.exit(2) }
}
