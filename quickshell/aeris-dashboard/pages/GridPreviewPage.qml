import QtQuick
import "../components"

// A diagnostic drawing, not a migration of the approved pages. Outlines and
// coordinate labels intentionally visualize boundaries normally left invisible.
Item {
    id: page
    property bool showGrid: true
    property bool showSpans: true
    property bool showInsets: true
    readonly property alias grid: gridModel
    readonly property var placements: gridModel.placements

    HomeGrid { id: gridModel; anchors.fill: parent }

    Repeater {
        model: page.placements
        delegate: Rectangle {
            id: sample
            required property var modelData
            readonly property rect bounds: gridModel.cellRect(modelData.column, modelData.row,
                modelData.columns, modelData.rows)
            x: bounds.x; y: bounds.y; width: bounds.width; height: bounds.height
            visible: page.showSpans
            color: Theme.tintedSurface(modelData.accent, 0.2)
            radius: Theme.radius
            border.width: 1
            border.color: Qt.alpha(modelData.accent, 0.7)

            Rectangle {
                anchors.fill: parent
                anchors.margins: gridModel.contentInset
                visible: page.showInsets && sample.modelData.name !== "CONTROL RACK"
                color: Qt.alpha(sample.modelData.accent, 0.035)
                border.width: 1
                border.color: Qt.alpha(sample.modelData.accent, 0.55)
            }

            // This rack demonstrates an explicit nested grid: two equal groups,
            // each containing three equal targets, within a five-column region.
            Row {
                anchors.fill: parent
                visible: sample.modelData.name === "CONTROL RACK"
                spacing: gridModel.gutter
                Repeater {
                    model: ["LIGHTS", "FANS"]
                    delegate: Rectangle {
                        required property string modelData
                        width: (sample.width - gridModel.gutter) / 2
                        height: sample.height
                        radius: Theme.radius
                        color: Theme.surface
                        border.color: Theme.teal
                        // Each group is a tile. Its three targets share one inset,
                        // with no second padded rectangle around the entire rack.
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: gridModel.contentInset
                            visible: page.showInsets
                            color: "transparent"
                            border.color: Qt.alpha(Theme.teal, 0.55)
                        }
                        Text {
                            anchors.centerIn: parent
                            text: modelData + " · 3 TARGETS"
                            color: Theme.teal
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                        }
                        Row {
                            anchors.fill: parent
                            Repeater {
                                model: 3
                                Rectangle {
                                    width: parent.width / 3; height: parent.height
                                    color: "transparent"
                                    border.width: page.showInsets ? 1 : 0
                                    border.color: Qt.alpha(Theme.teal, 0.2)
                                }
                            }
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - 2 * gridModel.contentInset
                spacing: gridModel.spacingUnit
                visible: sample.modelData.name !== "CONTROL RACK"
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: sample.modelData.name
                    font.family: Theme.fontFamily
                    font.pixelSize: sample.modelData.columns === 1 ? 18 : 22
                    color: sample.modelData.accent
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: sample.modelData.columns + (sample.modelData.columns === 1 ? "×" : " × ")
                        + sample.modelData.rows
                    font.family: Theme.fontFamily
                    font.pixelSize: 30
                    color: Theme.text
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: sample.modelData.columns === 1 ? sample.width + "px"
                        : sample.width + " × " + sample.height + "px"
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    color: Theme.muted
                }
            }

            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: gridModel.contentInset
                visible: page.showInsets && sample.modelData.columns > 1
                    && sample.modelData.name !== "CONTROL RACK"
                text: gridModel.contentInset + "px INSET"
                color: sample.modelData.accent
                font.family: Theme.fontFamily
                font.pixelSize: 14
            }
        }
    }

    // Transparent track overlay remains above the sample surfaces, like a CSS
    // grid inspector. It has no input handlers, timers, shaders, or live services.
    Repeater {
        model: gridModel.columns * gridModel.rows
        delegate: Rectangle {
            required property int index
            readonly property int column: index % gridModel.columns
            readonly property int row: Math.floor(index / gridModel.columns)
            readonly property rect bounds: gridModel.cellRect(column, row, 1, 1)
            x: bounds.x; y: bounds.y; width: bounds.width; height: bounds.height
            visible: page.showGrid
            color: Qt.alpha(Theme.mauve, page.showSpans ? 0.015 : 0.13)
            border.color: Qt.alpha(Theme.mauve, 0.45)
            Rectangle {
                anchors.fill: parent
                anchors.margins: gridModel.contentInset
                visible: page.showInsets && !page.showSpans
                color: "transparent"
                border.color: Qt.alpha(Theme.teal, 0.55)
            }
            Text {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: 5
                text: (parent.column + 1) + ":" + (parent.row + 1)
                color: Theme.mauve
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
            Text {
                anchors.centerIn: parent
                visible: !page.showSpans
                text: "1 × 1"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 20
            }
        }
    }

    // Inspector controls use the reserved navigation band, without consuming a
    // row or changing the grid's actual 1892×424 content rectangle.
    Row {
        y: parent.height + 7
        spacing: 8
        Repeater {
            model: [{label: "GRID", key: "showGrid"}, {label: "SPANS", key: "showSpans"},
                {label: "INSETS", key: "showInsets"}]
            delegate: Rectangle {
                required property var modelData
                width: 100; height: 28
                radius: 8
                color: page[modelData.key] ? Theme.tintedSurface(Theme.mauve, 0.35) : Theme.surface
                Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: page[parent.modelData.key] ? Theme.text : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                }
                Accessible.role: Accessible.CheckBox
                Accessible.name: "Show " + modelData.label.toLowerCase()
                Accessible.checked: page[modelData.key]
                Accessible.onPressAction: page[modelData.key] = !page[modelData.key]
                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    grabPermissions: PointerHandler.TakeOverForbidden
                    onTapped: page[parent.modelData.key] = !page[parent.modelData.key]
                }
            }
        }
    }
    Text {
        anchors.right: parent.right
        y: parent.height + 12
        text: "18 × 4  ·  1u ≈ " + gridModel.unitWidth.toFixed(1) + " × "
            + gridModel.unitHeight.toFixed(0) + "  ·  GAP 12  ·  INSET 12  ·  SPACE 6"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 16
    }
}
