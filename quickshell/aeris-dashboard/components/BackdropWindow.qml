import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    // Track the visible part of SlideReveal, not its offscreen content.
    property real backdropOffset: 0
    property bool backdropHidden: false
    readonly property int backdropTop: Math.round(Math.max(0, Math.min(height, backdropOffset)))
    readonly property bool backdropActive: !backdropHidden && backdropTop < height
    readonly property var activeBlurRegion: BackgroundEffect.blurRegion

    color: "transparent"
    BackgroundEffect.blurRegion: backdropActive ? backdropRegion : null

    Region {
        id: backdropRegion
        x: 0
        y: root.backdropTop
        width: root.width
        height: Math.max(0, root.height - root.backdropTop)
    }
}
