import QtQuick

DashboardTile {
    required property DashboardGrid grid
    required property string slotName
    objectName: grid.namePrefix + "-" + slotName
    readonly property rect bounds: grid.slot(slotName)
    x: bounds.x
    y: bounds.y
    width: bounds.width
    height: bounds.height
    contentMargin: grid.contentInset
}
