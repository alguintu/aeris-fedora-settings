import Quickshell
import Quickshell.Io
import QtQuick
import "pages" as Pages

ShellRoot {
    id: root

    property string targetOutput: "DP-3"
    property int currentMode: 0
    readonly property var modeNames: ["IDLE", "WORK", "AI FOCUS"]
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
                    anchors.bottomMargin: 58
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
                    target: null
                    acceptedDevices: PointerDevice.TouchScreen | PointerDevice.TouchPad | PointerDevice.Mouse
                    dragThreshold: 18
                    xAxis.enabled: true
                    yAxis.enabled: false
                    grabPermissions: PointerHandler.CanTakeOverFromItems
                                     | PointerHandler.CanTakeOverFromHandlersOfDifferentType
                                     | PointerHandler.ApprovesTakeOverByAnything

                    onActiveChanged: {
                        if (active)
                            return
                        const distance = activeTranslation.x
                        if (distance < -150 && root.currentMode < root.modeNames.length - 1)
                            root.currentMode += 1
                        else if (distance > 150 && root.currentMode > 0)
                            root.currentMode -= 1
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    width: 420
                    height: 42
                    radius: 21
                    z: 20
                    color: "#e31a2230"
                    border.color: "#53607182"

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Repeater {
                            model: root.modeNames

                            Rectangle {
                                required property string modelData
                                required property int index
                                width: 130
                                height: 34
                                radius: 17
                                color: index === root.currentMode ? "#503b2857" : "transparent"
                                border.color: index === root.currentMode ? "#9469cf" : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: index === root.currentMode ? "#e2c4ff" : "#8995a5"
                                    font.family: "Noto Sans"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 1.1
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
