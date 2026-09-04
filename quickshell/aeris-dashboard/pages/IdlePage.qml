import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import "../components"

Item {
    id: page

    property var metrics: ({})
    property bool metricsHealthy: false
    property bool animationsActive: true
    property string profilingPaused: ""
    function profilePaused(name) { return profilingPaused.split(",").indexOf(name) !== -1 }
    property date now
    property string lightingMode: "unknown"
    property bool lightingHealthy: false
    property bool lightingPending: false
    property string lightingError: ""
    property string coolingMode: "unknown"
    property bool coolingHealthy: false
    property bool coolingPending: false
    property string coolingError: ""

    signal lightingModeRequested(string mode)
    signal coolingModeRequested(string mode)

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

    function nominalCapacity(value) {
        if (!value || value <= 0)
            return "--"
        const gibibytes = value / (1024 * 1024 * 1024)
        return Math.pow(2, Math.round(Math.log(gibibytes) / Math.LN2)) + "GB"
    }

    DashboardTile {
        id: mediaTile
        anchors.top: parent.top
        anchors.left: parent.left
        width: 540
        height: middleBand.rowHeight + controlGrid.spacing + controlGrid.tileSize
        accent: Theme.mauve
        contentMargin: 24

        MediaControls {
            visible: !page.profilePaused("media")
            anchors.fill: parent
        }
    }

    DashboardTile {
        id: cpuTile
        anchors.top: parent.top
        anchors.right: parent.right
        width: mediaTile.width
        height: Math.round((parent.height - 12) / 2)

        Item {
            anchors.fill: parent
            clip: true

            Item {
                id: cpuSection
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.round((parent.width - 21) * 0.595)

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10

                    DashboardSectionHeader {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        title: "CPU"
                        iconName: "processor"
                        detail: "R9 5950X " + (page.metrics.cpuClock > 0
                                ? page.metrics.cpuClock.toFixed(1) : "--") + "GHz"
                        detailHint: "Representative clock of the busiest logical CPU, not an all-core average. One frequency read per second."
                        eyebrow: Math.round(page.metrics.cpuUsage) + "% "
                                 + page.temperature(page.metrics.cpuTemp)
                        accent: Theme.teal
                    }

                    CpuHeatmap {
                        animationEnabled: page.animationsActive && !page.profilePaused("cpu")
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Binding on ccds {
                            when: !page.profilePaused("cpu")
                            value: page.metrics.cpuCcds || []
                            restoreMode: Binding.RestoreNone
                        }
                    }
                }
            }

            Item {
                anchors.left: cpuSection.right
                anchors.leftMargin: 21
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10

                    DashboardSectionHeader {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        title: "RAM"
                        eyebrow: Math.round(page.percent(page.metrics.ramUsed,
                                                         page.metrics.ramTotal) * 100)
                                 + "% · " + page.nominalCapacity(page.metrics.ramTotal)
                        accent: Theme.cyan
                    }

                    MemoryHeatmap {
                        animationEnabled: page.animationsActive && !page.profilePaused("memory")
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        field: "ram"
                        ramUtilization: page.percent(page.metrics.ramUsed,
                                                     page.metrics.ramTotal) * 100
                    }
                }
            }
        }
    }

    DashboardTile {
        id: gpuTile
        anchors.top: cpuTile.bottom
        anchors.topMargin: 12
        anchors.bottom: parent.bottom
        anchors.left: cpuTile.left
        anchors.right: parent.right

        Item {
            anchors.fill: parent
            clip: true

            Item {
                id: gpuSection
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.round((parent.width - 21) * 0.595)

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10

                    DashboardSectionHeader {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        title: "GPU"
                        iconName: "graphics-card"
                        detail: "RX 6900 XT"
                        eyebrow: Math.round(page.metrics.gpuUsage) + "% · "
                                 + page.temperature(page.metrics.gpuTemp)
                        accent: Theme.teal
                    }

                    GpuHeatmap {
                        profilingNoBlend: page.profilePaused("gpu-blend")
                        profilingNoPaint: page.profilePaused("gpu-paint")
                        animationEnabled: page.animationsActive && !page.profilePaused("gpu")
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        utilization: page.metrics.gpuUsage || 0
                    }
                }
            }

            Item {
                anchors.left: gpuSection.right
                anchors.leftMargin: 21
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10

                    DashboardSectionHeader {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        title: "VRAM"
                        eyebrow: Math.round(page.percent(page.metrics.vramUsed,
                                                         page.metrics.vramTotal) * 100)
                                 + "% · " + page.nominalCapacity(page.metrics.vramTotal)
                        accent: Theme.mauve
                    }

                    MemoryHeatmap {
                        animationEnabled: page.animationsActive && !page.profilePaused("memory")
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        field: "vram"
                        vramUtilization: page.percent(page.metrics.vramUsed,
                                                      page.metrics.vramTotal) * 100
                    }
                }
            }
        }
    }

    Item {
        id: middleBand
        readonly property real rowHeight: Math.round((height - 12) / 2)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: mediaTile.right
        anchors.leftMargin: 12
        anchors.right: cpuTile.left
        anchors.rightMargin: 12

        Row {
            id: timeTiles
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: middleBand.rowHeight
            spacing: 12

            DashboardTile {
                width: timeTiles.width - pomodoroTile.width - timeTiles.spacing
                height: timeTiles.height
                accent: Theme.blue

                Item {
                    anchors.fill: parent

                    WeatherPattern {
                        anchors.fill: parent
                        anchors.margins: -18
                        condition: WeatherService.condition
                        isDay: WeatherService.previewMode ? WeatherService.previewMode !== "night"
                            : WeatherService.state.isDay !== false
                        animationEnabled: page.animationsActive && !page.profilePaused("weather")
                        useCanvasRenderer: WeatherService.renderingBackend === "canvas"
                        fixedTime: WeatherService.fixedAnimationTime
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        height: 84
                        verticalAlignment: Text.AlignVCenter
                        text: String(page.now.getHours() % 12 || 12).padStart(2, "0")
                        color: Theme.blue
                        font.family: Theme.clockBoldFontFamily
                        font.pixelSize: 100
                        font.weight: Font.Bold
                    }

                    Text {
                        id: clockMinute
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        height: 84
                        verticalAlignment: Text.AlignVCenter
                        text: String(page.now.getMinutes()).padStart(2, "0")
                        color: Theme.blue
                        font.family: Theme.clockBoldFontFamily
                        font.pixelSize: 100
                        font.weight: Font.Bold
                    }

                    Text {
                        anchors.left: clockMinute.right
                        anchors.leftMargin: 12
                        anchors.baseline: clockMinute.baseline
                        text: page.now.getHours() >= 12 ? "PM" : "AM"
                        color: Theme.green
                        font.family: Theme.clockBoldFontFamily
                        font.pixelSize: 36
                        font.weight: Font.Bold
                    }

                    Text {
                        id: clockDate
                        anchors.right: parent.right
                        anchors.bottom: clockWeekday.top
                        anchors.bottomMargin: 2
                        text: Qt.formatDateTime(page.now, "MMM d")
                        color: Theme.yellow
                        font.family: Theme.clockFontFamily
                        font.pixelSize: 24
                    }

                    Text {
                        id: clockWeekday
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        text: Qt.formatDateTime(page.now, "dddd")
                        color: Theme.yellow
                        font.family: Theme.clockBoldFontFamily
                        font.pixelSize: 36
                        font.weight: Font.Bold
                    }

                    Row {
                        id: weatherReading
                        anchors.top: parent.top
                        anchors.right: parent.right
                        spacing: 12

                        ThemeIcon {
                            width: 52
                            height: 52
                            name: WeatherService.icon
                            color: Theme.mauve
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 52
                            verticalAlignment: Text.AlignVCenter
                            text: WeatherService.temperature
                            color: Theme.cyan
                            font.family: Theme.clockBoldFontFamily
                            font.weight: Font.Bold
                            font.pixelSize: 60
                        }
                    }

                    Text {
                        id: weatherDescription
                        anchors.right: parent.right
                        anchors.top: weatherReading.bottom
                        anchors.topMargin: 6
                        text: (WeatherService.stale ? "Cached: " : "") + WeatherService.description
                        width: Math.min(implicitWidth, 240)
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        color: WeatherService.stale ? Theme.orange : Theme.mauve
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                    }

                    Item {
                        anchors.top: weatherReading.top
                        anchors.right: parent.right
                        width: Math.max(weatherReading.width, weatherDescription.width)
                        height: 96
                        Accessible.role: Accessible.Button
                        Accessible.name: "Refresh weather for " + (WeatherService.state.location || "configured location")
                        Accessible.onPressAction: WeatherService.refresh(true)
                        Controls.ToolTip.visible: weatherHover.hovered
                        Controls.ToolTip.text: (WeatherService.state.location || "Set location")
                            + " · " + WeatherService.description + (WeatherService.stale ? " (cached)" : "")
                            + (WeatherService.available ? " · Updated " + Qt.formatDateTime(new Date(WeatherService.state.fetchedAt * 1000), "h:mm AP") : "")
                            + "\nModel conditions by Open-Meteo · tap to refresh"
                        HoverHandler { id: weatherHover }
                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            grabPermissions: PointerHandler.TakeOverForbidden
                            onTapped: WeatherService.refresh(true)
                        }
                    }
                }
            }

            DashboardTile {
                id: pomodoroTile
                width: 296
                height: middleBand.height
                accent: Theme.mauve
                PomodoroTile {
                    visible: !page.profilePaused("pomodoro")
                    presentationActive: page.animationsActive && !page.profilePaused("pomodoro")
                    anchors.fill: parent
                }
            }
        }

        KeepAwakeButton {
            id: keepAwake
            contentMargin: cpuTile.contentMargin
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: controlGrid.tileSize
            height: middleBand.rowHeight
        }

        DashboardTile {
            // User-selected capacity label for the mounted storage summary.
            anchors.left: keepAwake.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: pomodoroTile.width + 12
            anchors.top: timeTiles.bottom
            anchors.topMargin: 12
            anchors.bottom: parent.bottom

            Item {
                id: diskSummary
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: diskLabelMetrics.tightBoundingRect.width

                ThemeIcon {
                    id: diskCapacityIcon
                    anchors.left: parent.left
                    anchors.top: parent.top
                    name: "harddisk-tight"
                    color: Theme.blue
                    width: diskLabelMetrics.tightBoundingRect.width
                    height: width * 20 / 16
                }

                Item {
                    id: diskCapacityInk
                    anchors.left: parent.left
                    anchors.top: diskCapacityIcon.bottom
                    anchors.topMargin: 16
                    width: parent.width
                    height: diskLabelMetrics.tightBoundingRect.height

                    Text {
                        id: diskCapacityLabel
                        // Align the ink bounds, not the font's invisible bearings.
                        x: -diskLabelMetrics.tightBoundingRect.x
                        y: -baselineOffset - diskLabelMetrics.tightBoundingRect.y
                        text: "6.5TB"
                        color: Theme.blue
                        font.family: Theme.clockBoldFontFamily
                        font.weight: Font.Bold
                        font.pixelSize: 32
                    }
                }

                Item {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: diskFreeLineMetrics.tightBoundingRect.height

                    Text {
                        id: diskFreeLine
                        x: -diskFreeLineMetrics.tightBoundingRect.x
                        y: -baselineOffset - diskFreeLineMetrics.tightBoundingRect.y
                        text: (page.metrics.mountedDiskTotal > 0
                            && page.metrics.mountedDiskFree !== null
                            && page.metrics.mountedDiskFree !== undefined
                            ? Math.round(page.metrics.mountedDiskFree / page.metrics.mountedDiskTotal * 100) + "%"
                            : "--%") + " FREE"
                        color: Theme.green
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        wrapMode: Text.NoWrap
                    }

                    TextMetrics {
                        id: diskFreeLineMetrics
                        font: diskFreeLine.font
                        text: diskFreeLine.text
                    }
                }

            }

            TextMetrics {
                id: diskLabelMetrics
                font: diskCapacityLabel.font
                text: diskCapacityLabel.text
            }

            Rectangle {
                id: diskDivider
                anchors.left: diskSummary.right
                anchors.leftMargin: 18
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Theme.border
            }

            Column {
                anchors.left: diskDivider.right
                anchors.leftMargin: 18
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: (height - 4 * 35) / 3

                Repeater {
                    model: 4

                    delegate: Item {
                        id: driveRow
                        required property int index
                        readonly property var drive: (page.metrics.drives || [])[index] || null
                        readonly property color accent: [Theme.red, Theme.green, Theme.yellow, Theme.cyan][index]
                        width: parent.width
                        height: 35

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 23
                            text: ["SYSTEM", "WORKSPACE", "DOCUMENTS", "STORAGE"][driveRow.index]
                            color: driveRow.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 8
                            radius: 4
                            color: Theme.inset

                            Rectangle {
                                width: parent.width * (driveRow.drive && driveRow.drive.total > 0
                                    ? Math.max(0, Math.min(1, driveRow.drive.used / driveRow.drive.total)) : 0)
                                height: parent.height
                                radius: parent.radius
                                color: driveRow.accent
                                Behavior on width {
                                    NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    }
                }
            }
        }

    }

    Rectangle {
        id: controlGrid
        anchors.left: mediaTile.left
        anchors.top: mediaTile.bottom
        anchors.topMargin: spacing
        width: (mediaTile.width - spacing) / 2
        height: tileSize
        radius: Theme.radius
        readonly property real spacing: 12

        readonly property real tileSize: (middleBand.rowHeight - spacing) / 2
        readonly property real buttonWidth: (width - spacing * 2) / 3

        readonly property var selectedButton: workLight.selected ? workLight
            : dayNightLight.selected ? dayNightLight : partyOffLight.selected ? partyOffLight : null
        readonly property var hoveredButton: workLight.hovered ? workLight
            : dayNightLight.hovered ? dayNightLight : partyOffLight.hovered ? partyOffLight : null
        readonly property bool pressed: workLight.pressed || dayNightLight.pressed || partyOffLight.pressed
        readonly property var tintButton: hoveredButton || selectedButton
        color: tintButton ? Theme.tintedSurface(tintButton.accent,
            pressed ? 0.32 : selectedButton ? Theme.controlTint : 0.14) : Theme.surface
        border.width: 0

        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Row {
            anchors.fill: parent
            spacing: controlGrid.spacing

            LightingModeButton {
                id: workLight
                flat: true
                width: controlGrid.buttonWidth
                height: controlGrid.tileSize
                iconKind: "aeris"
                accent: Theme.teal
                selected: page.lightingMode === "work"
                available: page.lightingHealthy
                busy: page.lightingPending
                onClicked: page.lightingModeRequested("work")
            }

            LightingModeButton {
                id: dayNightLight
                flat: true
                width: controlGrid.buttonWidth
                height: controlGrid.tileSize
                iconKind: page.lightingMode === "day" ? "day" : "night"
                accent: page.lightingMode === "day" ? Theme.text : Theme.green
                selected: page.lightingMode === "night" || page.lightingMode === "day"
                available: page.lightingHealthy
                busy: page.lightingPending
                onClicked: page.lightingModeRequested(
                    page.lightingMode === "night" ? "day" : "night"
                )
            }

            LightingModeButton {
                id: partyOffLight
                flat: true
                width: controlGrid.buttonWidth
                height: controlGrid.tileSize
                iconKind: page.lightingMode === "off" ? "off" : "party"
                accent: page.lightingMode === "off" ? Theme.muted : Theme.mauve
                selected: page.lightingMode === "party" || page.lightingMode === "off"
                available: page.lightingHealthy
                busy: page.lightingPending
                onClicked: page.lightingModeRequested(
                    page.lightingMode === "party" ? "off" : "party"
                )
            }
        }
    }

    Rectangle {
        id: coolingGroup
        anchors.left: controlGrid.right
        anchors.leftMargin: controlGrid.spacing
        anchors.top: controlGrid.top
        width: controlGrid.width
        height: controlGrid.tileSize
        radius: Theme.radius

        readonly property var selectedButton: defaultFan.selected ? defaultFan
            : tunedFan.selected ? tunedFan : firmwareFan.selected ? firmwareFan : null
        readonly property var hoveredButton: defaultFan.hovered ? defaultFan
            : tunedFan.hovered ? tunedFan : firmwareFan.hovered ? firmwareFan : null
        readonly property bool pressed: defaultFan.pressed || tunedFan.pressed || firmwareFan.pressed
        readonly property var tintButton: hoveredButton || selectedButton
        color: tintButton ? Theme.tintedSurface(tintButton.accent,
            pressed ? 0.32 : selectedButton ? Theme.controlTint : 0.14) : Theme.surface
        border.width: 0

        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Row {
            anchors.fill: parent
            spacing: controlGrid.spacing

            CoolingModeButton {
                id: defaultFan
                flat: true
                width: controlGrid.buttonWidth
                height: controlGrid.tileSize
                iconKind: "default"
                accent: Theme.teal
                selected: page.coolingMode === "default"
                available: page.coolingHealthy
                busy: page.coolingPending
                onClicked: page.coolingModeRequested("default")
            }

            CoolingModeButton {
                id: tunedFan
                flat: true
                width: controlGrid.buttonWidth
                height: controlGrid.tileSize
                iconKind: page.coolingMode === "performance" ? "performance" : "quiet"
                accent: page.coolingMode === "performance" ? Theme.yellow : Theme.green
                selected: page.coolingMode === "quiet" || page.coolingMode === "performance"
                available: page.coolingHealthy
                busy: page.coolingPending
                onClicked: page.coolingModeRequested(
                    page.coolingMode === "quiet" ? "performance" : "quiet"
                )
            }

            CoolingModeButton {
                id: firmwareFan
                flat: true
                width: controlGrid.buttonWidth
                height: controlGrid.tileSize
                iconKind: "firmware"
                accent: Theme.mauve
                selected: page.coolingMode === "firmware"
                available: page.coolingHealthy
                busy: page.coolingPending
                onClicked: page.coolingModeRequested("firmware")
            }
        }
    }
}
