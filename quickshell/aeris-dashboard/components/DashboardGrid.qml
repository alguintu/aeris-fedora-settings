import QtQuick

// Shared page geometry. All coordinates are zero-based; spans include gaps.
// Round shared edges, not individual widths, so the last track lands exactly.
Item {
    id: root
    property int columns: 18
    property int rows: 4
    property int gutter: Theme.tileGap
    property string namePrefix: "grid"
    property var placements: []
    readonly property int contentInset: Theme.gridContentInset
    readonly property int spacingUnit: Theme.spacingUnit
    readonly property real columnPitch: (width + gutter) / columns
    readonly property real rowPitch: (height + gutter) / rows
    readonly property real unitWidth: columnPitch - gutter
    readonly property real unitHeight: rowPitch - gutter

    function cellRect(column, row, columnSpan, rowSpan) {
        const left = Math.round(column * columnPitch)
        const top = Math.round(row * rowPitch)
        return Qt.rect(left, top,
            Math.round((column + columnSpan) * columnPitch) - gutter - left,
            Math.round((row + rowSpan) * rowPitch) - gutter - top)
    }

    function slot(key) {
        const spec = placements.find(item => item.key === key)
        return spec ? cellRect(spec.column, spec.row, spec.columns, spec.rows) : Qt.rect(0, 0, 0, 0)
    }
}
