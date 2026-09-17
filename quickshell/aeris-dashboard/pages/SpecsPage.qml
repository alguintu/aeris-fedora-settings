import QtQuick
import QtQuick.Layouts
import "../components"

// Curated 2026-09-04 build snapshot, not live telemetry. See settings/pc-specs.md.
Item {
    id: page
    property bool presentationActive: true
    readonly property var cards: [
        { label: "PROCESSOR", icon: "processor", accent: Theme.blue,
          value: "Ryzen 9 5950X", lines: ["16 cores / 32 threads · 64 MB L3", "3.4 GHz base · 4.9 GHz boost"] },
        { label: "GRAPHICS", icon: "graphics-card", accent: Theme.green,
          value: "Radeon RX 6900 XT", lines: ["ASUS TUF Gaming OC", "16 GB VRAM · 80 CU"] },
        { label: "MEMORY", icon: "chip", accent: Theme.mauve,
          value: "64 GB PNY DDR4", lines: ["4 × 16GB DDR4 DIMMs", "PNY XLR8 EPIC-X RGB", "3200 MTs"] },
        { label: "CHASSIS", icon: "desktop-tower", accent: Theme.cyan,
          value: "DeepCool CH260", lines: ["Grand Vision 360 White AIO", "MSI MAG A850GL PCIE5 · 850 W", "OpenRGB + CoolerControl"] },
        { label: "MOTHERBOARD", icon: "processor", accent: Theme.teal,
          value: "B550M MORTAR WIFI", lines: ["MSI MAG · AM4 · MS-7C94", "BIOS 1.O1"] },
        { label: "STORAGE", icon: "harddisk", accent: Theme.yellow,
          value: "2 NVMe · 3 SATA", lines: ["1TB 990 PRO · 512GB NM620", "1TB 860 EVO · 500GB BarraCuda", "4TB IronWolf HDD"] },
        { label: "SYSTEM", icon: "terminal", accent: Theme.orange,
          value: "Fedora Linux 44", lines: ["KDE Plasma 6.7.4 · x86_64", "Linux 7.1.12-200.fc44.x86_64"] }
    ]

    SpecsGrid { id: specsGrid; anchors.fill: parent }
    readonly property alias layoutGrid: specsGrid

    GridTile {
        id: identityCard
        grid: specsGrid
        slotName: "identity"
        Accessible.role: Accessible.Button
        Accessible.name: "Aeris animation: " + caseBackdrop.backdropAnimationName
        Accessible.description: "Activate to show the next pixel animation"
        Accessible.onPressAction: caseBackdrop.nextBackdropAnimation()

        TapHandler {
            // Cover the whole tile, including its inset, but yield to page drags.
            parent: identityCard
            enabled: page.presentationActive
            gesturePolicy: TapHandler.DragThreshold
            onTapped: caseBackdrop.nextBackdropAnimation()
        }

        ChromaticPulse {
            id: caseBackdrop
            objectName: "specs-case-backdrop"
            anchors.fill: parent
            backdropMode: true
            running: page.presentationActive
        }

        Row {
            spacing: 2 * Theme.spacingUnit
            ThemeIcon { name: "processor"; width: 24; height: 24; color: Theme.blue }
            Text { text: "PC SPECS"; color: Theme.blue; font.family: Theme.fontFamily; font.pixelSize: 22 }
        }

        Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: 4 * Theme.spacingUnit
            ThemeIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "aeris-wordmark"
                width: Math.min(240, parent.width)
                height: width * 64 / 240
                color: Theme.teal
            }
            Text {
                width: parent.width
                text: "WORKSTATION"
                horizontalAlignment: Text.AlignHCenter
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 20
            }
        }

        Column {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            spacing: Theme.spacingUnit
            Text { text: "BUILD SNAPSHOT"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 18 }
            Text { text: "04 SEP 2026"; color: Theme.blue; font.family: Theme.fontFamily; font.pixelSize: 20 }
        }
    }

    Repeater {
        model: page.cards
        delegate: GridTile {
            required property var modelData
            grid: specsGrid
            slotName: modelData.label.toLowerCase()

            Column {
                anchors.fill: parent
                spacing: 2 * Theme.spacingUnit

                Row {
                    spacing: 2 * Theme.spacingUnit
                    ThemeIcon { name: modelData.icon; color: modelData.accent; width: 24; height: 24 }
                    Text {
                        text: modelData.label
                        color: modelData.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                    }
                }
                Text {
                    width: parent.width
                    text: modelData.value
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 32
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Column {
                    width: parent.width
                    spacing: Theme.spacingUnit
                    Repeater {
                        model: modelData.lines
                        delegate: Text {
                            required property string modelData
                            width: parent.width
                            text: modelData
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 20
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    Repeater {
        model: [
            {key: "fans", icon: "fan", accent: Theme.red, label: "THERMALRIGHT FANS",
             details: "EXHAUST · 3 RAD · 2 GPU\nINTAKE · 1 REAR · 2 FRONT"},
            {key: "argb", icon: "aurora", accent: Theme.mauve, label: "ARGB ZONES",
             details: "BACKPLANE + PSU · FANS\nDRAM · GPU"}
        ]
        delegate: GridTile {
            required property var modelData
            grid: specsGrid
            slotName: modelData.key

            Item {
                anchors.fill: parent
                ThemeIcon {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    name: modelData.icon
                    color: modelData.accent
                    width: 24; height: 24
                }
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 24 + Theme.spacingUnit
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: Theme.spacingUnit
                    Text {
                        width: parent.width
                        text: modelData.label
                        color: modelData.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                    }
                    Text {
                        width: parent.width
                        text: modelData.details
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                    }
                }
            }
        }
    }
}
