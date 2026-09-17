import QtQuick
import org.freedownloadmanager.fdm
import "MoveFolderFix.js" as MoveFolderFix

// Observe FDM's model and correct its native Move-dialog destination.
Item {
    id: bridge
    property var stockUi: null
    // A nonvisual owner keeps the dynamically created Window top-level.
    // Parenting it to this invisible Item prevents its native window appearing.
    property QtObject uiOwner: QtObject {}
    property bool moveFixApplied: false
    function readResource(url) {
        const request = new XMLHttpRequest();
        request.open("GET", url, false);
        request.send();
        if (!request.responseText) throw new Error("FDM UI resource unavailable");
        return request.responseText;
    }
    // FDM's own UI count is maintained by the tracker, independent of filters.
    property var completedCount: Number.isInteger(App.downloads.tracker.finishedDownloadsCount)
        && App.downloads.tracker.finishedDownloadsCount >= 0
        ? App.downloads.tracker.finishedDownloadsCount : null
    function snapshot() {
        const ids = App.downloads.tracker.runningIds()
        const rows = []
        for (const id of ids) {
            const info = App.downloads.infos.info(id)
            if (!info || info.finished || info.parentId > 0) continue
            rows.push({id: String(id), title: String(info.title).slice(0, 240),
                size: Number(info.selectedSize), downloaded: Number(info.selectedBytesDownloaded),
                speed: Number(info.downloadSpeed), running: Boolean(info.running)})
        }
        console.info("AERIS_FDM_STATE " + JSON.stringify({version: 1, downloads: rows,
            completedCount: completedCount}))
    }
    Timer { interval: 1000; running: bridge.stockUi !== null; repeat: true; onTriggered: bridge.snapshot() }
    Component.onCompleted: {
        try {
            const source = MoveFolderFix.patchMain(
                readResource("qrc:/qml_ui/desktop/main.qml"),
                readResource("qrc:/qml_ui/desktop/Dialogs/MovingFolderDialog.qml"));
            stockUi = Qt.createQmlObject(source, uiOwner, "qrc:/qml_ui/desktop/AerisMain.qml");
            moveFixApplied = true;
            console.info("AERIS_FDM_MOVE_FIX applied");
            snapshot();
            return;
        } catch (error) {
            console.warn("AERIS_FDM_MOVE_FIX " + String(error));
        }
        const component = Qt.createComponent("qrc:/qml_ui/desktop/main.qml")
        if (component.status !== Component.Ready) {
            console.error("AERIS_FDM_ERROR " + component.errorString())
            return
        }
        stockUi = component.createObject(null)
        snapshot()
    }
}
