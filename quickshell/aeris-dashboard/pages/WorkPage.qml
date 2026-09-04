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
            accent: Theme.cyan

            ColumnLayout {
                anchors.fill: parent
                spacing: 4
                Text { text: "DEEP WORKSPACE"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 27; font.weight: Font.DemiBold; font.letterSpacing: 1 }
                Text { Layout.fillWidth: true; text: "Fast access, live load, and the current session at a glance."; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 13; wrapMode: Text.WordWrap }
                Item { Layout.fillHeight: true }
                Text { text: "Swipe either direction to change context"; color: Theme.cyan; font.family: Theme.fontFamily; font.pixelSize: 11 }
            }
        }

        DashboardTile {
            Layout.preferredWidth: 500
            Layout.fillHeight: true
            title: "LIVE LOAD"
            eyebrow: page.metricsHealthy ? "1 HZ" : "OFFLINE"
            accent: Theme.teal

            ColumnLayout {
                anchors.fill: parent
                spacing: 3
                MetricBar { Layout.fillWidth: true; label: "CPU"; progress: page.metrics.cpuUsage / 100; valueText: Math.round(page.metrics.cpuUsage) + "%  " + page.temperature(page.metrics.cpuTemp); accent: Theme.red }
                MetricBar { Layout.fillWidth: true; label: "GPU"; progress: page.metrics.gpuUsage / 100; valueText: Math.round(page.metrics.gpuUsage) + "%  " + page.temperature(page.metrics.gpuTemp); accent: Theme.green }
                MetricBar { Layout.fillWidth: true; label: "RAM"; progress: page.percent(page.metrics.ramUsed, page.metrics.ramTotal); valueText: Math.round(page.percent(page.metrics.ramUsed, page.metrics.ramTotal) * 100) + "%"; accent: Theme.cyan }
            }
        }

        DashboardTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "SESSION"
            eyebrow: "LOCAL"
            accent: Theme.mauve

            RowLayout {
                anchors.fill: parent
                spacing: 18
                Rectangle {
                    Layout.preferredWidth: 68
                    Layout.preferredHeight: 68
                    radius: 18
                    color: "#2e2844"
                    border.color: "#7258a0"
                    Text { anchors.centerIn: parent; text: "<>"; color: Theme.mauve; font.family: Theme.fontFamily; font.pixelSize: 25; font.weight: Font.Bold }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text { text: "No active project adapter"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 20; font.weight: Font.Medium }
                    Text { Layout.fillWidth: true; text: "Project, Git, and task context will land here without inventing state."; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 13; wrapMode: Text.WordWrap }
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
            accent: Theme.cyan

            RowLayout {
                anchors.centerIn: parent
                spacing: 18
                ActionButton { iconName: "terminal"; label: "Terminal"; accent: Theme.text; onClicked: Quickshell.execDetached(["konsole"]) }
                ActionButton { iconName: "code"; label: "Code"; accent: Theme.cyan; onClicked: Quickshell.execDetached(["code"]) }
                ActionButton { iconName: "folder"; label: "Files"; accent: Theme.teal; onClicked: Quickshell.execDetached(["dolphin"]) }
                ActionButton { iconName: "globe"; label: "Firefox"; accent: Theme.yellow; onClicked: Quickshell.execDetached(["firefox"]) }
            }
        }

        DashboardTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "ACTIVE WORK"
            eyebrow: "CONNECTOR PENDING"
            accent: Theme.green

            ColumnLayout {
                anchors.fill: parent
                spacing: 10
                Text { text: "TODAY'S CONTEXT"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 11; font.letterSpacing: 1.2 }
                Text { text: "Choose a project to make this mode situational."; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 22; font.weight: Font.Medium }
                Text { Layout.fillWidth: true; text: "Next: bind repository status, running services, tasks, and a real focus timer."; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 13; wrapMode: Text.WordWrap }
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
                            Text { id: tagText; anchors.centerIn: parent; text: modelData; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.6 }
                        }
                    }
                }
            }
        }
    }
}
