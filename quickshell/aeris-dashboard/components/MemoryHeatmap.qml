import QtQuick

Item {
    id: root

    property real ramUtilization: 0
    property real vramUtilization: 0
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
            if (ramUnits.get(index).active === active)
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
        ramUnits.setProperty(index, "active", true)
        ramUnits.setProperty(index, "heat", Math.max(0.16, ramUnits.get(index).heat))
        ramActiveCount += 1
    }

    function deactivateRam() {
        const index = randomCell(true)
        if (index < 0)
            return
        ramUnits.setProperty(index, "active", false)
        ramActiveCount -= 1
    }

    ListModel { id: ramUnits }

    Component.onCompleted: {
        for (let index = 0; index < unitCount; ++index)
            ramUnits.append({"active": false, "heat": 0.0})
    }

    Timer {
        interval: 100
        repeat: true
        running: true

        onTriggered: {
            const requestedRam = Math.max(0, Math.min(100, root.ramUtilization || 0))
            const requestedVram = Math.max(0, Math.min(100, root.vramUtilization || 0))
            root.smoothedRam += (requestedRam - root.smoothedRam) * 0.18
            root.smoothedVram += (requestedVram - root.smoothedVram) * 0.18

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

            for (let index = 0; index < root.unitCount; ++index) {
                const cell = ramUnits.get(index)
                const nextHeat = cell.active
                        ? Math.min(1, cell.heat + 0.07)
                        : Math.max(0, cell.heat - 0.08)
                if (nextHeat !== cell.heat)
                    ramUnits.setProperty(index, "heat", nextHeat)
            }
        }
    }

    Row {
        anchors.fill: parent
        spacing: root.field === "both" ? 21 : 0

        Item {
            visible: root.field !== "vram"
            width: root.field === "both" ? (root.width - 21) / 2 : root.width
            height: root.height

            Grid {
                id: ramGrid
                readonly property real cellSize: root.fittedCellSize(parent.width, parent.height)

                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: root.columns * cellSize + (root.columns - 1) * columnSpacing
                height: root.rows * cellSize + (root.rows - 1) * rowSpacing
                columns: root.columns
                rows: root.rows
                columnSpacing: root.fittedGap(parent.width, parent.height)
                rowSpacing: columnSpacing

                Repeater {
                    model: ramUnits

                    Rectangle {
                        required property bool active
                        required property real heat
                        width: ramGrid.cellSize
                        height: ramGrid.cellSize
                        radius: 2
                        color: root.mix(root.idleColor,
                                        root.pressureColor(root.ramColor, root.smoothedRam),
                                        heat)
                        border.color: Theme.border
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 220 } }
                    }
                }
            }
        }

        Item {
            visible: root.field !== "ram"
            width: root.field === "both" ? (root.width - 21) / 2 : root.width
            height: root.height

            Grid {
                id: vramGrid
                readonly property real cellSize: root.fittedCellSize(parent.width, parent.height)
                readonly property int filledUnits: Math.round(root.smoothedVram * root.unitCount / 100)

                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: root.columns * cellSize + (root.columns - 1) * columnSpacing
                height: root.rows * cellSize + (root.rows - 1) * rowSpacing
                columns: root.columns
                rows: root.rows
                columnSpacing: root.fittedGap(parent.width, parent.height)
                rowSpacing: columnSpacing

                Repeater {
                    model: root.unitCount

                    Rectangle {
                        required property int index
                        width: vramGrid.cellSize
                        height: vramGrid.cellSize
                        radius: 2
                        color: index < vramGrid.filledUnits
                                ? root.pressureColor(root.vramColor, root.smoothedVram)
                                : root.idleColor
                        border.color: Theme.border
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 220 } }
                    }
                }
            }
        }
    }
}
