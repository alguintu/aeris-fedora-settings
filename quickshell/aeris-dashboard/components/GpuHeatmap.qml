import QtQuick

Item {
    id: root

    property real utilization: 0
    property bool animationEnabled: true
    property bool profilingNoBlend: false
    property bool profilingNoPaint: false
    onProfilingNoPaintChanged: if (!profilingNoPaint) updateColors()
    property real smoothedUtilization: 0
    property real lowLoadResidence: 0
    property int activeCount: 0
    property int columns: 10
    property int rows: 8
    readonly property int unitCount: columns * rows
    readonly property real saturationThreshold: 98
    property color idleColor: Theme.heatIdle
    property color tealColor: Theme.teal
    property color orangeColor: Theme.orange
    property color redColor: Theme.red

    function mix(first, second, amount) {
        const t = Math.max(0, Math.min(1, amount))
        return Qt.rgba(first.r + (second.r - first.r) * t,
                       first.g + (second.g - first.g) * t,
                       first.b + (second.b - first.b) * t,
                       first.a + (second.a - first.a) * t)
    }

    function heatColor(value) {
        const heat = Math.max(0, Math.min(1, value))
        if (heat < 0.28)
            return mix(idleColor, tealColor, heat / 0.28)
        if (heat < 0.7)
            return mix(tealColor, orangeColor, (heat - 0.28) / 0.42)
        return mix(orangeColor, redColor, (heat - 0.7) / 0.3)
    }

    function neighborScore(cellIndex) {
        const x = cellIndex % columns
        const y = Math.floor(cellIndex / columns)
        let score = 0
        for (let dy = -1; dy <= 1; ++dy) {
            for (let dx = -1; dx <= 1; ++dx) {
                if (dx === 0 && dy === 0)
                    continue
                const nx = x + dx
                const ny = y + dy
                if (nx < 0 || nx >= columns || ny < 0 || ny >= rows)
                    continue
                if (units[ny * columns + nx].active)
                    score += (dx === 0 || dy === 0) ? 5 : 2
            }
        }
        return score
    }

    function chooseWeightedInactive() {
        if (activeCount === 0)
            return Math.floor(Math.random() * unitCount)

        const candidates = []
        let totalWeight = 0
        for (let index = 0; index < unitCount; ++index) {
            const cell = units[index]
            if (cell.active)
                continue
            const weight = 0.35 + neighborScore(index) * 4 + cell.heat * 2
            candidates.push({"index": index, "weight": weight})
            totalWeight += weight
        }

        let draw = Math.random() * totalWeight
        for (const candidate of candidates) {
            draw -= candidate.weight
            if (draw <= 0)
                return candidate.index
        }
        return candidates.length ? candidates[candidates.length - 1].index : -1
    }

    function chooseFringeActive() {
        let chosen = -1
        let lowestScore = 999
        let lowestHeat = 999
        for (let index = 0; index < unitCount; ++index) {
            const cell = units[index]
            if (!cell.active)
                continue
            const score = neighborScore(index)
            if (score < lowestScore || (score === lowestScore && cell.heat < lowestHeat)) {
                chosen = index
                lowestScore = score
                lowestHeat = cell.heat
            }
        }
        return chosen
    }

    function activateOne() {
        const index = chooseWeightedInactive()
        if (index < 0)
            return
        units[index].active = true
        units[index].heat = Math.max(0.12, units[index].heat)
        activeCount += 1
    }

    function deactivateOne() {
        const index = chooseFringeActive()
        if (index < 0)
            return
        units[index].active = false
        activeCount -= 1
    }

    function rotateLowLoadActivity() {
        const previous = chooseFringeActive()
        if (previous < 0)
            return
        units[previous].active = false
        activeCount -= 1
        activateOne()
    }

    // The renderer receives one color frame, so these cells no longer need
    // observable QML model roles or per-cell change notifications.
    property var units: []

    Component.onCompleted: {
        for (let index = 0; index < unitCount; ++index)
            units.push({"heat": 0.0, "active": false})
        updateColors()
    }

    function updateColors() {
        if (!units || units.length !== unitCount) return
        const colors = []
        for (let i = 0; i < units.length; ++i) colors.push(root.heatColor(units[i].heat))
        if (!root.profilingNoPaint) surface.cellColors = colors
    }
    onIdleColorChanged: updateColors()
    onTealColorChanged: updateColors()
    onOrangeColorChanged: updateColors()
    onRedColorChanged: updateColors()

    Timer {
        interval: 100
        repeat: true
        running: root.animationEnabled && root.visible

        onTriggered: {
            const requested = Math.max(0, Math.min(100, root.utilization || 0))
            root.smoothedUtilization = Math.abs(requested - root.smoothedUtilization) < 0.01
                ? requested : root.smoothedUtilization + (requested - root.smoothedUtilization) * 0.14
            const saturated = requested >= root.saturationThreshold
            const target = saturated
                    ? root.unitCount
                    : Math.round(root.smoothedUtilization * root.unitCount / 100)

            const lowLoadTarget = target <= 2
            if (target > root.activeCount + 1
                    || ((lowLoadTarget || saturated) && target > root.activeCount)) {
                root.activateOne()
                if (target > root.activeCount + 5)
                    root.activateOne()
            } else if (target < root.activeCount - 1
                       || (lowLoadTarget && target < root.activeCount)) {
                root.deactivateOne()
                if (target < root.activeCount - 5)
                    root.deactivateOne()
            }

            if (target > 0 && target <= 2 && root.activeCount > 0 && requested < 4) {
                root.lowLoadResidence += interval / 1000
                if (root.lowLoadResidence >= 2.5 && Math.random() < 0.08) {
                    root.rotateLowLoadActivity()
                    root.lowLoadResidence = 0
                }
            } else {
                root.lowLoadResidence = 0
            }

            let heatChanged = false
            for (let index = 0; index < root.unitCount; ++index) {
                const cell = root.units[index]
                const nextHeat = cell.active
                        ? Math.min(1, cell.heat + 0.014)
                        : Math.max(0, cell.heat - 0.024)
                if (nextHeat !== cell.heat) {
                    cell.heat = nextHeat
                    heatChanged = true
                }
            }
            if (heatChanged) root.updateColors()
        }
    }

    HeatmapSurface {
        id: surface
        anchors.fill: parent
        animationEnabled: root.animationEnabled && !root.profilingNoBlend && !root.profilingNoPaint
        columns: root.columns
        rows: root.rows
        gapX: 4
        gapY: 3
    }
}
