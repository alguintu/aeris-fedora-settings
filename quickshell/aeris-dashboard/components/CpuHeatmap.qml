import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property var ccds: []
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

    RowLayout {
        anchors.fill: parent
        spacing: 10

        Repeater {
            model: 2

            Grid {
                required property int index
                property int ccdIndex: index
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 4
                rows: 2
                columnSpacing: 4
                rowSpacing: 4

                Repeater {
                    model: 8

                    Rectangle {
                        required property int index
                        property int ccdIndex: parent.ccdIndex
                        property int coreIndex: index
                        width: (parent.width - 12) / 4
                        height: (parent.height - 4) / 2
                        radius: 3
                        color: "#1d2c35"
                        clip: true

                        Row {
                            anchors.fill: parent
                            anchors.margins: 1
                            spacing: 1

                            Repeater {
                                model: 2

                                Rectangle {
                                    required property int index
                                    width: (parent.width - 1) / 2
                                    height: parent.height
                                    radius: 2
                                    color: root.heatColor(root.threadLoad(parent.parent.ccdIndex,
                                                                             parent.parent.coreIndex,
                                                                             index))

                                    Behavior on color { ColorAnimation { duration: 340 } }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
