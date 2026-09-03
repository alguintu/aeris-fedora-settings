import Quickshell
import QtQuick
import QtQuick.Layouts
import "../components"

Item {
    id: page

    property var metrics: ({})
    property bool metricsHealthy: false
    property date now

    function percent(value, total) {
        return total > 0 ? Math.max(0, Math.min(1, value / total)) : 0
    }

    function temperature(value) {
        return value === null || value === undefined ? "--°" : Math.round(value) + "°C"
    }

    function bytes(value) {
        if (value === null || value === undefined) return "--"
        const units = ["B", "KB", "MB", "GB", "TB"]
        let number = value
        let unit = 0
        while (number >= 1024 && unit < units.length - 1) {
            number /= 1024
            unit += 1
        }
        return (number >= 100 || unit === 0 ? number.toFixed(0) : number.toFixed(1)) + " " + units[unit]
    }

    function nominalCapacity(value) {
        if (!value || value <= 0)
            return "--"
        const gibibytes = value / (1024 * 1024 * 1024)
        return Math.pow(2, Math.round(Math.log(gibibytes) / Math.LN2)) + "GB"
    }

    function hourText() {
        const hour = page.now.getHours() % 12 || 12
        return hour + ":" + String(page.now.getMinutes()).padStart(2, "0")
    }

    RowLayout {
        id: topRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 176
        spacing: 12

        DashboardTile {
            Layout.preferredWidth: 330
            Layout.fillHeight: true
            accent: "#d77ec3"

            Column {
                anchors.fill: parent
                spacing: 0

                Row {
                    spacing: 10
                    Text { text: page.hourText(); color: "#f7f8fa"; font.family: "Noto Sans"; font.pixelSize: 62; font.weight: Font.Light }
                    Text { anchors.baseline: parent.children[0].baseline; text: page.now.getHours() >= 12 ? "PM" : "AM"; color: "#8ed170"; font.family: "Noto Sans"; font.pixelSize: 20; font.weight: Font.Medium }
                }

                Text { text: Qt.formatDateTime(page.now, "dddd  •  MMMM d"); color: "#b8aaf6"; font.family: "Noto Sans"; font.pixelSize: 17 }
            }
        }

        DashboardTile {
            Layout.preferredWidth: 460
            Layout.fillHeight: true
            title: "CPU"
            eyebrow: Math.round(page.metrics.cpuUsage) + "%  ·  " + page.temperature(page.metrics.cpuTemp)
            accent: "#77d7cb"

            CpuHeatmap {
                anchors.fill: parent
                ccds: page.metrics.cpuCcds || []
            }
        }

        DashboardTile {
            Layout.preferredWidth: 460
            Layout.fillHeight: true
            title: "GPU"
            eyebrow: Math.round(page.metrics.gpuUsage) + "%  ·  " + page.temperature(page.metrics.gpuTemp)
            accent: "#77d7cb"

            GpuHeatmap {
                anchors.fill: parent
                utilization: page.metrics.gpuUsage || 0
            }
        }

        DashboardTile {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 10

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 18
                    Layout.bottomMargin: 5

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Rectangle { width: 5; height: 18; radius: 3; color: "#57bced" }
                        DashboardHeaderLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.nominalCapacity(page.metrics.ramTotal) + " RAM "
                                  + Math.round(page.percent(page.metrics.ramUsed, page.metrics.ramTotal) * 100) + "%"
                            color: "#57bced"
                        }
                    }

                    Row {
                        x: (parent.width + 21) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Rectangle { width: 5; height: 18; radius: 3; color: "#a99bf5" }
                        DashboardHeaderLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.nominalCapacity(page.metrics.vramTotal) + " VRAM "
                                  + Math.round(page.percent(page.metrics.vramUsed, page.metrics.vramTotal) * 100) + "%"
                            color: "#a99bf5"
                        }
                    }
                }

                MemoryHeatmap {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ramUtilization: page.percent(page.metrics.ramUsed, page.metrics.ramTotal) * 100
                    vramUtilization: page.percent(page.metrics.vramUsed, page.metrics.vramTotal) * 100
                }
            }
        }
    }

    RowLayout {
        anchors.top: topRow.bottom
        anchors.topMargin: 12
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 12

        DashboardTile {
            Layout.preferredWidth: 540
            Layout.fillHeight: true
            title: "LAUNCH"
            eyebrow: "QUICK ACCESS"
            accent: "#8ed170"

            RowLayout {
                anchors.centerIn: parent
                spacing: 12
                ActionButton { symbol: ">_"; label: "Terminal"; accent: "#d5dbe3"; onClicked: Quickshell.execDetached(["konsole"]) }
                ActionButton { symbol: "◎"; label: "Firefox"; accent: "#f0aa58"; onClicked: Quickshell.execDetached(["firefox"]) }
                ActionButton { symbol: "<>"; label: "Code"; accent: "#57bced"; onClicked: Quickshell.execDetached(["code"]) }
                ActionButton { symbol: "▣"; label: "Files"; accent: "#77d7cb"; onClicked: Quickshell.execDetached(["dolphin"]) }
            }
        }

        DashboardTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "AT A GLANCE"
            eyebrow: "CALM STATE"
            accent: "#77d7cb"

            RowLayout {
                anchors.fill: parent
                spacing: 26

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    Text { text: "ROOT STORAGE"; color: "#8995a5"; font.family: "Noto Sans"; font.pixelSize: 11; font.letterSpacing: 1 }
                    Text { text: page.bytes(page.metrics.rootUsed) + " / " + page.bytes(page.metrics.rootTotal); color: "#eef3f8"; font.family: "Noto Sans"; font.pixelSize: 20 }
                    MetricBar { Layout.fillWidth: true; label: "NVMe"; progress: page.percent(page.metrics.rootUsed, page.metrics.rootTotal); valueText: Math.round(page.percent(page.metrics.rootUsed, page.metrics.rootTotal) * 100) + "%"; accent: "#57bced" }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#344050" }

                ColumnLayout {
                    Layout.preferredWidth: 300
                    spacing: 5
                    Text { text: "FOCUS TIMER"; color: "#8995a5"; font.family: "Noto Sans"; font.pixelSize: 11; font.letterSpacing: 1 }
                    Text { text: "25:00"; color: "#f7f8fa"; font.family: "Noto Sans"; font.pixelSize: 36; font.weight: Font.Light }
                    Text { text: "READY — CONTROL NEXT PASS"; color: "#d77ec3"; font.family: "Noto Sans"; font.pixelSize: 11; font.weight: Font.DemiBold }
                }
            }
        }
    }
}
