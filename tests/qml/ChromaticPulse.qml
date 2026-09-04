import QtQuick
import QtQuick.Window
import Quickshell
import "components" as Components

ShellRoot {
    property int step: 0
    function check(ok, message) {
        if (!ok) {
            console.error("CHROMATIC_PULSE_TEST_FAILED: " + message)
            Qt.exit(1)
        }
    }
    Window {
        id: window
        visible: true
        width: 260; height: 260
        color: Components.Theme.inset
        Rectangle { anchors.fill: parent; color: Components.Theme.inset }
        Components.ChromaticPulse { id: pulse; anchors.fill: parent; anchors.margins: 1; running: true }
    }
    Timer {
        interval: 120; repeat: true; running: true
        onTriggered: {
            step++
            if (step === 1) {
                check(pulse.animationRegistered, "visible pulse registers")
                check(Components.DecorativeClock.users === 1, "one animation registration")
                if (Quickshell.env("AERIS_TEST_RHI"))
                    check(pulse.blendStatus !== ShaderEffect.Error, "media wave shader loads")
                pulse.elapsed = 19992
                Components.DecorativeClock.tick(16)
                check(pulse.elapsed === 20008, "shared clock advances without a phase reset")
                pulse.pixelMode = true
            } else if (step === 2) {
                check(!pulse.animationRegistered, "static pixel mode detaches")
                check(Components.DecorativeClock.users === 0, "pixel mode releases animation registration")
            } else if (step === 4) {
                const output = Quickshell.env("AERIS_PULSE_TEST_IMAGE")
                if (output) window.contentItem.grabToImage(result => {
                    check(result.saveToFile(output), "save wave preview")
                    console.info("CHROMATIC_PULSE_TEST_PASSED")
                    Qt.quit()
                })
                else {
                    console.info("CHROMATIC_PULSE_TEST_PASSED")
                    Qt.quit()
                }
            }
        }
    }
}
