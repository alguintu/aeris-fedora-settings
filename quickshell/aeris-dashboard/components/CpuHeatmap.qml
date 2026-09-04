import QtQuick

Item {
    id: root

    property var ccds: []
    property bool animationEnabled: true
    property color idleColor: Theme.heatIdle
    property color tealColor: Theme.teal
    property color orangeColor: Theme.orange
    property color redColor: Theme.red

    function mix(first, second, amount) {
        const t = Math.max(0, Math.min(1, amount))
        return Qt.rgba(first.r + (second.r - first.r) * t,
                       first.g + (second.g - first.g) * t,
                       first.b + (second.b - first.b) * t,
                       first.a + (second.a - first.a) * t)
    }

    function heatColor(value) {
        const load = Math.max(0, Math.min(100, value || 0)) / 100
        if (load < 0.3)
            return mix(idleColor, tealColor, load / 0.3)
        if (load < 0.72)
            return mix(tealColor, orangeColor, (load - 0.3) / 0.42)
        return mix(orangeColor, redColor, (load - 0.72) / 0.28)
    }

    function threadLoad(ccdIndex, coreIndex, threadIndex) {
        if (!ccds || ccdIndex >= ccds.length)
            return 0
        const cores = ccds[ccdIndex]
        if (!cores || coreIndex >= cores.length)
            return 0
        const threads = cores[coreIndex]
        return threads && threadIndex < threads.length ? threads[threadIndex] : 0
    }

    function colors() {
        const result = []
        for (let die = 0; die < 2; ++die)
            for (let core = 0; core < 8; ++core)
                for (let thread = 0; thread < 2; ++thread)
                    result.push(root.heatColor(root.threadLoad(die, core, thread)))
        return result
    }
    HeatmapSurface {
        anchors.fill: parent
        cpuLayout: true
        transitionMs: 340
        animationEnabled: root.animationEnabled
        cellColors: root.colors()
    }
}
