import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property var ccds: []
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
        const load = Math.max(0, Math.min(100, value || 0)) / 100
        if (load < 0.3)
            return mix(idleColor, tealColor, load / 0.3)
        if (load < 0.72)
            return mix(tealColor, orangeColor, (load - 0.3) / 0.42)
        return mix(orangeColor, redColor, (load - 0.72) / 0.28)
    }

    function threadLoad(ccdIndex, coreIndex, threadIndex) {
        if (!ccds || ccdIndex >= ccds.length)
            return 0
        const cores = ccds[ccdIndex]
        if (!cores || coreIndex >= cores.length)
            return 0
        const threads = cores[coreIndex]
        return threads && threadIndex < threads.length ? threads[threadIndex] : 0
    }

    Row {
        anchors.fill: parent
        spacing: 10

        Repeater {
            model: 2

            Grid {
                required property int index
                property int ccdIndex: index
                width: (root.width - 10) / 2
                height: root.height
                columns: 2
                spacing: 3

                Repeater {
                    model: 8

                    Rectangle {
                        required property int index
                        property int ccdIndex: parent.ccdIndex
                        property int coreIndex: index
                        width: (parent.width - 3) / 2
                        height: (parent.height - 9) / 4
                        radius: 3
                        color: Theme.surface
                        clip: true

                        Row {
                            anchors.fill: parent
                            anchors.margins: 1
                            spacing: 0

                            Repeater {
                                model: 2

                                Shape {
                                    id: threadCell
                                    required property int index
                                    width: parent.width / 2
                                    height: parent.height
                                    antialiasing: true
                                    readonly property int coreIndex: parent.parent.coreIndex
                                    readonly property int dieIndex: parent.parent.ccdIndex
                                    readonly property real chamfer: Math.min(8, width * 0.4, height * 0.4)
                                    readonly property real topLeft: dieIndex === 0 && coreIndex === 0 && index === 0 ? chamfer : 0
                                    readonly property real topRight: dieIndex === 1 && coreIndex === 1 && index === 1 ? chamfer : 0
                                    readonly property real bottomLeft: dieIndex === 0 && coreIndex === 6 && index === 0 ? chamfer : 0
                                    readonly property real bottomRight: dieIndex === 1 && coreIndex === 7 && index === 1 ? chamfer : 0
                                    property color heat: root.heatColor(root.threadLoad(parent.parent.ccdIndex,
                                                                             parent.parent.coreIndex,
                                                                             index))

                                    Behavior on heat { ColorAnimation { duration: 340 } }

                                    ShapePath {
                                        strokeWidth: -1
                                        fillColor: threadCell.heat
                                        startX: threadCell.topLeft
                                        startY: 0
                                        PathLine { x: threadCell.width - threadCell.topRight; y: 0 }
                                        PathLine { x: threadCell.width; y: threadCell.topRight }
                                        PathLine { x: threadCell.width; y: threadCell.height - threadCell.bottomRight }
                                        PathLine { x: threadCell.width - threadCell.bottomRight; y: threadCell.height }
                                        PathLine { x: threadCell.bottomLeft; y: threadCell.height }
                                        PathLine { x: 0; y: threadCell.height - threadCell.bottomLeft }
                                        PathLine { x: 0; y: threadCell.topLeft }
                                        PathLine { x: threadCell.topLeft; y: 0 }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
