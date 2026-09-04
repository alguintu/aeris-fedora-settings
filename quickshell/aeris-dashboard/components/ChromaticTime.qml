import QtQuick

// Original clock metrics, with three cached glyph masks as RGB channels.
Text {
    id: root
    color: "transparent"
    font.family: Theme.clockBoldFontFamily
    font.pixelSize: 100
    font.weight: Font.Bold
    verticalAlignment: Text.AlignVCenter

    readonly property real fringePadding: 12
    readonly property int blendStatus: blend.status
    property FontLoader companionFont: FontLoader {
        source: "../assets/fonts/NotoSans-CondensedBold.ttf"
    }

    component GlyphMask: ShaderEffectSource {
        id: mask
        property bool alternate: false
        property real offsetX: 0
        property real offsetY: 0
        visible: false
        hideSource: true
        // Refresh only when source text/font/geometry changes, not every frame.
        live: true
        recursive: false
        sourceRect: Qt.rect(-root.fringePadding, -root.fringePadding,
                            root.width + root.fringePadding * 2,
                            root.height + root.fringePadding * 2)
        sourceItem: Item {
            width: root.width
            height: root.height
            Repeater {
                model: root.text.length
                Item {
                    id: digitCell
                    required property int index
                    readonly property string digit: root.text.charAt(index)
                    x: index * root.implicitWidth / Math.max(1, root.text.length)
                    TextMetrics {
                        id: originalInk
                        text: digitCell.digit
                        font: root.font
                    }
                    TextMetrics {
                        id: companionInk
                        text: digitCell.digit
                        font: glyph.font
                    }
                    Text {
                        id: glyph
                        readonly property real fitX: mask.alternate
                            ? originalInk.tightBoundingRect.width / Math.max(1, companionInk.tightBoundingRect.width) : 1
                        readonly property real fitY: mask.alternate
                            ? originalInk.tightBoundingRect.height / Math.max(1, companionInk.tightBoundingRect.height) : 1
                        text: digitCell.digit
                        color: "white"
                        // Register each numeral's ink bounds, not the whole string.
                        // Preserve Iosevka unchanged; fit its upright companion to it.
                        x: originalInk.tightBoundingRect.x
                            - companionInk.tightBoundingRect.x * fitX + mask.offsetX
                        y: root.baselineOffset + originalInk.tightBoundingRect.y
                            - (baselineOffset + companionInk.tightBoundingRect.y) * fitY + mask.offsetY
                        font.family: mask.alternate ? root.companionFont.name : Theme.clockBoldFontFamily
                        font.pixelSize: root.font.pixelSize
                        font.weight: Font.Bold
                        font.italic: false
                        transform: Scale { xScale: glyph.fitX; yScale: glyph.fitY }
                        Accessible.ignored: true
                    }
                }
            }
        }
    }

    GlyphMask { id: red; offsetX: 1; offsetY: 1 }
    GlyphMask { id: green; alternate: true; offsetX: 2; offsetY: -1 }
    GlyphMask { id: blue; offsetX: -1 }

    ShaderEffect {
        id: blend
        x: -root.fringePadding
        y: -root.fringePadding
        width: root.width + root.fringePadding * 2
        height: root.height + root.fringePadding * 2
        property var redMask: red
        property var greenMask: green
        property var blueMask: blue
        fragmentShader: "../shaders/chromatic-time.frag.qsb"
        onStatusChanged: if (status === ShaderEffect.Error) console.warn("Clock color blend:", log)
    }
}
