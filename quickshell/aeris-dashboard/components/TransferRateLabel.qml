import QtQuick

DashboardHeaderLabel {
    property var bytesPerSecond: null
    property string direction: ""
    readonly property string formattedRate: formatRate(bytesPerSecond)
    text: direction + formattedRate

    function formatRate(bytes) {
        if (bytes === null || bytes === undefined || !Number.isFinite(Number(bytes)) || Number(bytes) < 0)
            return "—"
        // Decimal byte units for the compact readout; no telemetry work here.
        let value = Number(bytes) / 1000
        const units = ["KBs", "MBs", "GBs", "TBs", "PBs", "EBs"]
        let unit = 0
        while (value >= 999.5 && unit < units.length - 1) { value /= 1000; ++unit }
        const decimals = value > 0 && value < 99.95 ? 1 : 0
        return value.toFixed(decimals) + units[unit]
    }
}
