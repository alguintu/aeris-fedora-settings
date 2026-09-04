import QtQuick
import QtQuick.Window
import Quickshell
import "components" as Components

ShellRoot {
    function check(ok, message) {
        if (!ok) {
            console.error("CHROMATIC_TIME_TEST_FAILED: " + message)
            Qt.exit(1)
        }
    }
    Window {
        visible: true
        width: 440; height: 207
        Components.DashboardTile {
            id: tile
            anchors.fill: parent
            Item {
                anchors.fill: parent
                Components.ChromaticTime {
                    id: hour
                    anchors.left: parent.left; anchors.top: parent.top
                    height: 84; text: "06"
                }
                Components.ChromaticTime {
                    id: minute
                    anchors.left: parent.left; anchors.bottom: parent.bottom
                    height: 84; text: "48"
                }
                Text {
                    id: period
                    anchors.left: minute.right; anchors.leftMargin: 12
                    anchors.baseline: minute.baseline
                    text: "PM"; color: Components.Theme.green
                    font.family: Components.Theme.clockBoldFontFamily
                    font.pixelSize: 36; font.weight: Font.Bold
                }
                Text {
                    id: original
                    visible: false
                    text: minute.text
                    height: minute.height
                    font: minute.font
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
    Timer {
        interval: 500; running: true
        onTriggered: {
            if (Quickshell.env("AERIS_TEST_RHI")) {
                const expected = Quickshell.env("AERIS_TEST_RHI") === "vulkan"
                    ? GraphicsInfo.Vulkan : GraphicsInfo.OpenGL
                check(hour.GraphicsInfo.api === expected, "requested hardware renderer")
                check(hour.blendStatus !== ShaderEffect.Error && minute.blendStatus !== ShaderEffect.Error,
                      "clock shader loads")
            }
            check(hour.color.a === 0 && minute.color.a === 0, "no visible white face")
            check(hour.companionFont.status === FontLoader.Ready, "bundled companion font loads")
            check(hour.companionFont.name !== hour.font.family, "two distinct font families")
            check(hour.width > 90 && hour.width === minute.width, "equal-width stacked digits")
            check(hour.x === minute.x && minute.y >= hour.height, "retain stacked geometry")
            check(minute.width === original.width && minute.baselineOffset === original.baselineOffset,
                  "same geometry as original plain clock")
            check(Math.abs(period.y + period.baselineOffset - minute.y - minute.baselineOffset) < 0.1,
                  "period aligned to minute baseline")
            const width = minute.width
            for (let n = 0; n < 60; n++) {
                minute.text = String(n).padStart(2, "0")
                check(minute.width === width, "no width jump at minute " + n)
            }
            minute.text = "48"
            const output = Quickshell.env("AERIS_CLOCK_TEST_IMAGE")
            if (output) {
                tile.grabToImage(result => {
                    check(result.saveToFile(output), "save preview")
                    console.info("CHROMATIC_TIME_TEST_PASSED")
                    Qt.quit()
                })
            } else {
                console.info("CHROMATIC_TIME_TEST_PASSED")
                Qt.quit()
            }
        }
    }
}
