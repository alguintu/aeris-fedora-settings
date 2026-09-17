import QtQuick
import QtQuick.Controls as Controls

Item {
    id: root
    property bool presentationActive: true
    property var sample: null
    property var shownSample: null
    property real hitInset: Theme.gridContentInset
    signal openRequested()
    Binding on shownSample {
        when: root.presentationActive
        value: root.sample
        restoreMode: Binding.RestoreNone
    }
    readonly property bool ready: shownSample !== null && shownSample.ok === true
    readonly property real completedCount: ready && Number.isInteger(shownSample.completedCount)
        && shownSample.completedCount > 0 ? shownSample.completedCount : 0
    readonly property var slots: ready ? shownSample.slots || [] : []
    readonly property bool indeterminate: slots.some(row => row && row.indeterminate)
    property real phase: 0
    readonly property bool animationRegistered: tick.registered
    DashboardHeaderLabel {
        id: label
        objectName: "downloads-header"
        anchors.top: parent.top
        anchors.left: parent.left
        text: "DOWNLOADS"
        color: Theme.mauve
    }
    TransferRateLabel {
        id: rate
        objectName: "downloads-rate"
        anchors.right: separator.visible ? separator.left : parent.right
        anchors.rightMargin: separator.visible ? Theme.spacingUnit : 0
        anchors.baseline: label.baseline
        bytesPerSecond: root.ready ? root.shownSample.downloadBytesPerSecond : null
        visible: !root.ready || Number(bytesPerSecond) > 0
        color: root.ready ? Theme.mauve : Theme.inactive
    }
    DashboardHeaderLabel {
        id: completed
        objectName: "downloads-completed"
        anchors.right: parent.right
        anchors.baseline: label.baseline
        visible: root.completedCount > 0
        text: root.completedCount > 99 ? "99+" : String(root.completedCount)
        color: Theme.green
    }
    DashboardHeaderLabel {
        id: separator
        objectName: "downloads-separator"
        anchors.right: completed.left
        anchors.rightMargin: Theme.spacingUnit
        anchors.baseline: label.baseline
        visible: completed.visible && rate.visible
        text: "·"
        color: Theme.muted
    }
    DecorativeTick {
        id: tick
        running: root.presentationActive && root.visible && root.indeterminate
        onTick: deltaMs => root.phase = (root.phase + deltaMs / 2200) % 1
    }
    Repeater {
        model: 4
        Rectangle {
            id: track
            required property int index
            readonly property var download: root.slots[index] || null
            objectName: "download-slot-" + index
            readonly property real barsTop: label.height + Theme.spacingUnit
            readonly property real stride: (root.height - barsTop + Theme.spacingUnit) / 4
            y: barsTop + Math.round(index * stride)
            width: root.width
            height: Math.round((index + 1) * stride) - Math.round(index * stride) - Theme.spacingUnit
            radius: height / 2
            // Occupancy is independent of byte progress: an active 0% download
            // must not look like an empty slot. Keep the actual fill truthful.
            color: download ? Qt.tint(Theme.raised,
                Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.32)) : Theme.raised
            Rectangle {
                objectName: "download-fill-" + track.index
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                radius: parent.radius
                width: !track.download ? 0 : track.download.indeterminate ? parent.width * 0.2
                    : parent.width * Math.max(0, Math.min(1, track.download.progress || 0))
                x: track.download && track.download.indeterminate
                    ? (parent.width - width) * (0.5 - 0.5 * Math.cos(root.phase * Math.PI * 2)) : 0
                color: Theme.mauve
                Behavior on width {
                    enabled: root.presentationActive && track.download !== null && !track.download.indeterminate
                    NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                }
            }
        }
    }
    Item {
        anchors.fill: parent
        anchors.margins: -root.hitInset
        TapHandler { gesturePolicy: TapHandler.DragThreshold; onTapped: root.openRequested() }
        HoverHandler { id: hover }
    }
    Controls.ToolTip.visible: hover.hovered
    Controls.ToolTip.text: !ready ? "FDM monitor unavailable · Tap to open FDM"
        : (root.completedCount > 0 ? root.completedCount + " completed in FDM\n" : "")
        + (slots.some(row => row) ? slots.filter(row => row).map(row => row.title + " · "
            + (row.indeterminate ? "Unknown total" : Math.round(row.progress * 100) + "%")).join("\n")
        : "No active downloads · Tap to open FDM")
}
