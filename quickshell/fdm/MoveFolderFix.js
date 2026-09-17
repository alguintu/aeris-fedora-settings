.pragma library

// FDM 6.34's native Move picker returns selectedFolder, but its handler reads
// currentFolder. Replace only that dialog in the current bundled main UI.
function patchMain(main, dialog) {
    const marker = "    MovingFolderDialog {\n        id: movingFolderDlg\n    }";
    const remember = "uiSettingsTools.settings.lastMovePath = currentFolder;";
    const move = "App.tools.url(currentFolder).toLocalFile()";
    if (main.split(marker).length !== 2 || dialog.split(remember).length !== 2
            || dialog.split(move).length !== 2) {
        throw new Error("FDM Move dialog changed; workaround not applied");
    }
    const start = dialog.indexOf("FolderDialog {");
    if (start < 0) throw new Error("FDM Move dialog type not found");
    const corrected = dialog.slice(start)
        .replace("FolderDialog {", "NativeDialogs.FolderDialog {\n    id: movingFolderDlg")
        .replace(remember, "uiSettingsTools.settings.lastMovePath = selectedFolder;")
        .replace(move, "App.tools.url(selectedFolder).toLocalFile()");
    return "import QtQuick.Dialogs as NativeDialogs\n" + main.replace(marker, corrected);
}
