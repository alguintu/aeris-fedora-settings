import QtQuick
import QtQuick.Window
import Quickshell
import "pages" as Pages

ShellRoot {
    function check(value, message) {
        if (!value) {
            console.error("GRID_PREVIEW_TEST_FAILED: " + message)
            Qt.exit(1)
        }
    }
    Window {
        visible: true
        width: 1920; height: 480
        Pages.GridPreviewPage { id: page; x: 14; y: 14; width: 1892; height: 424 }
    }
    Timer {
        interval: 400; running: true
        onTriggered: {
            for (const size of [1892, 1572]) {
                page.width = size
                const grid = page.grid
                const full = grid.cellRect(0, 0, 18, 4)
                check(full.width === size && full.height === 424, "full span meets page edges")
                for (let row = 0; row < 4; ++row) {
                    for (let col = 0; col < 18; ++col) {
                        const cell = grid.cellRect(col, row, 1, 1)
                        check(Number.isInteger(cell.x) && Number.isInteger(cell.width), "rounded shared edges")
                        if (col < 17) check(grid.cellRect(col + 1, row, 1, 1).x - cell.x - cell.width === 12,
                            "horizontal gutters remain exact")
                        if (row < 3) check(grid.cellRect(col, row + 1, 1, 1).y - cell.y - cell.height === 12,
                            "vertical gutters remain exact")
                    }
                }
                const occupied = new Set()
                for (const tile of page.placements) {
                    const bounds = grid.cellRect(tile.column, tile.row, tile.columns, tile.rows)
                    check(bounds.x >= 0 && bounds.y >= 0 && bounds.x + bounds.width <= page.width
                        && bounds.y + bounds.height <= page.height, "sample stays in content area")
                    for (let row = tile.row; row < tile.row + tile.rows; ++row)
                        for (let col = tile.column; col < tile.column + tile.columns; ++col) {
                            const key = row * 18 + col
                            check(!occupied.has(key), "sample spans never overlap")
                            occupied.add(key)
                        }
                }
                check(occupied.size === 72, "new horizontal monitors fill the six remaining cells")
                for (let row = 2; row < 4; ++row)
                    for (let col = 10; col < 13; ++col)
                        check(occupied.has(row * 18 + col), "downloads and network occupy the area beside storage")
                page.showSpans = false
                page.showGrid = false
                page.showInsets = false
                check(grid.cellRect(0, 0, 18, 4).width === size, "inspector toggles do not change geometry")
                page.showSpans = true
                page.showGrid = true
                page.showInsets = true
            }
            console.info("GRID_PREVIEW_TEST_PASSED")
            Qt.quit()
        }
    }
}
