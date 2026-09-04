import Quickshell
import Quickshell.Io
import QtQuick
import "pages" as Pages

ShellRoot {
    id: root

    property string targetOutput: "DP-3"
    property int currentMode: 0
    readonly property var modeNames: ["IDLE", "WORK", "AI FOCUS"]
    property real lastSwipeDistance: 0
    property real lastSwipeVelocity: 0
    property bool lastSwipeCommitted: false
    property bool dashboardCollapsed: false
    property bool metricsHealthy: false
    property string coolingMode: "unknown"
    property bool coolingHealthy: false
    property bool coolingPending: false
    property string coolingError: ""
    property var metrics: ({
        "cpuUsage": 0,
        "cpuCcds": [],
        "cpuTemp": null,
        "cpuClock": null,
        "gpuUsage": 0,
        "gpuTemp": null,
        "gpuHotspot": null,
        "vramUsed": 0,
        "vramTotal": 1,
        "ramUsed": 0,
        "ramTotal": 1,
        "rootUsed": 0,
        "rootTotal": 1
    })

    SystemClock {
        id: systemClock
        precision: SystemClock.Seconds
    }

    function applyCoolingStatus(data) {
        try {
            const status = JSON.parse(data)
            root.coolingHealthy = status.ok === true
            root.coolingMode = status.mode || "unknown"
            root.coolingError = status.error || ""
        } catch (error) {
            root.coolingHealthy = false
            root.coolingMode = "unknown"
            root.coolingError = "Invalid CoolerControl status"
            console.warn("Aeris cooling status parse failure:", error)
        }
    }

    function setCoolingMode(mode) {
        if (root.coolingPending || !root.coolingHealthy)
            return
        root.coolingPending = true
        coolingCommandProcess.command = [
            "python3", Quickshell.shellPath("services/coolingctl.py"), "set", mode
        ]
        coolingCommandProcess.running = true
    }

    Process {
        id: metricsProcess
        command: ["python3", Quickshell.shellPath("services/metrics.py")]
        running: true

        stdout: SplitParser {
            onRead: data => {
                try {
                    root.metrics = JSON.parse(data)
                    root.metricsHealthy = true
                } catch (error) {
                    console.warn("Aeris metrics parse failure:", error)
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.metricsHealthy = false
            metricsRestart.start()
        }
    }

    Timer {
        id: metricsRestart
        interval: 2000
        onTriggered: metricsProcess.running = true
    }

    Process {
        id: coolingStatusProcess
        command: ["python3", Quickshell.shellPath("services/coolingctl.py"), "watch"]
        running: true

        stdout: SplitParser {
            onRead: data => root.applyCoolingStatus(data)
        }

        onExited: coolingStatusRestart.start()
    }

    Timer {
        id: coolingStatusRestart
        interval: 2000
        onTriggered: coolingStatusProcess.running = true
    }

    Process {
        id: coolingCommandProcess
        running: false

        stdout: SplitParser {
            onRead: data => root.applyCoolingStatus(data)
        }

        onExited: root.coolingPending = false
    }

    IpcHandler {
        target: "dashboard"
        readonly property int mode: root.currentMode
        readonly property real swipeDistance: root.lastSwipeDistance
        readonly property real swipeVelocity: root.lastSwipeVelocity
        readonly property bool swipeCommitted: root.lastSwipeCommitted
        readonly property bool collapsed: root.dashboardCollapsed
        readonly property string coolingMode: root.coolingMode
        readonly property bool coolingHealthy: root.coolingHealthy

        function setMode(mode: int): void {
            root.currentMode = Math.max(0, Math.min(root.modeNames.length - 1, mode))
        }

        function setCoolingMode(mode: string): void {
            root.setCoolingMode(mode)
        }

        function showDashboard(): void {
            root.dashboardCollapsed = false
        }

        function hideDashboard(): void {
            root.dashboardCollapsed = true
        }

        function toggleDashboard(): void {
            root.dashboardCollapsed = !root.dashboardCollapsed
        }
    }

    Variants {
        model: Quickshell.screens.filter(screen =>
            screen.name === root.targetOutput || (screen.width === 1920 && screen.height === 480))

        delegate: Component {
            PanelWindow {
                required property var modelData

                screen: modelData
                color: "transparent"
                aboveWindows: true
                focusable: false
                exclusionMode: ExclusionMode.Ignore
                mask: root.dashboardCollapsed ? collapsedInputRegion : null

                Region {
                    id: collapsedInputRegion
                    item: restoreHandle
                }

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                Image {
                    anchors.fill: parent
                    visible: !root.dashboardCollapsed
                    source: "file:///usr/share/wallpapers/Honeywave/contents/images/5120x2880.jpg"
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 1920
                    sourceSize.height: 1080
                }

                Rectangle {
                    anchors.fill: parent
                    visible: !root.dashboardCollapsed
                    color: "#b00b111c"
                }

                Item {
                    id: viewport
                    visible: !root.dashboardCollapsed
                    anchors.fill: parent
                    anchors.margins: 14
                    anchors.bottomMargin: 42
                    clip: true

                    Row {
                        id: pageTrack
                        height: viewport.height
                        width: viewport.width * 3
                        spacing: 0
                        x: -root.currentMode * viewport.width + swipeOffset()

                        function swipeOffset() {
                            if (!swipeHandler.active)
                                return 0
                            let delta = swipeHandler.activeTranslation.x
                            if ((root.currentMode === 0 && delta > 0)
                                    || (root.currentMode === root.modeNames.length - 1 && delta < 0))
                                delta *= 0.18
                            return delta
                        }

                        Behavior on x {
                            enabled: !swipeHandler.active
                            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                        }

                        Pages.IdlePage {
                            width: viewport.width
                            height: viewport.height
                            metrics: root.metrics
                            metricsHealthy: root.metricsHealthy
                            now: systemClock.date
                            coolingMode: root.coolingMode
                            coolingHealthy: root.coolingHealthy
                            coolingPending: root.coolingPending
                            coolingError: root.coolingError
                            onCoolingModeRequested: mode => root.setCoolingMode(mode)
                        }

                        Pages.WorkPage {
                            width: viewport.width
                            height: viewport.height
                            metrics: root.metrics
                            metricsHealthy: root.metricsHealthy
                        }

                        Pages.AiFocusPage {
                            width: viewport.width
                            height: viewport.height
                            metrics: root.metrics
                            metricsHealthy: root.metricsHealthy
                        }
                    }
                }

                DragHandler {
                    id: swipeHandler
                    enabled: !root.dashboardCollapsed
                    property real retainedTranslation: 0
                    property real retainedVelocity: 0
                    property double lastMovementAt: 0
                    readonly property real settleDistance: 180
                    readonly property real flickDistance: 36
                    readonly property real flickVelocity: 700
                    readonly property real flickReleaseWindow: 140

                    target: null
                    acceptedDevices: PointerDevice.TouchScreen | PointerDevice.TouchPad | PointerDevice.Mouse
                    dragThreshold: 10
                    xAxis.enabled: true
                    yAxis.enabled: false
                    grabPermissions: PointerHandler.CanTakeOverFromItems
                                     | PointerHandler.CanTakeOverFromHandlersOfDifferentType
                                     | PointerHandler.ApprovesTakeOverByAnything

                    onActiveTranslationChanged: {
                        if (active) {
                            retainedTranslation = activeTranslation.x
                            retainedVelocity = centroid.velocity.x
                            lastMovementAt = Date.now()
                        }
                    }

                    onActiveChanged: {
                        if (active) {
                            retainedTranslation = 0
                            retainedVelocity = 0
                            lastMovementAt = 0
                            return
                        }

                        const distance = retainedTranslation
                        const velocity = retainedVelocity
                        const releasedDuringFlick = Date.now() - lastMovementAt <= flickReleaseWindow
                        const flickLeft = releasedDuringFlick
                                && distance < -flickDistance && velocity < -flickVelocity
                        const flickRight = releasedDuringFlick
                                && distance > flickDistance && velocity > flickVelocity
                        const commitLeft = distance < -settleDistance || flickLeft
                        const commitRight = distance > settleDistance || flickRight

                        root.lastSwipeDistance = distance
                        root.lastSwipeVelocity = velocity
                        root.lastSwipeCommitted = false

                        if (commitLeft && root.currentMode < root.modeNames.length - 1) {
                            root.currentMode += 1
                            root.lastSwipeCommitted = true
                        } else if (commitRight && root.currentMode > 0) {
                            root.currentMode -= 1
                            root.lastSwipeCommitted = true
                        }

                        console.info("Aeris swipe:", Math.round(distance), "px,",
                                     Math.round(velocity), "px/s, committed:",
                                     root.lastSwipeCommitted)
                    }
                }

                Rectangle {
                    visible: !root.dashboardCollapsed
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    width: 152
                    height: 28
                    radius: 14
                    z: 20
                    color: "#e31a2230"
                    border.color: "#53607182"

                    Row {
                        anchors.centerIn: parent
                        spacing: 4

                        Repeater {
                            model: root.modeNames

                            Rectangle {
                                required property string modelData
                                required property int index
                                width: 32
                                height: 24
                                color: "transparent"

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: index === root.currentMode ? 18 : 8
                                    height: 8
                                    radius: 4
                                    color: index === root.currentMode ? "#e2c4ff" : "#8995a5"

                                    Behavior on width {
                                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                    }

                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }

                                TapHandler {
                                    onTapped: root.currentMode = index
                                }
                            }
                        }

                        Rectangle {
                            width: 1
                            height: 14
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#53607182"
                        }

                        Rectangle {
                            width: 28
                            height: 24
                            color: "transparent"

                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -2
                                text: "⌄"
                                color: "#b8aaf6"
                                font.family: "Noto Sans"
                                font.pixelSize: 20
                                font.weight: Font.DemiBold
                            }

                            TapHandler {
                                onTapped: root.dashboardCollapsed = true
                            }
                        }
                    }
                }

                Rectangle {
                    id: restoreHandle
                    visible: root.dashboardCollapsed
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    width: 52
                    height: 28
                    radius: 14
                    z: 20
                    color: "#e31a2230"
                    border.color: "#53607182"

                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 2
                        text: "⌃"
                        color: "#e2c4ff"
                        font.family: "Noto Sans"
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }

                    TapHandler {
                        onTapped: root.dashboardCollapsed = false
                    }
                }
            }
        }
    }
}
