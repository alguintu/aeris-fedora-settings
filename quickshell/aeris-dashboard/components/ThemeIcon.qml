import QtQuick
import QtQuick.Effects

Item {
    id: root
    property string name: "music-note"
    property color color: Theme.text
    // Semantic names keep callers independent of the two vendored icon sets.
    readonly property var iconPaths: ({
        "aeris": "custom/aeris",
        "aeris-wordmark": "custom/aeris-wordmark",
        "timer": "icons/timer-outline",
        "weather-partly-cloudy": "icons/weather-partly-cloudy",
        "weather-cloudy": "icons/weather-cloudy",
        "weather-night-partly-cloudy": "icons/weather-night-partly-cloudy",
        "weather-fog": "icons/weather-fog",
        "weather-rainy": "icons/weather-rainy",
        "weather-snowy": "icons/weather-snowy",
        "weather-lightning-rainy": "icons/weather-lightning-rainy",
        "reset": "feather/rotate-ccw",
        "processor": "icons/memory",
        "graphics-card": "icons/expansion-card",
        "desktop-tower": "icons/desktop-tower",
        "reference-moon": "feather/moon",
        "moon-waning-crescent": "feather/moon",
        "white-balance-sunny": "feather/sun",
        "power": "feather/power",
        "lights-off": "icons/lightbulb-off-outline",
        "aurora": "icons/aurora",
        "coffee": "feather/coffee",
        "weather-windy": "feather/wind",
        "lightning-bolt": "feather/zap",
        "chip": "feather/cpu",
        "music-note": "feather/music",
        "chevron-down": "feather/chevron-down",
        "chevron-up": "feather/chevron-up",
        "pie-chart": "feather/pie-chart",
        "battery": "feather/battery",
        "terminal": "feather/terminal",
        "code": "feather/code",
        "folder": "feather/folder",
        "globe": "feather/globe",
        "fan": "icons/fan",
        "star-four-points": "icons/star-four-points",
        "play": "icons/play",
        "pause": "icons/pause",
        "skip-previous": "icons/skip-previous",
        "skip-next": "icons/skip-next",
        "harddisk": "icons/harddisk",
        "harddisk-tight": "icons/harddisk-tight"
    })
    implicitWidth: 48
    implicitHeight: 48

    Image {
        id: artwork
        anchors.fill: parent
        source: "../assets/" + (root.iconPaths[root.name] || "feather/music") + ".svg"
        sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)
        sourceSize.height: Math.ceil(height * Screen.devicePixelRatio)
        fillMode: Image.PreserveAspectFit
        visible: false
    }

    MultiEffect {
        anchors.fill: artwork
        source: artwork
        colorization: 1
        colorizationColor: root.color
    }
}
