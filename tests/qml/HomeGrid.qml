import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "pages" as Pages
import "components" as Components

ShellRoot {
    id: root
    property int step: 0
    property var lightingRequests: []
    function check(value, message) {
        if (!value) {
            console.error("HOME_GRID_TEST_FAILED: " + message)
            Qt.exit(1)
        }
    }
    function near(a, b) { return Math.abs(a - b) < 0.01 }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = find(child, name)
            if (found) return found
        }
        return null
    }
    function surface(item) {
        if (!item.visible) return null
        if (item.gapX !== undefined && item.cellColors !== undefined) return item
        for (const child of item.children || []) {
            const found = surface(child)
            if (found) return found
        }
        return null
    }
    function point(item) { return item.mapToItem(page, 0, 0) }
    Window {
        visible: true
        width: 1920; height: 480
        Pages.IdlePage {
            id: page
            x: 14; y: 14; width: 1892; height: 424
            now: new Date(2026, 8, 9, 23, 59) // Longest weekday, two-digit time.
            animationsActive: false
            metricsHealthy: true
            onLightingModeRequested: mode => root.lightingRequests = root.lightingRequests.concat([mode])
            metrics: ({cpuUsage: 0, cpuTemp: null, cpuClock: 0, cpuCcds: [],
                gpuUsage: 0, gpuTemp: null, ramUsed: 0, ramTotal: 64 * 1073741824,
                vramUsed: 0, vramTotal: 16 * 1073741824,
                drives: [{temperature: 30}, {temperature: 45.85}, {temperature: null}, {}]})
        }
    }
    TestCase { id: input; name: "OfflineLighting"; when: false }
    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: {
            const grid = page.layoutGrid
            for (const spec of grid.placements) {
                if (spec.key === "controls") continue
                const tile = find(page, "home-" + spec.key)
                check(!!tile, "tile exists: " + spec.key)
                const expected = grid.slot(spec.key)
                check(near(tile.x, expected.x) && near(tile.y, expected.y)
                    && near(tile.width, expected.width) && near(tile.height, expected.height),
                    "real tile uses shared span: " + spec.key)
                check(tile.contentMargin === 12, "one universal inset: " + spec.key)
            }
            const lights = find(page, "home-lights"), fans = find(page, "home-fans")
            const rack = grid.slot("controls")
            check(near(lights.x, rack.x) && near(fans.x + fans.width, rack.x + rack.width)
                && near(lights.width, fans.width) && near(fans.x - lights.x - lights.width, 12)
                && lights.y === rack.y && lights.height === rack.height
                && fans.y === rack.y && fans.height === rack.height, "equal nested control groups")

            for (const pair of [["cpu", "ram"], ["gpu", "vram"]]) {
                const header = find(page, "home-" + pair[0] + "-header")
                const memoryHeader = find(page, "home-" + pair[1] + "-header")
                const field = find(page, "home-" + pair[0] + "-field")
                const memory = find(page, "home-" + pair[1] + "-field")
                const cells = surface(memory)
                check(!!cells, "real memory surface exists")
                check(header.height === 30 && memoryHeader.height === 30, "equal header slots")
                check(near(point(field).y, point(cells).y)
                    && near(point(field).y + field.height, point(cells).y + cells.height),
                    "hardware and memory field tops/bottoms align")
                check(near(point(memoryHeader).x, point(cells).x)
                    && near(point(memoryHeader).x + memoryHeader.width, point(cells).x + cells.width),
                    "memory headers align to both grid edges")
                const cellWidth = (cells.width - (cells.columns - 1) * cells.gapX) / cells.columns
                const cellHeight = (cells.height - (cells.rows - 1) * cells.gapY) / cells.rows
                check(near(cellWidth, cellHeight) && near(cellWidth, Math.round(cellWidth)),
                    "all memory cells stay square with integer side length")
            }
            const media = find(page, "home-media"), body = find(page, "home-media-body")
            const art = find(page, "media-art")
            check(near(point(body).x - media.x, 12) && near(point(body).y - media.y, 12)
                && near(media.width - body.width, 24) && near(media.height - body.height, 24),
                "media has exactly one 12px inset")
            check(near(art.width, art.height) && near(art.height, body.height), "cover fills content height")
            const timer = find(page, "home-pomodoro"), timerBody = find(page, "home-timer-body")
            const storage = find(page, "home-storage"), downloads = find(page, "home-downloads")
            const network = find(page, "home-network")
            for (let i = 0; i < 4; ++i) {
                const label = find(page, "storage-label-" + i)
                const temperature = find(page, "storage-temperature-" + i)
                check(temperature.text === (root.step === 0 ? ["30°C", "46°C", "—", "—"][i] : "—"),
                    "drive temperature rounded; missing or unhealthy never appears as zero")
                check(near(point(label).y + label.baselineOffset, point(temperature).y + temperature.baselineOffset)
                    && near(temperature.x + temperature.width, temperature.parent.width)
                    && near(temperature.x - label.x - label.width, 6),
                    "drive label and temperature share baseline and opposite edges with 6px gap")
                check(label.font.pixelSize === 18 && temperature.font.pixelSize === 18
                    && label.implicitWidth <= label.width, "drive labels stay legible and untruncated")
            }
            check(downloads.x === storage.x + storage.width + 12 && network.x === downloads.x
                && downloads.width === network.width && downloads.height === 97 && network.height === 97
                && network.y === downloads.y + downloads.height + 12
                && network.y + network.height === storage.y + storage.height,
                "two matching horizontal monitors fit next to storage")
            check(!find(page, "home-network-body").animationRegistered,
                "network animation respects Home's inactive presentation gate")
            const weather = find(page, "home-weather")
            check(weather.width === timer.width && near(timer.x - weather.x - weather.width, 12)
                && near(timer.x + timer.width, grid.slot("cpu").x - 12),
                "weather and timer share four columns each without moving CPU")
            check(timerBody.timerService === Components.TomatService, "Home reuses the shared Tomat singleton")
            const routines = find(page, "home-timer-routines")
            check(routines.x === timer.x && routines.width === timer.width && routines.height === timer.height
                && routines.contentInset === 12, "compact routine chooser stays inside the small tile")
            check(timer.height === 206 && near(point(timerBody).x - timer.x, 12)
                && near(point(timerBody).y - timer.y, 12) && near(timerBody.height, timer.height - 24),
                "compact timer occupies upper half with one 12px inset")
            if (root.step++ === 0) {
                const aeris = find(page, "home-light-aeris")
                const night = find(page, "home-light-night")
                const party = find(page, "home-light-party")
                check(aeris.allowOffline && !aeris.available && !night.allowOffline && !party.allowOffline,
                    "only Aeris can be tapped while offline")
                input.mouseClick(night, 40, 40, Qt.LeftButton)
                input.mouseClick(party, 40, 40, Qt.LeftButton)
                check(root.lightingRequests.length === 0, "offline mode buttons remain disabled")
                input.mouseClick(aeris, 40, 40, Qt.LeftButton)
                check(root.lightingRequests.length === 1 && root.lightingRequests[0] === "work",
                    "offline Aeris requests guarded Work startup")
                page.lightingPending = true
                input.mouseClick(aeris, 40, 40, Qt.LeftButton)
                check(root.lightingRequests.length === 1, "pending blocks duplicate taps")
                page.lightingPending = false
                page.lightingHealthy = true
                page.lightingMode = "night"
                input.mouseClick(aeris, 40, 40, Qt.LeftButton)
                check(root.lightingRequests.length === 2 && !aeris.allowOffline,
                    "online Aeris remains normal Work selection")
                page.lightingHealthy = false
                page.lightingCanStart = false
                input.mouseClick(aeris, 40, 40, Qt.LeftButton)
                check(root.lightingRequests.length === 2, "Python rollback never invokes missing startup API")
                page.metrics = Object.assign({}, page.metrics, {cpuUsage: 100, cpuTemp: 100, cpuClock: 4.9,
                    gpuUsage: 100, gpuTemp: 100, ramUsed: page.metrics.ramTotal, vramUsed: page.metrics.vramTotal})
                page.metricsHealthy = false
            } else {
                console.info("HOME_GRID_TEST_PASSED")
                Qt.quit()
            }
        }
    }
}
