import QtQuick
import QtQuick.Effects
import Quickshell.Widgets

ClippingRectangle {
    id: root
    // Feed this the same condition as the foreground icon when weather is wired.
    property string condition: "partly-cloudy"
    readonly property var patterns: ({
        "partly-cloudy": "weather-clouds",
        "cloudy": "weather-clouds"
    })
    color: "transparent"
    radius: Theme.radius

    Image {
        id: pattern
        anchors.fill: parent
        source: root.patterns[root.condition]
            ? "../assets/custom/" + root.patterns[root.condition] + ".svg" : ""
        sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)
        sourceSize.height: Math.ceil(height * Screen.devicePixelRatio)
        fillMode: Image.Stretch
        visible: false
    }

    MultiEffect {
        anchors.fill: pattern
        source: pattern
        blurEnabled: true
        blurMax: 24
        blur: 0.65
    }
}
