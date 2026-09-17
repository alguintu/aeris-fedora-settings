import QtQuick
import QtQuick.Window
import Quickshell
import "pages" as Pages
import "components" as Components

ShellRoot {
    id: root
    function check(ok, message) {
        if (!ok) { console.error("AI_HUB_TEST_FAILED: " + message); Qt.exit(1) }
    }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const result = find(child, name)
            if (result) return result
        }
        return null
    }
    Window {
        visible: true; width: 1920; height: 480
        Pages.WorkPage {
            id: page; x: 14; y: 14; width: 1892; height: 424
            pollingEnabled: false
            metricsHealthy: true
            metrics: ({cpuUsage: 32, gpuUsage: 99, ramUsed: 16, ramTotal: 64, vramUsed: 8, vramTotal: 16})
            aiHealthy: true
            aiState: ({apis: [
                {name: "llama.cpp", state: "READY", online: true, detail: "Local inference API ready"},
                {name: "LM Studio", state: "READY", online: true, detail: "A deliberately very long resident model name that must elide without wrapping over its neighbor"}],
                presets: [
                    {name: "Aeris Qwen3.8 Fast Text 16GB", context: 8192, offload: 1, path: "/test/fast.json"},
                    {name: "Aeris Qwen3.8 Q4 Hybrid 64GB", context: 8192, offload: 0.75, path: "/test/hybrid.json"}],
                jobs: [{name: "Read-only smoke", path: "/test/job.toml"},
                    {name: "Disposable edit", path: "/test/edit.toml"}, {name: "Write smoke", path: "/test/write.toml"}]})
        }
    }
    Timer {
        interval: 350; running: true
        onTriggered: {
            const ai = root.find(page, "hub-ai-card")
            const card = root.find(page, "hub-pomodoro-card")
            const timer = root.find(page, "hub-pomodoro")
            root.check(ai.x === 0 && ai.y === 0 && ai.width === 720 && ai.height === 176,
                "AI card retains its geometry at the page's upper-left margin")
            root.check(card.x + card.width === page.width && card.y === 0
                && card.height === page.height && card.width === Components.Theme.pomodoroTileWidth,
                "full Pomodoro retains width and right/top/bottom anchors")
            root.check(card.x - ai.width >= Components.Theme.tileGap, "no overlap or collapsed gutter")
            root.check(timer.presentationActive, "visible hub presents shared timer")
            const meters = root.find(page, "hub-resources")
            const presets = root.find(page, "hub-presets")
            const worker = root.find(page, "hub-worker")
            root.check(meters.x === ai.width + 12 && meters.x + meters.width === card.x - 12,
                "resource card fills remaining top width with shared gutters")
            root.check(meters.height === ai.height && presets.y === ai.height + 12
                && presets.y + presets.height === page.height && worker.y === presets.y
                && worker.x === meters.x && worker.width === meters.width,
                "lower cards align at top, bottom and column edges")
            for (const tile of [ai, meters, presets, worker]) root.check(tile.contentMargin === 12, "uniform inset")
            for (const pair of [["CPU", "32%"], ["GPU", "99%"], ["RAM", "25%"], ["VRAM", "50%"]])
                root.check(root.find(page, "hub-meter-" + pair[0]).readout === pair[1], "live " + pair[0] + " meter")
            page.metricsHealthy = false
            root.check(root.find(page, "hub-meter-CPU").readout === "—", "unavailable is not idle zero")
            page.metricsHealthy = true
            page.metrics = {ramUsed: 16, ramTotal: 0, gpuUsage: null}
            root.check(root.find(page, "hub-meter-RAM").readout === "—", "invalid capacity is unknown")
            root.check(root.find(page, "hub-meter-GPU").readout === "—", "missing utilization is unknown")
            page.presentationActive = false
            root.check(!timer.presentationActive, "offscreen hub pauses timer presentation")
            root.check(!meters.presentationActive && !root.find(page, "hub-status-reader").polling,
                "offscreen hub pauses meters and API polling")
            console.info("AI_HUB_TEST_PASSED")
            Qt.quit()
        }
    }
}
