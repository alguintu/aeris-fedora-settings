import QtQuick
import QtQuick.Layouts
import "../components"

Item {
    id: page

    property var metrics: ({})
    property bool metricsHealthy: false

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

    RowLayout {
        id: topRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 176
        spacing: 12

        DashboardTile {
            Layout.preferredWidth: 720
            Layout.fillHeight: true
            title: "AERIS AI"
            eyebrow: "STATE UNKNOWN"
            accent: "#d77ec3"

            RowLayout {
                anchors.fill: parent
                spacing: 20

                Rectangle {
                    Layout.preferredWidth: 88
                    Layout.preferredHeight: 88
                    radius: 24
                    color: "#3a2650"
                    border.color: "#8c5fca"
                    Text { anchors.centerIn: parent; text: "A"; color: "#d0a7f4"; font.family: "Noto Sans"; font.pixelSize: 42; font.weight: Font.Bold }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text { text: "Qwen3.5-27B"; color: "#f2f4f8"; font.family: "Noto Sans"; font.pixelSize: 30; font.weight: Font.Medium }
                    Text { text: "Local text model target"; color: "#a99bf5"; font.family: "Noto Sans"; font.pixelSize: 14 }
                    Text { text: "Runtime detection and controls are not connected yet."; color: "#9ca8b8"; font.family: "Noto Sans"; font.pixelSize: 12 }
                }

                Rectangle {
                    Layout.preferredWidth: 132
                    Layout.preferredHeight: 44
                    radius: 22
                    color: "#2a2935"
                    border.color: "#575367"
                    Text { anchors.centerIn: parent; text: "UNKNOWN"; color: "#aaa5b6"; font.family: "Noto Sans"; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1 }
                }
            }
        }

        DashboardTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "ACCELERATOR"
            eyebrow: page.metricsHealthy ? "LIVE" : "OFFLINE"
            accent: "#8ed170"

            ColumnLayout {
                anchors.fill: parent
                spacing: 3
                MetricBar { Layout.fillWidth: true; label: "GPU"; progress: page.metrics.gpuUsage / 100; valueText: Math.round(page.metrics.gpuUsage) + "%  " + page.temperature(page.metrics.gpuTemp); accent: "#8ed170" }
                MetricBar { Layout.fillWidth: true; label: "VRAM"; progress: page.percent(page.metrics.vramUsed, page.metrics.vramTotal); valueText: page.bytes(page.metrics.vramUsed); accent: "#a99bf5" }
                MetricBar { Layout.fillWidth: true; label: "HOT"; progress: (page.metrics.gpuHotspot || 0) / 110; valueText: page.temperature(page.metrics.gpuHotspot); accent: "#f0aa58" }
            }
        }

        DashboardTile {
            Layout.preferredWidth: 430
            Layout.fillHeight: true
            title: "MODE"
            eyebrow: "AI FOCUS"
            accent: "#a99bf5"

            Column {
                anchors.centerIn: parent
                spacing: 7
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "LOCAL FIRST"; color: "#eee8f5"; font.family: "Noto Sans"; font.pixelSize: 26; font.weight: Font.DemiBold; font.letterSpacing: 2 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "SWIPE RIGHT TO EXIT"; color: "#b69ad9"; font.family: "Noto Sans"; font.pixelSize: 11; font.letterSpacing: 1.2 }
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
            Layout.preferredWidth: 700
            Layout.fillHeight: true
            title: "RUNTIME"
            eyebrow: "NEXT MILESTONE"
            accent: "#d77ec3"

            ColumnLayout {
                anchors.fill: parent
                spacing: 9
                Text { Layout.fillWidth: true; text: "RUNTIME ADAPTER NOT CONNECTED"; color: "#efb3ca"; font.family: "Noto Sans"; font.pixelSize: 19; font.weight: Font.DemiBold; horizontalAlignment: Text.AlignLeft }
                Text { Layout.fillWidth: true; text: "This tile will own load/unload, context, throughput, and memory pressure once the llama.cpp adapter is real."; color: "#aab5c2"; font.family: "Noto Sans"; font.pixelSize: 13; wrapMode: Text.WordWrap }
                Item { Layout.fillHeight: true }
                Row {
                    spacing: 8
                    Repeater {
                        model: ["MODEL STATE  --", "API  NOT CONNECTED", "TOKENS  --"]
                        Rectangle {
                            required property string modelData
                            width: runtimeTag.implicitWidth + 24
                            height: 32
                            radius: 16
                            color: "#34243a49"
                            border.color: "#61496f83"
                            Text { id: runtimeTag; anchors.centerIn: parent; text: modelData; color: "#c0a4d2"; font.family: "Noto Sans"; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.6 }
                        }
                    }
                }
            }
        }

        DashboardTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "RESOURCE ENVELOPE"
            eyebrow: "OBSERVED"
            accent: "#57bced"

            RowLayout {
                anchors.fill: parent
                spacing: 24

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text { text: "GPU MEMORY"; color: "#8995a5"; font.family: "Noto Sans"; font.pixelSize: 11; font.letterSpacing: 1 }
                    Text { text: page.bytes(page.metrics.vramUsed) + " / " + page.bytes(page.metrics.vramTotal); color: "#eef3f8"; font.family: "Noto Sans"; font.pixelSize: 24 }
                    MetricBar { Layout.fillWidth: true; label: "VRAM"; progress: page.percent(page.metrics.vramUsed, page.metrics.vramTotal); valueText: Math.round(page.percent(page.metrics.vramUsed, page.metrics.vramTotal) * 100) + "%"; accent: "#a99bf5" }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#344050" }

                ColumnLayout {
                    Layout.preferredWidth: 410
                    spacing: 4
                    Text { text: "THERMAL HEADROOM"; color: "#8995a5"; font.family: "Noto Sans"; font.pixelSize: 11; font.letterSpacing: 1 }
                    Text { text: page.temperature(page.metrics.gpuHotspot); color: "#f0aa58"; font.family: "Noto Sans"; font.pixelSize: 34; font.weight: Font.Light }
                    Text { text: "Live hotspot reading — policy thresholds pending"; color: "#aab5c2"; font.family: "Noto Sans"; font.pixelSize: 12 }
                }
            }
        }
    }
}
