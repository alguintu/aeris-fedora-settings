import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"

// Combined AI/work hub. Preserve the two retained cards while its content grows.
Item {
    id: page
    property bool presentationActive: true
    property var metrics: ({})
    property bool metricsHealthy: false
    property alias pollingEnabled: aiStatus.pollingEnabled
    property alias aiState: aiStatus.state
    property alias aiHealthy: aiStatus.healthy
    function openFile(path) { if (path) Qt.openUrlExternally("file://" + encodeURI(path).replace(/#/g, "%23")) }

    AiHubStatus { id: aiStatus; objectName: "hub-status-reader"; presentationActive: page.presentationActive }

    AerisAiCard {
        id: aiCard
        objectName: "hub-ai-card"
        anchors.top: parent.top
        anchors.left: parent.left
        width: 720
        height: 176
        apis: aiStatus.state.apis || []
        healthy: aiStatus.healthy
    }

    ResourceMeters {
        id: resources
        objectName: "hub-resources"
        anchors.left: aiCard.right; anchors.leftMargin: Theme.tileGap
        anchors.right: pomodoroTile.left; anchors.rightMargin: Theme.tileGap
        anchors.top: parent.top
        height: aiCard.height
        metrics: page.metrics; healthy: page.metricsHealthy
        presentationActive: page.presentationActive
    }

    DashboardTile {
        id: presets
        objectName: "hub-presets"
        anchors.left: parent.left; anchors.top: aiCard.bottom; anchors.topMargin: Theme.tileGap
        anchors.bottom: parent.bottom; width: aiCard.width
        title: "SAVED PRESETS"; accent: Theme.mauve
        contentMargin: Theme.gridContentInset
        ColumnLayout {
            anchors.fill: parent; spacing: Theme.spacingUnit
            Repeater {
                model: aiStatus.state.presets || []
                delegate: HubLink {
                    required property var modelData
                    Layout.fillWidth: true; Layout.fillHeight: true
                    label: modelData.name.replace(/^Aeris /, "")
                    detail: (modelData.context ? modelData.context + " context" : "Context unspecified")
                        + " · " + (modelData.offload === null ? "GPU offload unspecified" : Math.round(modelData.offload * 100) + "% GPU offload")
                    accent: Theme.mauve
                    hint: "Open saved preset JSON · does not apply or load a model"
                    onClicked: page.openFile(modelData.path)
                }
            }
            Text {
                visible: !(aiStatus.state.presets || []).length
                Layout.fillWidth: true; Layout.fillHeight: true
                text: aiStatus.healthy ? "No saved LM Studio presets found" : "Preset catalog unavailable"
                color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.headerDetailSize
                verticalAlignment: Text.AlignVCenter
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.tileGap
                HubLink {
                    Layout.fillWidth: true; label: "OPEN LM STUDIO"
                    enabled: aiStatus.state.studioInstalled === true
                    onClicked: Quickshell.execDetached(["gtk-launch", "lm-studio"])
                }
                HubLink {
                    Layout.fillWidth: true; label: "MODEL FILES"
                    enabled: !!aiStatus.state.modelsPath
                    onClicked: page.openFile(aiStatus.state.modelsPath)
                }
            }
        }
    }

    DashboardTile {
        objectName: "hub-worker"
        anchors.left: resources.left; anchors.right: resources.right
        anchors.top: presets.top; anchors.bottom: parent.bottom
        title: "WORKER TEMPLATES"; eyebrow: "MANUAL RUN"; accent: Theme.blue
        contentMargin: Theme.gridContentInset
        ColumnLayout {
            anchors.fill: parent; spacing: Theme.spacingUnit
            Repeater {
                model: aiStatus.state.jobs || []
                delegate: HubLink {
                    required property var modelData
                    Layout.fillWidth: true; Layout.fillHeight: true
                    label: modelData.name; accent: Theme.blue
                    hint: "Open job TOML for inspection · does not execute it"
                    onClicked: page.openFile(modelData.path)
                }
            }
            Text {
                visible: !(aiStatus.state.jobs || []).length
                Layout.fillWidth: true; Layout.fillHeight: true
                text: aiStatus.healthy ? "No saved worker templates found" : "Worker catalog unavailable"
                color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.headerDetailSize
                verticalAlignment: Text.AlignVCenter
            }
            HubLink {
                Layout.fillWidth: true; label: "OPEN WORKSPACE"
                enabled: !!aiStatus.state.workspace
                onClicked: page.openFile(aiStatus.state.workspace)
            }
        }
    }

    DashboardTile {
        id: pomodoroTile
        objectName: "hub-pomodoro-card"
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: Theme.pomodoroTileWidth
        accent: Theme.mauve

        PomodoroTile {
            objectName: "hub-pomodoro"
            anchors.fill: parent
            presentationActive: page.presentationActive
        }
    }
}
