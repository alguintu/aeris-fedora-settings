// Short-lived, user-requested window action. Never changes placement or rules.
const replyTo = __DESTINATION__;
const restore = __RESTORE__;
const window = workspace.windowList().find(w => w.normalWindow && (
    String(w.desktopFileName).toLowerCase() === "org.freedownloadmanager.manager"
    || String(w.resourceClass).toLowerCase() === "fdm"));
if (window && restore) {
    window.minimized = false;
    workspace.activeWindow = window;
}
callDBus(replyTo, "/FdmWindow", "org.aeris.FdmWindow", "report", JSON.stringify(
    window ? {found: true, minimized: window.minimized, active: window.active,
        x: window.frameGeometry.x, y: window.frameGeometry.y,
        width: window.frameGeometry.width, height: window.frameGeometry.height}
    : {found: false}));
