import QtQuick
import QtQuick.Layouts
import "../components"

// Curated 2026-09-04 build snapshot, not live telemetry. See settings/pc-specs.md.
Item {
    id: page
    readonly property var cards: [
        { label: "PROCESSOR", icon: "processor", accent: Theme.blue,
          value: "Ryzen 9 5950X", lines: ["AMD · 16 cores / 32 threads", "2 CCDs · 64 MB L3 cache"] },
        { label: "GRAPHICS", icon: "graphics-card", accent: Theme.green,
          value: "Radeon RX 6900 XT", lines: ["ASUS TUF Gaming OC", "16 GB VRAM · 80 compute units"] },
        { label: "MEMORY", icon: "chip", accent: Theme.mauve,
          value: "64 GB DDR4", lines: ["4 × 16 GB DIMMs", "3200 MT/s · recorded"] },
        { label: "CHASSIS", icon: "desktop-tower", accent: Theme.cyan,
          value: "DeepCool CH260", lines: ["Grand Vision 360 White AIO", "MSI MAG A850GL PCIE5 · 850 W"] },
        { label: "MOTHERBOARD", icon: "processor", accent: Theme.teal,
          value: "B550M MORTAR WIFI", lines: ["MSI MAG · AM4 · MS-7C94", "BIOS 1.O1"] },
        { label: "STORAGE", icon: "harddisk", accent: Theme.yellow,
          value: "5 physical drives", lines: ["990 PRO 1 TB · 860 EVO 1 TB", "BarraCuda 500 GB · IronWolf 4 TB", "Lexar NM620 512 GB · unmounted"] },
        { label: "SYSTEM", icon: "terminal", accent: Theme.orange,
          value: "Fedora Linux 44", lines: ["KDE Plasma 6.7.4 · x86_64", "Linux 7.1.12-200.fc44.x86_64"] },
        { label: "FANS & RGB", icon: "fan", accent: Theme.red,
          value: "8 fans · 4 zones", lines: ["3 rad · 1 rear · 2 front · 2 GPU", "2 ARGB chains · RAM · GPU", "CoolerControl + OpenRGB"] }
    ]

    RowLayout {
        anchors.fill: parent
        spacing: 12

        DashboardTile {
            Layout.preferredWidth: 300
            Layout.fillHeight: true

            Row {
                spacing: 12
                ThemeIcon { name: "processor"; width: 24; height: 24; color: Theme.blue }
                Text { text: "PC SPECS"; color: Theme.blue; font.family: Theme.fontFamily; font.pixelSize: 22 }
            }

            Column {
                anchors.centerIn: parent
                width: parent.width
                spacing: 22
                ThemeIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "aeris-wordmark"
                    width: 240
                    height: 64
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
                spacing: 5
                Text { text: "BUILD SNAPSHOT"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 18 }
                Text { text: "04 SEP 2026"; color: Theme.blue; font.family: Theme.fontFamily; font.pixelSize: 20 }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 4
            columnSpacing: 12
            rowSpacing: 12

            Repeater {
                model: page.cards
                delegate: DashboardTile {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 1

                    Column {
                        anchors.fill: parent
                        spacing: 12

                        Row {
                            spacing: 12
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
                            spacing: 4
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
        }
    }
}
