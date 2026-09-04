import QtQuick
import QtQuick.Window
import Quickshell
import "pages" as Pages

ShellRoot {
    Window {
        visible: true
        width: 1920
        height: 424
        color: "#202631"
        Pages.SpecsPage { id: specs; anchors.fill: parent }
    }
    Timer {
        interval: 500; running: true
        onTriggered: {
            const output = Quickshell.env("AERIS_SPECS_TEST_IMAGE")
            if (output) specs.grabToImage(result => {
                if (!result.saveToFile(output)) {
                    console.error("SPECS_PAGE_TEST_FAILED: save preview")
                    Qt.exit(1)
                }
                console.info("SPECS_PAGE_TEST_PASSED")
                Qt.quit()
            })
            else {
                console.info("SPECS_PAGE_TEST_PASSED")
                Qt.quit()
            }
        }
    }
}
