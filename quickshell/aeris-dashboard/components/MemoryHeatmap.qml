import QtQuick

Item {
    id: root

    property real ramUtilization: 0
    property real vramUtilization: 0
    property bool animationEnabled: true
    property bool settled: false
    onRamUtilizationChanged: settled = false
    onVramUtilizationChanged: settled = false
    onFieldChanged: settled = false
    property string field: "both"
    property real smoothedRam: 0
    property real smoothedVram: 0
    property int ramActiveCount: 0
    property int columns: 14
    property int rows: 10
    property real cellGap: 3
    readonly property int unitCount: columns * rows
    property color idleColor: Theme.heatIdle
    property color ramColor: Theme.cyan
    property color vramColor: Theme.mauve
    property color orangeColor: Theme.orange
    property color redColor: Theme.red
    // Most utilization changes do not change the pressure color. Resolve it once,
    // not separately for every memory square on every smoothing tick.
    readonly property color currentRamColor: pressureColor(ramColor, smoothedRam)
    readonly property color currentVramColor: pressureColor(vramColor, smoothedVram)
    property var ramColors: []
    property var vramColors: []
    readonly property int filledVramUnits: Math.round(smoothedVram * unitCount / 100)
    onCurrentRamColorChanged: updateColors()
    onCurrentVramColorChanged: updateColors()
    onFilledVramUnitsChanged: updateColors()
    onIdleColorChanged: updateColors()

    function updateColors() {
        if (!ramUnits || ramUnits.length !== root.unitCount) return
        if (root.field !== "vram") {
            const colors = []
            for (let i = 0; i < root.unitCount; ++i)
                colors.push(root.mix(root.idleColor, root.currentRamColor, ramUnits[i].heat))
            root.ramColors = colors
        }
        if (root.field !== "ram") {
            const colors = []
            for (let i = 0; i < root.unitCount; ++i)
                colors.push(i < root.filledVramUnits ? root.currentVramColor : root.idleColor)
            root.vramColors = colors
        }
    }

    // Fit the entire grid, including gaps, without stretching or clipping cells.
    function fittedGap(availableWidth, availableHeight) {
        return Math.max(0, Math.min(cellGap,
            availableWidth / Math.max(1, columns - 1),
            availableHeight / Math.max(1, rows - 1)))
    }

    function fittedCellSize(availableWidth, availableHeight) {
        const gap = fittedGap(availableWidth, availableHeight)
        return Math.max(0, Math.min(
            (availableWidth - (columns - 1) * gap) / columns,
            (availableHeight - (rows - 1) * gap) / rows))
    }

    function mix(first, second, amount) {
        const t = Math.max(0, Math.min(1, amount))
        return Qt.rgba(first.r + (second.r - first.r) * t,
                       first.g + (second.g - first.g) * t,
                       first.b + (second.b - first.b) * t,
                       first.a + (second.a - first.a) * t)
    }

    function pressureColor(base, utilization) {
        const pressure = Math.max(0, Math.min(100, utilization)) / 100
        if (pressure < 0.78)
            return base
        if (pressure < 0.92)
            return mix(base, orangeColor, (pressure - 0.78) / 0.14)
        return mix(orangeColor, redColor, (pressure - 0.92) / 0.08)
    }

    function randomCell(active) {
        const candidates = []
        for (let index = 0; index < unitCount; ++index) {
            if (ramUnits[index].active === active)
                candidates.push(index)
        }
        return candidates.length
                ? candidates[Math.floor(Math.random() * candidates.length)]
                : -1
    }

    function activateRam() {
        const index = randomCell(false)
        if (index < 0)
            return
        ramUnits[index].active = true
        ramUnits[index].heat = Math.max(0.16, ramUnits[index].heat)
        ramActiveCount += 1
    }

    function deactivateRam() {
        const index = randomCell(true)
        if (index < 0)
            return
        ramUnits[index].active = false
        ramActiveCount -= 1
    }

    property var ramUnits: []

    Component.onCompleted: {
        for (let index = 0; index < unitCount; ++index)
            ramUnits.push({"active": false, "heat": 0.0})
        updateColors()
    }

    Timer {
        interval: 100
        repeat: true
        running: root.animationEnabled && root.visible && !root.settled

        onTriggered: {
            const requestedRam = Math.max(0, Math.min(100, root.ramUtilization || 0))
            const requestedVram = Math.max(0, Math.min(100, root.vramUtilization || 0))
            if (root.field !== "vram")
                root.smoothedRam = Math.abs(requestedRam - root.smoothedRam) < 0.01
                    ? requestedRam : root.smoothedRam + (requestedRam - root.smoothedRam) * 0.18
            if (root.field !== "ram")
                root.smoothedVram = Math.abs(requestedVram - root.smoothedVram) < 0.01
                    ? requestedVram : root.smoothedVram + (requestedVram - root.smoothedVram) * 0.18
            if (root.field === "vram") {
                root.settled = root.smoothedVram === requestedVram
                return
            }

            const ramTarget = Math.round(root.smoothedRam * root.unitCount / 100)
            const difference = ramTarget - root.ramActiveCount
            const changes = Math.min(6, Math.max(1, Math.ceil(Math.abs(difference) / 10)))
            if (difference > 1) {
                for (let index = 0; index < changes; ++index)
                    root.activateRam()
            } else if (difference < -1) {
                for (let index = 0; index < changes; ++index)
                    root.deactivateRam()
            }

            let heatChanging = false
            for (let index = 0; index < root.unitCount; ++index) {
                const cell = root.ramUnits[index]
                const nextHeat = cell.active
                        ? Math.min(1, cell.heat + 0.07)
                        : Math.max(0, cell.heat - 0.08)
                if (nextHeat !== cell.heat) {
                    cell.heat = nextHeat
                    heatChanging = true
                }
            }
            root.settled = !heatChanging && Math.abs(ramTarget - root.ramActiveCount) <= 1
                && root.smoothedRam === requestedRam
                && (root.field === "ram" || root.smoothedVram === requestedVram)
            if (heatChanging) root.updateColors()
        }
    }

    Row {
        anchors.fill: parent
        spacing: root.field === "both" ? 21 : 0

        Item {
            visible: root.field !== "vram"
            width: root.field === "both" ? (root.width - 21) / 2 : root.width
            height: root.height

            HeatmapSurface {
                id: ramGrid
                readonly property real cellSize: root.fittedCellSize(parent.width, parent.height)
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: root.columns * cellSize + (root.columns - 1) * gapX
                height: root.rows * cellSize + (root.rows - 1) * gapY
                columns: root.columns
                rows: root.rows
                gapX: root.fittedGap(parent.width, parent.height)
                gapY: gapX
                animationEnabled: root.animationEnabled
                cellColors: root.ramColors
            }
        }

        Item {
            visible: root.field !== "ram"
            width: root.field === "both" ? (root.width - 21) / 2 : root.width
            height: root.height

            HeatmapSurface {
                id: vramGrid
                readonly property real cellSize: root.fittedCellSize(parent.width, parent.height)
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: root.columns * cellSize + (root.columns - 1) * gapX
                height: root.rows * cellSize + (root.rows - 1) * gapY
                columns: root.columns
                rows: root.rows
                gapX: root.fittedGap(parent.width, parent.height)
                gapY: gapX
                animationEnabled: root.animationEnabled
                cellColors: root.vramColors
            }
        }
    }
}
