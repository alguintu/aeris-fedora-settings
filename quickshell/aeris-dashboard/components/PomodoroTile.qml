import QtQuick
import Quickshell.Widgets
import QtQuick.Controls as Controls

// Reusable presentation of the shared Tomat daemon, never a local timer.
Item {
    id: root
    readonly property int stageCount: TomatService.state.sessions
    readonly property int currentStage: Math.min(stageCount - 1, TomatService.state.session - 1)
    readonly property string stageLabel: !TomatService.healthy ? "OFFLINE"
        : TomatService.state.stageLabel ? TomatService.state.stageLabel
        : TomatService.state.phase === "Break" ? "SHORT BREAK"
        : TomatService.state.phase === "LongBreak" ? "LONG BREAK" : "WORK"
    readonly property real progress: TomatService.state.progress
    readonly property color phaseColor: TomatService.state.phase === "Work" || TomatService.idle
        ? Theme.mauve : Theme.green
    onProgressChanged: dial.requestPaint()
    onPhaseColorChanged: dial.requestPaint()

    ClippingRectangle {
        anchors.fill: parent
        anchors.margins: -18
        radius: Theme.radius
        color: "transparent"

        Canvas {
            id: dial
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.scale(width / 296, height / 424)

                const cx = 24, cy = 180, radius = 158
                ctx.strokeStyle = Theme.border
                ctx.lineWidth = 7
                ctx.beginPath()
                ctx.arc(cx, cy, radius, 0, Math.PI * 2)
                ctx.stroke()

                // Map the phase to the visible half of the cropped dial.
                const endAngle = -Math.PI / 2 + root.progress * Math.PI
                ctx.strokeStyle = root.phaseColor
                ctx.lineWidth = 7
                ctx.lineCap = "round"
                ctx.beginPath()
                ctx.arc(cx, cy, radius, -Math.PI / 2, endAngle)
                ctx.stroke()

                ctx.lineCap = "butt"
                for (let i = 0; i < 72; ++i) {
                    const angle = -Math.PI / 2 + i * Math.PI / 36
                    const outer = radius - 14, inner = radius - (i % 3 === 0 ? 25 : 20)
                    ctx.strokeStyle = i < root.progress * 36 ? root.phaseColor : Theme.inset
                    ctx.lineWidth = i % 3 === 0 ? 2 : 1
                    ctx.beginPath()
                    ctx.moveTo(cx + Math.cos(angle) * inner, cy + Math.sin(angle) * inner)
                    ctx.lineTo(cx + Math.cos(angle) * outer, cy + Math.sin(angle) * outer)
                    ctx.stroke()
                }
                ctx.fillStyle = Theme.yellow
                ctx.beginPath()
                ctx.arc(cx + Math.cos(endAngle) * radius, cy + Math.sin(endAngle) * radius, 6, 0, Math.PI * 2)
                ctx.fill()
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            // The clipping frame begins 18px before the content area.
            y: Math.max(0, quoteBlock.y + 18 - 140)
            height: parent.height - y
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.15; color: "#03000000" }
                GradientStop { position: 0.35; color: "#10000000" }
                GradientStop { position: 0.60; color: "#2c000000" }
                GradientStop { position: 0.82; color: "#42000000" }
                GradientStop { position: 1; color: "#48000000" }
            }
        }
    }

    Column {
        id: stageHeader
        anchors.top: parent.top
        anchors.right: parent.right
        width: 122
        spacing: 12

        Row {
            id: stageDots
            anchors.right: parent.right
            readonly property real dotSize: Math.min(10, 122 / (root.stageCount * 2 - 1))
            spacing: dotSize

            Repeater {
                model: root.stageCount
                delegate: Rectangle {
                    required property int index
                    width: stageDots.dotSize
                    height: width
                    radius: width / 2
                    color: index === root.currentStage ? root.phaseColor : "transparent"
                    border.width: 1.5
                    border.color: index === root.currentStage ? root.phaseColor : Theme.inactive
                }
            }
        }

        Text {
            width: parent.width
            text: root.stageLabel
            horizontalAlignment: Text.AlignRight
            color: Theme.teal
            font.family: Theme.fontFamily
            font.pixelSize: 18
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }

    Item {
        anchors.top: stageHeader.top
        anchors.right: stageHeader.right
        width: 150
        height: Math.max(52, stageHeader.height)
        Accessible.role: Accessible.Button
        Accessible.name: "Choose timer routine"
        Accessible.onPressAction: TomatService.pickerOpen = true
        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            grabPermissions: PointerHandler.TakeOverForbidden
            onTapped: TomatService.pickerOpen = true
        }
        Controls.ToolTip.visible: stageHover.hovered
        Controls.ToolTip.text: "Choose routine · " + (TomatService.state.activeName || TomatService.state.selectedName || "Tomat")
        HoverHandler { id: stageHover }
    }

    Text {
        id: countdown
        anchors.left: parent.left
        y: parent.height * 0.29
        text: TomatService.healthy ? String(Math.floor(TomatService.state.remaining / 60)).padStart(2, "0")
            + ":" + String(TomatService.state.remaining % 60).padStart(2, "0") : "--:--"
        color: Theme.text
        font.family: Theme.clockBoldFontFamily
        font.weight: Font.Bold
        font.pixelSize: 48
    }

    Text {
        id: countdownStatus
        anchors.left: countdown.left
        anchors.top: countdown.bottom
        anchors.topMargin: 2
        text: !TomatService.healthy ? "UNAVAILABLE" : TomatService.pending ? "UPDATING"
            : TomatService.idle ? "READY" : TomatService.state.paused ? "PAUSED" : "REMAINING"
        font.family: Theme.fontFamily
        font.pixelSize: 13
        color: Theme.muted
    }

    Item {
        id: quoteBlock
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: timerControls.top
        anchors.bottomMargin: 18
        height: quoteContent.height

        Column {
            id: quoteContent
            width: parent.width
            spacing: 12

            Text {
                width: parent.width
                text: TomatService.state.quote || "Nothing lasts. Make it count."
                maximumLineCount: 4
                elide: Text.ElideRight
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignRight
                color: Theme.yellow
                font.family: Theme.fontFamily
                font.pixelSize: 24
                lineHeight: 1.05
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: "— AERIS"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
        }
    }

    Row {
        id: timerControls
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        spacing: 18

        Repeater {
            model: ["reset", "play", "skip-next"]
            delegate: Rectangle {
                id: control
                required property string modelData
                readonly property bool usable: TomatService.healthy && !TomatService.pending
                    && (modelData === "play" || !TomatService.idle)
                readonly property string action: modelData === "play" ? "toggle"
                    : modelData === "reset" ? "reset" : "skip"
                width: 52
                height: 52
                radius: 26
                color: modelData === "play" ? Theme.green : "transparent"
                opacity: usable ? (tap.pressed ? 0.7 : 1) : 0.4
                Accessible.role: Accessible.Button
                Accessible.name: modelData === "reset" ? "Reset session" : modelData === "skip-next"
                    ? "Skip stage" : TomatService.idle ? "Start" : TomatService.state.paused ? "Resume" : "Pause"
                Accessible.onPressAction: TomatService.send(control.action)
                Controls.ToolTip.visible: hover.hovered
                Controls.ToolTip.text: TomatService.commandError || TomatService.errorText || Accessible.name
                HoverHandler { id: hover }
                TapHandler {
                    id: tap
                    enabled: control.usable
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    grabPermissions: PointerHandler.TakeOverForbidden
                    onTapped: TomatService.send(control.action)
                }

                ThemeIcon {
                    anchors.centerIn: parent
                    width: parent.modelData === "play" ? 34 : 30
                    height: width
                    name: parent.modelData === "play" && !TomatService.idle && !TomatService.state.paused
                        ? "pause" : parent.modelData
                    color: parent.modelData === "play" ? Theme.surface : Theme.yellow
                }
            }
        }
    }

    RoutinePicker {
        anchors.fill: parent
        anchors.margins: -18
        visible: TomatService.pickerOpen
        z: 20
    }
}
