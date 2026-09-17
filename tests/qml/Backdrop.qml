import QtQuick
import Quickshell
import "components" as Components

ShellRoot {
    function check(ok, message) {
        if (!ok) {
            console.error("BACKDROP_TEST_FAILED: " + message)
            Qt.exit(1)
        }
    }

    Components.BackdropWindow {
        id: backdrop
        visible: false
        implicitWidth: 400
        implicitHeight: 100
    }

    Timer {
        interval: 100; running: true
        onTriggered: {
            check(backdrop.color.a === 0, "no wallpaper replacement or dimming fill")
            check(backdrop.activeBlurRegion !== null, "open backdrop requests compositor blur")
            check(backdrop.activeBlurRegion.y === 0, "blur starts at top")
            check(backdrop.activeBlurRegion.height === backdrop.height, "blur fills window")
            backdrop.backdropOffset = 40
            check(backdrop.activeBlurRegion.y === 40, "blur follows slide")
            check(backdrop.activeBlurRegion.height === backdrop.height - 40, "uncovered area is not blurred")
            backdrop.backdropOffset = backdrop.height
            check(backdrop.activeBlurRegion === null, "fully slid out disables blur")
            backdrop.backdropOffset = 0
            backdrop.backdropHidden = true
            check(backdrop.activeBlurRegion === null, "hidden dashboard disables blur")
            backdrop.backdropHidden = false
            check(backdrop.activeBlurRegion !== null, "restoring enables blur")
            console.info("BACKDROP_TEST_PASSED")
            Qt.quit()
        }
    }
}
