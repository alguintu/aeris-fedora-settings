import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import "pages" as Pages
import "components" as Components

ShellRoot {
    id: root

    property string targetOutput: "DP-3"
    property int currentMode: 1 // Idle remains the startup page.
    readonly property var modeNames: ["PC SPECS", "IDLE", "WORK", "AI FOCUS"]
    property real lastSwipeDistance: 0
    property real lastSwipeVelocity: 0
    property bool lastSwipeCommitted: false
    property bool dashboardCollapsed: false
    property var rendererInfo: ({api: "uninitialized"})
    property var renderProbe: null
    property bool metricsHealthy: false
    // Explicit rollback retains the reference adapters for matched comparisons.
    readonly property bool nativeBackend: Components.BackendService.useNative
    readonly property string backendBinary: Components.BackendService.binary
    // Session-only render profiling. Never sent to RGB/fan control services.
    property real simulatedGpuUsage: -1
    // Reversible profiling only; watchdog restores live presentation if a runner exits.
    property string profilingPaused: ""
    property bool profilingReplay: false
    Timer {
        id: profilingWatchdog
        interval: 60000
        onTriggered: { root.profilingPaused = ""; root.profilingReplay = false }
    }
    property string lightingMode: "unknown"
    property bool lightingHealthy: false
    property bool lightingPending: false
    property string lightingError: ""
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
    })

    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
    }

    function applyLightingStatus(data) {
        try {
            const status = typeof data === "string" ? JSON.parse(data) : data
            root.lightingHealthy = status.ok === true
            root.lightingMode = status.mode || "unknown"
            root.lightingError = status.error || ""
        } catch (error) {
            root.lightingHealthy = false
            root.lightingMode = "unknown"
            root.lightingError = "Invalid daemon status"
            console.warn("Aeris RGB status parse failure:", error)
        }
    }

    function setLightingMode(mode) {
        if (root.lightingPending || !root.lightingHealthy)
            return
        root.lightingPending = true
        rgbCommandProcess.command = Components.BackendService.command("rgb", ["set", mode])
        rgbCommandProcess.running = true
    }

    function applyCoolingStatus(data) {
        try {
            const status = typeof data === "string" ? JSON.parse(data) : data
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
        coolingCommandProcess.command = Components.BackendService.command("cooling", ["set", mode])
        coolingCommandProcess.running = true
    }

    Process {
        id: metricsProcess
        command: root.nativeBackend ? [root.backendBinary, "watch"]
                                    : ["python3", Quickshell.shellPath("services/metrics.py")]
        running: true

        stdout: SplitParser {
            onRead: data => {
                try {
                    const event = JSON.parse(data)
                    if (root.nativeBackend) Components.BackendService.publish(event.service, event.payload)
                    if (root.nativeBackend && event.service === "rgb") {
                        root.applyLightingStatus(event.payload)
                        return
                    }
                    if (root.nativeBackend && event.service === "cooling") {
                        root.applyCoolingStatus(event.payload)
                        return
                    }
                    if (root.nativeBackend && event.service !== "metrics") return
                    if (root.nativeBackend && event.payload.ok !== true) {
                        root.metricsHealthy = false
                        return
                    }
                    const sample = root.nativeBackend ? event.payload.data : event
                    if (root.simulatedGpuUsage >= 0) sample.gpuUsage = root.simulatedGpuUsage
                    if (!root.profilingReplay) root.metrics = sample
                    root.metricsHealthy = true
                } catch (error) {
                    console.warn("Aeris metrics parse failure:", error)
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.metricsHealthy = false
            if (root.nativeBackend) {
                root.lightingHealthy = false
                root.coolingHealthy = false
                Components.BackendService.disconnected()
            }
            metricsRestart.start()
        }
    }

    Timer {
        id: metricsRestart
        interval: 2000
        onTriggered: metricsProcess.running = true
    }

    Process {
        id: rgbStatusProcess
        command: ["python3", Quickshell.shellPath("services/rgbctl.py"), "watch"]
        running: !root.nativeBackend

        stdout: SplitParser {
            onRead: data => root.applyLightingStatus(data)
        }

        onExited: { if (!root.nativeBackend) rgbStatusRestart.start() }
    }

    Timer {
        id: rgbStatusRestart
        interval: 2000
        onTriggered: { if (!root.nativeBackend) rgbStatusProcess.running = true }
    }

    Process {
        id: rgbCommandProcess
        running: false

        stdout: SplitParser {
            onRead: data => root.applyLightingStatus(data)
        }

        onExited: {
            root.lightingPending = false
        }
    }

    Process {
        id: coolingStatusProcess
        command: ["python3", Quickshell.shellPath("services/coolingctl.py"), "watch"]
        running: !root.nativeBackend

        stdout: SplitParser {
            onRead: data => root.applyCoolingStatus(data)
        }

        onExited: { if (!root.nativeBackend) coolingStatusRestart.start() }
    }

    Timer {
        id: coolingStatusRestart
        interval: 2000
        onTriggered: { if (!root.nativeBackend) coolingStatusProcess.running = true }
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
        function renderingStatus(): string { return JSON.stringify(root.rendererInfo) }
        function frameTiming(start: bool): string {
            if (!root.renderProbe) return "{}"
            if (start) { root.renderProbe.start(); return "{}" }
            return JSON.stringify(root.renderProbe.stop())
        }
        function backendStatus(): string {
            return JSON.stringify({implementation: root.nativeBackend ? "rust" : "python",
                metricsHealthy: root.metricsHealthy, lightingHealthy: root.lightingHealthy,
                lightingMode: root.lightingMode, coolingHealthy: root.coolingHealthy,
                coolingMode: root.coolingMode, tomatHealthy: Components.TomatService.healthy,
                awakeHealthy: Components.BackendService.awakeState?.ok === true,
                connected: Components.BackendService.connected})
        }
        function decorationRate(fps: int): void {
            if (fps === 30 || fps === 60) Components.DecorativeClock.framesPerSecond = fps
        }
        function decorationClock(): string {
            return JSON.stringify({fps: Components.DecorativeClock.framesPerSecond,
                ticks: Components.DecorativeClock.ticks, users: Components.DecorativeClock.users})
        }
        function profile(paused: string, replay: bool): void {
            root.profilingPaused = paused
            root.profilingReplay = replay
            profilingWatchdog.restart()
        }
        function profileFrame(frame: string): void {
            if (!root.profilingReplay) return
            profilingWatchdog.restart()
            if (root.profilingPaused.split(",").indexOf("metrics") === -1)
                root.metrics = JSON.parse(frame)
        }
        readonly property string profiling: root.profilingPaused
        readonly property bool replaying: root.profilingReplay
        function simulateGpu(percent: real): void {
            root.simulatedGpuUsage = percent < 0 ? -1 : Math.min(100, percent)
            if (root.simulatedGpuUsage >= 0)
                root.metrics = Object.assign({}, root.metrics, {gpuUsage: root.simulatedGpuUsage})
        }
        readonly property int mode: root.currentMode
        readonly property real swipeDistance: root.lastSwipeDistance
        readonly property real swipeVelocity: root.lastSwipeVelocity
        readonly property bool swipeCommitted: root.lastSwipeCommitted
        readonly property bool collapsed: root.dashboardCollapsed
        readonly property string lightingMode: root.lightingMode
        readonly property bool lightingHealthy: root.lightingHealthy
        readonly property string coolingMode: root.coolingMode
        readonly property bool coolingHealthy: root.coolingHealthy

        function setMode(mode: int): void {
            root.currentMode = Math.max(0, Math.min(root.modeNames.length - 1, mode))
        }

        function setLightingMode(mode: string): void {
            root.setLightingMode(mode)
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
                mask: dashboardMotion.fullyHidden ? collapsedInputRegion : null

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

                Components.SlideReveal {
                    id: dashboardMotion
                    anchors.fill: parent
                    collapsed: root.dashboardCollapsed

                    Binding {
                        target: root
                        property: "rendererInfo"
                        value: ({api: dashboardMotion.GraphicsInfo.api === GraphicsInfo.Vulkan ? "vulkan"
                            : dashboardMotion.GraphicsInfo.api === GraphicsInfo.OpenGL ? "opengl"
                            : dashboardMotion.GraphicsInfo.api === GraphicsInfo.Software ? "software" : "other",
                            requested: Quickshell.env("QSG_RHI_BACKEND"),
                            moving: dashboardMotion.moving, hidden: dashboardMotion.fullyHidden,
                            interactive: dashboardMotion.interactive})
                    }

                    Components.FrameProbe { id: frameProbe }
                    Binding { target: root; property: "renderProbe"; value: frameProbe }

                    Image {
                        anchors.fill: parent
                        source: "file:///usr/share/wallpapers/Honeywave/contents/images/5120x2880.jpg"
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 1920
                        sourceSize.height: 1080
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blurMax: 48
                            blur: 0.85
                        }
                    }

                    Components.PageViewport {
                        id: viewport
                        anchors.fill: parent
                        pageIndex: root.currentMode
                        dragging: swipeHandler.active
                        dragOffset: {
                            if (!swipeHandler.active)
                                return 0
                            let delta = swipeHandler.activeTranslation.x
                            if ((root.currentMode === 0 && delta > 0)
                                    || (root.currentMode === root.modeNames.length - 1 && delta < 0))
                                delta *= 0.18
                            return delta
                        }

                        Pages.SpecsPage {
                            width: viewport.pageWidth
                            height: viewport.pageHeight
                        }

                        Pages.IdlePage {
                            id: idlePage
                            profilingPaused: root.profilingPaused
                            width: viewport.pageWidth
                            height: viewport.pageHeight
                            // Include partly visible pages during drags/settling; never remove
                            // pages from the Row, which would change swipe geometry.
                            animationsActive: dashboardMotion.presentationActive && viewport.pageIsVisible(idlePage)
                            Binding on metrics {
                                when: idlePage.animationsActive
                                value: root.metrics
                                restoreMode: Binding.RestoreNone
                            }
                            metricsHealthy: root.metricsHealthy
                            now: systemClock.date
                            lightingMode: root.lightingMode
                            lightingHealthy: root.lightingHealthy
                            lightingPending: root.lightingPending
                            lightingError: root.lightingError
                            onLightingModeRequested: mode => root.setLightingMode(mode)
                            coolingMode: root.coolingMode
                            coolingHealthy: root.coolingHealthy
                            coolingPending: root.coolingPending
                            coolingError: root.coolingError
                            onCoolingModeRequested: mode => root.setCoolingMode(mode)
                        }

                        Pages.WorkPage {
                            id: workPage
                            width: viewport.pageWidth
                            height: viewport.pageHeight
                            readonly property bool presentationActive: dashboardMotion.presentationActive && viewport.pageIsVisible(workPage)
                            Binding on metrics {
                                when: workPage.presentationActive
                                value: root.metrics
                                restoreMode: Binding.RestoreNone
                            }
                            metricsHealthy: root.metricsHealthy
                        }

                        Pages.AiFocusPage {
                            id: aiPage
                            width: viewport.pageWidth
                            height: viewport.pageHeight
                            readonly property bool presentationActive: dashboardMotion.presentationActive && viewport.pageIsVisible(aiPage)
                            Binding on metrics {
                                when: aiPage.presentationActive
                                value: root.metrics
                                restoreMode: Binding.RestoreNone
                            }
                            metricsHealthy: root.metricsHealthy
                        }
                    }

                    DragHandler {
                        id: swipeHandler
                        enabled: dashboardMotion.interactive && !Components.TomatService.pickerOpen
                            && !Components.TomatService.scrubbing
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
                        width: 44 + root.modeNames.length * 36
                        height: 28
                        radius: 14
                        z: 20
                        color: Components.Theme.surface
                        border.color: Components.Theme.border

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
                                    Accessible.role: Accessible.Button
                                    Accessible.name: modelData
                                    Accessible.onPressAction: root.currentMode = index

                                    Rectangle {
                                        visible: index !== 0
                                        anchors.centerIn: parent
                                        width: index === root.currentMode ? 18 : 8
                                        height: 8
                                        radius: 4
                                        color: index === root.currentMode ? Components.Theme.mauve : Components.Theme.muted

                                        Behavior on width {
                                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                        }

                                        Behavior on color { ColorAnimation { duration: 140 } }
                                    }

                                    Components.ThemeIcon {
                                        visible: index === 0
                                        anchors.centerIn: parent
                                        name: "processor"
                                        width: 20
                                        height: 20
                                        color: index === root.currentMode ? Components.Theme.mauve : Components.Theme.muted
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
                                color: Components.Theme.border
                            }

                            Rectangle {
                                width: 28
                                height: 24
                                color: "transparent"

                                Components.ThemeIcon {
                                    anchors.centerIn: parent
                                    name: "chevron-down"
                                    color: Components.Theme.mauve
                                    width: 20
                                    height: 20
                                }

                                TapHandler {
                                    onTapped: root.dashboardCollapsed = true
                                }
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
                    color: Components.Theme.surface
                    border.color: Components.Theme.border

                    Components.ThemeIcon {
                        anchors.centerIn: parent
                        name: "chevron-up"
                        color: Components.Theme.mauve
                        width: 20
                        height: 20
                    }

                    TapHandler {
                        onTapped: root.dashboardCollapsed = false
                    }
                }
            }
        }
    }
}
