import QtQuick
import QtQuick.Layouts

DashboardTile {
    id: root
    property var metrics: ({})
    property bool healthy: false
    property bool presentationActive: true
    contentMargin: Theme.gridContentInset
    title: "RESOURCES"
    accent: Theme.cyan
    function percent(used, total) {
        return typeof used === "number" && typeof total === "number" && total > 0 ? used / total * 100 : null
    }
    function valid(value) { return root.healthy && typeof value === "number" && isFinite(value) }
    RowLayout {
        anchors.fill: parent
        spacing: Theme.tileGap
        Repeater {
            // Keep delegates alive between sensor snapshots; only values change.
            model: ["CPU", "GPU", "RAM", "VRAM"]
            delegate: Item {
                id: meter
                required property var modelData
                required property int index
                readonly property var value: [root.metrics.cpuUsage, root.metrics.gpuUsage,
                    root.percent(root.metrics.ramUsed, root.metrics.ramTotal),
                    root.percent(root.metrics.vramUsed, root.metrics.vramTotal)][index]
                readonly property color tint: [Theme.orange, Theme.green, Theme.teal, Theme.mauve][index]
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 1
                objectName: "hub-meter-" + modelData
                readonly property string readout: root.valid(value) ? Math.round(value) + "%" : "—"
                Text {
                    anchors.left: parent.left; anchors.top: parent.top
                    text: meter.modelData; color: meter.tint
                    font.family: Theme.fontFamily; font.pixelSize: Theme.sectionTitleSize
                }
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: meter.readout; color: Theme.text
                    font.family: Theme.fontFamily; font.pixelSize: 36
                }
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 8; radius: 4; color: Theme.raised
                    Rectangle {
                        height: parent.height; radius: parent.radius; color: meter.tint
                        width: parent.width * (root.valid(meter.value) ? Math.max(0, Math.min(100, meter.value)) / 100 : 0)
                        Behavior on width { enabled: root.presentationActive; NumberAnimation { duration: 250 } }
                    }
                }
            }
        }
    }
}
