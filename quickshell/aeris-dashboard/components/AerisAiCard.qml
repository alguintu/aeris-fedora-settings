import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

DashboardTile {
    id: root
    property var apis: []
    property bool healthy: false
    title: "AERIS AI"
    accent: Theme.mauve
    contentMargin: Theme.gridContentInset
    RowLayout {
        anchors.fill: parent
        spacing: Theme.tileGap
        ThemeIcon {
            Layout.preferredWidth: 200; Layout.preferredHeight: 54
            Layout.alignment: Qt.AlignVCenter
            name: "aeris-wordmark"; color: Theme.teal
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: Theme.spacingUnit
            Repeater {
                model: root.healthy ? root.apis : [
                    {name: "llama.cpp", state: "UNKNOWN", detail: "Waiting for local API check"},
                    {name: "LM Studio", state: "UNKNOWN", detail: "Waiting for local API check"}]
                delegate: Item {
                    required property var modelData
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Text {
                        anchors.left: parent.left; anchors.top: parent.top
                        text: modelData.name; color: Theme.text
                        font.family: Theme.fontFamily; font.pixelSize: Theme.sectionTitleSize
                    }
                    Text {
                        anchors.right: parent.right; anchors.top: parent.top
                        text: modelData.state; color: modelData.online ? Theme.green : Theme.muted
                        font.family: Theme.fontFamily; font.pixelSize: Theme.headerDetailSize
                    }
                    Text {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        text: modelData.detail; elide: Text.ElideRight; color: Theme.muted
                        font.family: Theme.fontFamily; font.pixelSize: Theme.headerDetailSize
                        HoverHandler { id: hover }
                        Controls.ToolTip.visible: hover.hovered
                        Controls.ToolTip.text: modelData.detail
                    }
                }
            }
        }
    }
}
