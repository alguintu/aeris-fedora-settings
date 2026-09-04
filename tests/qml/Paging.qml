import QtQuick
import QtQuick.Window
import Quickshell
import "components" as Components

ShellRoot {
    id: root
    property int step: 0
    function check(ok, message) {
        if (!ok) {
            console.error("PAGING_TEST_FAILED: " + message)
            Qt.exit(1)
        }
    }
    function screenX(page) { return page.mapToItem(viewport, 0, 0).x }

    Window {
        id: screen
        visible: true
        width: 1920; height: 480
        Components.PageViewport {
            id: viewport
            anchors.fill: parent
            pageIndex: 1
            dragging: true
            Repeater {
                id: pages
                model: 4
                delegate: Rectangle {
                    required property int index
                    width: viewport.pageWidth; height: viewport.pageHeight
                    color: ["red", "green", "blue", "yellow"][index]
                }
            }
        }
    }

    Timer {
        interval: 350; repeat: true; running: true
        onTriggered: {
            if (root.step++ === 0) {
                root.check(viewport.x === 0 && viewport.y === 0
                    && viewport.width === screen.width && viewport.height === screen.height
                    && viewport.clip, "only the full-screen viewport clips the strip")
                root.check(viewport.pageWidth === 1892 && viewport.pageHeight === 424,
                           "resting widget dimensions must not change")
                for (let index = 0; index < 4; index++) {
                    viewport.pageIndex = index
                    const page = pages.itemAt(index)
                    root.check(root.screenX(page) === 14, "every settled page retains its left margin")
                    root.check(page.mapToItem(viewport, 0, 0).y === 14, "retain the top margin")
                    root.check(!page.clip && !page.parent.clip, "no individual page/track clipping")
                    for (let other = 0; other < 4; other++)
                        root.check(viewport.pageIsVisible(pages.itemAt(other)) === (other === index),
                                   "only the settled page is presentation-active")
                }
                viewport.pageIndex = 1
                for (const offset of [-1892, -960, -14, 14, 960, 1892]) {
                    viewport.dragOffset = offset
                    for (let index = 0; index < 3; index++)
                        root.check(root.screenX(pages.itemAt(index + 1))
                            - root.screenX(pages.itemAt(index)) - viewport.pageWidth === 28,
                            "neighboring contents keep both 14px gutters during a drag")
                    for (let index = 0; index < 4; index++) {
                        const page = pages.itemAt(index)
                        const x = root.screenX(page)
                        root.check(viewport.pageIsVisible(page) === (x < screen.width && x + page.width > 0),
                                   "partially visible pages animate until they leave the screen")
                    }
                }
                viewport.dragOffset = 0
                root.check(root.screenX(pages.itemAt(1)) === 14, "cancel returns to the same margin")
                viewport.dragging = false
                viewport.pageIndex = 2
            } else if (root.step === 2) {
                root.check(Math.abs(root.screenX(pages.itemAt(2)) - 14) < 0.01,
                           "settling lands on the full-screen page stride")
                viewport.dragging = true
                screen.width = 1600
            } else {
                root.check(viewport.pageWidth === 1572, "resize preserves per-page gutters")
                root.check(root.screenX(pages.itemAt(2)) === 14, "resize keeps selected page aligned")
                viewport.visible = false
                root.check(!viewport.pageIsVisible(pages.itemAt(2)), "collapsed viewport suspends presentation")
                console.info("PAGING_TEST_PASSED")
                Qt.quit()
            }
        }
    }
}
