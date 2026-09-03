import QtQuick

Item {
    id: root

    property real utilization: 0
    property real smoothedUtilization: 0
    property int activeCount: 0
    property int columns: 10
    property int rows: 8
    readonly property int unitCount: columns * rows
    property color idleColor: "#29424b"
    property color tealColor: "#59b9ad"
    property color orangeColor: "#f0a04b"
    property color redColor: "#ef5d65"

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
                if (units.get(ny * columns + nx).active)
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
            const cell = units.get(index)
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
            const cell = units.get(index)
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
        units.setProperty(index, "active", true)
        units.setProperty(index, "heat", Math.max(0.12, units.get(index).heat))
        activeCount += 1
    }

    function deactivateOne() {
        const index = chooseFringeActive()
        if (index < 0)
            return
        units.setProperty(index, "active", false)
        activeCount -= 1
    }

    ListModel { id: units }

    Component.onCompleted: {
        for (let index = 0; index < unitCount; ++index)
            units.append({"heat": 0.0, "active": false})
    }

    Timer {
        interval: 100
        repeat: true
        running: true

        onTriggered: {
            const requested = Math.max(0, Math.min(100, root.utilization || 0))
            root.smoothedUtilization += (requested - root.smoothedUtilization) * 0.14
            const target = Math.round(root.smoothedUtilization * root.unitCount / 100)

            if (target > root.activeCount + 1) {
                root.activateOne()
                if (target > root.activeCount + 5)
                    root.activateOne()
            } else if (target < root.activeCount - 1) {
                root.deactivateOne()
                if (target < root.activeCount - 5)
                    root.deactivateOne()
            }

            for (let index = 0; index < root.unitCount; ++index) {
                const cell = units.get(index)
                const nextHeat = cell.active
                        ? Math.min(1, cell.heat + 0.016)
                        : Math.max(0, cell.heat - 0.009)
                if (nextHeat !== cell.heat)
                    units.setProperty(index, "heat", nextHeat)
            }
        }
    }

    Grid {
        anchors.fill: parent
        columns: root.columns
        rows: root.rows
        columnSpacing: 4
        rowSpacing: 3

        Repeater {
            model: units

            Rectangle {
                required property real heat
                width: (parent.width - (root.columns - 1) * parent.columnSpacing) / root.columns
                height: (parent.height - (root.rows - 1) * parent.rowSpacing) / root.rows
                radius: 2
                color: root.heatColor(heat)
                border.color: "#3d5260"
                border.width: 1

                Behavior on color { ColorAnimation { duration: 220 } }
            }
        }
    }
}
