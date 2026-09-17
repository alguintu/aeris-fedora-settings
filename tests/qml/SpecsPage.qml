import QtQuick
import QtQuick.Window
import Quickshell
import "pages" as Pages

ShellRoot {
    function check(value, message) {
        if (!value) {
            console.error("SPECS_PAGE_TEST_FAILED: " + message)
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
    function checkText(item, tile) {
        if (!item.visible) return
        if (item.text !== undefined && item.text.length > 0) {
            const p = item.mapToItem(tile, 0, 0)
            check(!item.truncated, "no elided spec text: " + item.text)
            check(p.x >= 12 - 0.01 && p.y >= 12 - 0.01
                && p.x + item.width <= tile.width - 12 + 0.01
                && p.y + item.height <= tile.height - 12 + 0.01,
                "text stays inside tile inset: " + item.text)
            check(item.contentWidth <= item.width + 0.01, "text fits its allocated width: " + item.text)
        }
        for (const child of item.children || []) checkText(child, tile)
    }
    Window {
        visible: true
        width: 1920
        height: 480
        color: "#202631"
        Pages.SpecsPage { id: specs; x: 14; y: 14; width: 1892; height: 424 }
    }
    Timer {
        interval: 500; running: true
        onTriggered: {
            const grid = specs.layoutGrid
            const occupied = new Set()
            for (const placement of grid.placements) {
                const tile = find(specs, "specs-" + placement.key)
                check(!!tile, "tile exists: " + placement.key)
                const rect = grid.slot(placement.key)
                check(near(tile.x, rect.x) && near(tile.y, rect.y)
                    && near(tile.width, rect.width) && near(tile.height, rect.height),
                    "tile follows its grid span: " + placement.key)
                check(tile.contentMargin === 12, "universal content inset")
                checkText(tile, tile)
                for (let row = placement.row; row < placement.row + placement.rows; ++row)
                    for (let col = placement.column; col < placement.column + placement.columns; ++col) {
                        const key = row * 18 + col
                        check(!occupied.has(key), "no overlapping spans")
                        occupied.add(key)
                    }
            }
            check(occupied.size === 72, "all grid cells accounted for")
            check(near(grid.slot("chassis").x + grid.slot("chassis").width, 1892), "right page margin")
            check(near(grid.slot("argb").y + grid.slot("argb").height, 424), "bottom page margin")
            const output = Quickshell.env("AERIS_SPECS_TEST_IMAGE")
            const phase = Quickshell.env("AERIS_SPECS_PIXEL_PHASE")
            if (output && phase) {
                const backdrop = find(specs, "specs-case-backdrop")
                specs.presentationActive = false
                backdrop.elapsed = Number(phase) * 1000
            }
            if (output) specs.grabToImage(result => {
                if (!result.saveToFile(output)) {
                    console.error("SPECS_PAGE_TEST_FAILED: save preview")
                    Qt.exit(1)
                }
                console.info("SPECS_PAGE_TEST_PASSED")
                Qt.quit()
            })
            else {
                console.info("SPECS_PAGE_TEST_PASSED")
                Qt.quit()
            }
        }
    }
}
