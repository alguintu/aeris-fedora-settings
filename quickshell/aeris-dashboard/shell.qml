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
    property bool metricsHealthy: false
    property var metrics: ({
        "cpuUsage": 0,
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

    IpcHandler {
        target: "dashboard"
        readonly property int mode: root.currentMode
        readonly property real swipeDistance: root.lastSwipeDistance
        readonly property real swipeVelocity: root.lastSwipeVelocity
        readonly property bool swipeCommitted: root.lastSwipeCommitted

        function setMode(mode: int): void {
            root.currentMode = Math.max(0, Math.min(root.modeNames.length - 1, mode))
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

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                Image {
                    anchors.fill: parent
                    source: "file:///usr/share/wallpapers/Honeywave/contents/images/5120x2880.jpg"
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 1920
                    sourceSize.height: 1080
                }

                Rectangle {
                    anchors.fill: parent
                    color: "#b00b111c"
                }

                Item {
                    id: viewport
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
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    width: 116
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
                    }
                }
            }
        }
    }
}
