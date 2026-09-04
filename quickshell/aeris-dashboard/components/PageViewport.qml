import QtQuick

// Clip once at the screen, not at the inset bounds of a page's widgets.
// Each page keeps both gutters as it moves: adjacent contents are 2 * margin apart.
Item {
    id: viewport

    default property alias pages: pageTrack.data
    property int pageIndex: 0
    property real horizontalMargin: 14
    property real topMargin: 14
    property real bottomMargin: 42
    property bool dragging: false
    property real dragOffset: 0
    readonly property real pageWidth: Math.max(0, width - 2 * horizontalMargin)
    readonly property real pageHeight: Math.max(0, height - topMargin - bottomMargin)

    clip: true

    function pageIsVisible(page) {
        return visible && page.x + pageTrack.x < width
            && page.x + page.width + pageTrack.x > 0
    }

    Row {
        id: pageTrack
        x: viewport.horizontalMargin - viewport.pageIndex * viewport.width + viewport.dragOffset
        y: viewport.topMargin
        height: viewport.pageHeight
        spacing: 2 * viewport.horizontalMargin

        Behavior on x {
            enabled: !viewport.dragging
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }
    }
}
