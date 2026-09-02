import Quickshell
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

    RowLayout {
        id: topRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 176
        spacing: 12

        DashboardTile {
            Layout.preferredWidth: 430
            Layout.fillHeight: true
            title: "WORK MODE"
            eyebrow: "READY"
            accent: "#57bced"

            ColumnLayout {
                anchors.fill: parent
                spacing: 4
                Text { text: "DEEP WORKSPACE"; color: "#f2f5f8"; font.family: "Noto Sans"; font.pixelSize: 27; font.weight: Font.DemiBold; font.letterSpacing: 1 }
                Text { Layout.fillWidth: true; text: "Fast access, live load, and the current session at a glance."; color: "#aab5c2"; font.family: "Noto Sans"; font.pixelSize: 13; wrapMode: Text.WordWrap }
                Item { Layout.fillHeight: true }
                Text { text: "Swipe either direction to change context"; color: "#6fc8f2"; font.family: "Noto Sans"; font.pixelSize: 11 }
            }
        }

        DashboardTile {
            Layout.preferredWidth: 500
            Layout.fillHeight: true
            title: "LIVE LOAD"
            eyebrow: page.metricsHealthy ? "1 HZ" : "OFFLINE"
            accent: "#77d7cb"

            ColumnLayout {
                anchors.fill: parent
                spacing: 3
                MetricBar { Layout.fillWidth: true; label: "CPU"; progress: page.metrics.cpuUsage / 100; valueText: Math.round(page.metrics.cpuUsage) + "%  " + page.temperature(page.metrics.cpuTemp); accent: "#ef648c" }
                MetricBar { Layout.fillWidth: true; label: "GPU"; progress: page.metrics.gpuUsage / 100; valueText: Math.round(page.metrics.gpuUsage) + "%  " + page.temperature(page.metrics.gpuTemp); accent: "#8ed170" }
                MetricBar { Layout.fillWidth: true; label: "RAM"; progress: page.percent(page.metrics.ramUsed, page.metrics.ramTotal); valueText: Math.round(page.percent(page.metrics.ramUsed, page.metrics.ramTotal) * 100) + "%"; accent: "#57bced" }
            }
        }

        DashboardTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "SESSION"
            eyebrow: "LOCAL"
            accent: "#a99bf5"

            RowLayout {
                anchors.fill: parent
                spacing: 18
                Rectangle {
                    Layout.preferredWidth: 68
                    Layout.preferredHeight: 68
                    radius: 18
                    color: "#2e2844"
                    border.color: "#7258a0"
                    Text { anchors.centerIn: parent; text: "<>"; color: "#b69cf4"; font.family: "Noto Sans"; font.pixelSize: 25; font.weight: Font.Bold }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text { text: "No active project adapter"; color: "#eef3f8"; font.family: "Noto Sans"; font.pixelSize: 20; font.weight: Font.Medium }
                    Text { Layout.fillWidth: true; text: "Project, Git, and task context will land here without inventing state."; color: "#9ca8b8"; font.family: "Noto Sans"; font.pixelSize: 13; wrapMode: Text.WordWrap }
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
            Layout.preferredWidth: 650
            Layout.fillHeight: true
            title: "WORKSPACE"
            eyebrow: "TOUCH LAUNCH"
            accent: "#57bced"

            RowLayout {
                anchors.centerIn: parent
                spacing: 18
                ActionButton { symbol: ">_"; label: "Terminal"; accent: "#d5dbe3"; onClicked: Quickshell.execDetached(["konsole"]) }
                ActionButton { symbol: "<>"; label: "Code"; accent: "#57bced"; onClicked: Quickshell.execDetached(["code"]) }
                ActionButton { symbol: "▣"; label: "Files"; accent: "#77d7cb"; onClicked: Quickshell.execDetached(["dolphin"]) }
                ActionButton { symbol: "◎"; label: "Firefox"; accent: "#f0aa58"; onClicked: Quickshell.execDetached(["firefox"]) }
            }
        }

        DashboardTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "ACTIVE WORK"
            eyebrow: "CONNECTOR PENDING"
            accent: "#8ed170"

            ColumnLayout {
                anchors.fill: parent
                spacing: 10
                Text { text: "TODAY'S CONTEXT"; color: "#8995a5"; font.family: "Noto Sans"; font.pixelSize: 11; font.letterSpacing: 1.2 }
                Text { text: "Choose a project to make this mode situational."; color: "#eef3f8"; font.family: "Noto Sans"; font.pixelSize: 22; font.weight: Font.Medium }
                Text { Layout.fillWidth: true; text: "Next: bind repository status, running services, tasks, and a real focus timer."; color: "#aab5c2"; font.family: "Noto Sans"; font.pixelSize: 13; wrapMode: Text.WordWrap }
                Item { Layout.fillHeight: true }
                Row {
                    spacing: 8
                    Repeater {
                        model: ["GIT  NOT CONNECTED", "TASKS  NOT CONNECTED", "FOCUS  READY"]
                        Rectangle {
                            required property string modelData
                            width: tagText.implicitWidth + 24
                            height: 32
                            radius: 16
                            color: "#30262f3c"
                            border.color: "#4a526072"
                            Text { id: tagText; anchors.centerIn: parent; text: modelData; color: "#aab5c2"; font.family: "Noto Sans"; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.6 }
                        }
                    }
                }
            }
        }
    }
}
