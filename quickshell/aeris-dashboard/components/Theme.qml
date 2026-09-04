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
