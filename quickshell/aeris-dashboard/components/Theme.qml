pragma Singleton
import QtQuick

QtObject {
    readonly property color surface: "#2e3440"
    readonly property color raised: "#3b4252"
    readonly property color inset: "#4c566a"
    readonly property color border: "#434c5e"
    readonly property color text: "#e5e9f0"
    readonly property color muted: "#a7adba"
    readonly property color inactive: "#727d90"
    readonly property color blue: "#81a1c1"
    readonly property color cyan: "#88c0d0"
    readonly property color teal: "#8fbcbb"
    readonly property color green: "#a3be8c"
    readonly property color yellow: "#ebcb8b"
    readonly property color orange: "#d08770"
    readonly property color red: "#bf616a"
    readonly property color mauve: "#b48ead"
    readonly property color heatIdle: "#3b5059"
    readonly property real radius: 12
    readonly property real controlTint: 0.24

    // Layout contract: ../DESIGN.md. Logical pixels at the 1920×480 target.
    // Keep semantic roles separate even when their current values match.
    readonly property int pageGutter: 14
    readonly property int pageTopInset: 14
    readonly property int pageBottomInset: 42
    readonly property int tileGap: 12
    readonly property int gridContentInset: 12
    readonly property int spacingUnit: 6
    readonly property int gridHeaderHeight: 30
    readonly property int tilePadding: 18
    readonly property int mediaPadding: 24
    readonly property int compactTilePadding: 14
    readonly property int headerBodyGap: 10
    readonly property int primaryTileWidth: 540
    readonly property int pomodoroTileWidth: 296
    readonly property int sectionTitleSize: 20
    readonly property int headerDetailSize: 18
    readonly property int headerIconSize: 26

    function tintedSurface(accent, strength) {
        return Qt.tint(surface, Qt.rgba(accent.r, accent.g, accent.b, strength))
    }

    readonly property string fontFamily: dashboardFont.name || "Noto Sans Mono"
    readonly property string clockFontFamily: clockFont.name || fontFamily
    readonly property string clockBoldFontFamily: clockBoldFont.name || clockFontFamily
    property FontLoader clockBoldFont: FontLoader {
        source: "../assets/fonts/IosevkaNerdFont-Bold.ttf"
    }
    property FontLoader clockFont: FontLoader {
        source: "../assets/fonts/iosevka-nerd-font.ttf"
    }
    property FontLoader dashboardFont: FontLoader {
        source: "../assets/fonts/ShareTechMono-Regular.ttf"
    }
}
