// Pure color-transition bookkeeping. One small texture replaces per-cell QML animations.
function color(c) { return [c.r, c.g, c.b, c.a].map(function(v) { return Math.round(v * 255) / 255 }) }
function equal(a, b) { return a && b && a.every(function(v, i) { return v === b[i] }) }
function sample(frame, elapsed) {
    var t = frame.remaining > 0 ? Math.min(1, Math.max(0, elapsed / frame.remaining)) : 1
    return frame.from.map(function(v, i) { return v + (frame.to[i] - v) * t })
}
function retarget(frames, elapsed, targets, duration) {
    var colors = targets.map(color)
    if (frames.length === colors.length && frames.every(function(f, i) { return equal(f.to, colors[i]) }))
        return null
    var result = [], longest = 0
    for (var i = 0; i < colors.length; ++i) {
        var old = frames[i], target = colors[i]
        var from = old ? sample(old, elapsed) : target
        var remaining = old && equal(old.to, target) ? Math.max(0, old.remaining - elapsed) : duration
        if (!old || equal(from, target)) remaining = 0
        longest = Math.max(longest, remaining)
        result.push({from: from, to: target, remaining: remaining})
    }
    return {frames: result, longest: longest}
}

// CPU cores are left/right threads, with chamfers only on the package's four corners.
function cells(width, height, columns, rows, gapX, gapY, cpu) {
    var result = []
    if (cpu) {
        var dieWidth = (width - 10) / 2, coreWidth = (dieWidth - 3) / 2
        var coreHeight = (height - 9) / 4, threadWidth = (coreWidth - 2) / 2
        var innerHeight = coreHeight - 2, cut = Math.min(8, threadWidth * 0.4, innerHeight * 0.4)
        for (var die = 0; die < 2; ++die) for (var core = 0; core < 8; ++core) for (var thread = 0; thread < 2; ++thread) {
            result.push({x: die * (dieWidth + 10) + (core % 2) * (coreWidth + 3) + 1 + thread * threadWidth,
                y: Math.floor(core / 2) * (coreHeight + 3) + 1, w: threadWidth, h: innerHeight,
                tl: die === 0 && core === 0 && thread === 0 ? cut : 0,
                tr: die === 1 && core === 1 && thread === 1 ? cut : 0,
                bl: die === 0 && core === 6 && thread === 0 ? cut : 0,
                br: die === 1 && core === 7 && thread === 1 ? cut : 0})
        }
    } else {
        var w = (width - (columns - 1) * gapX) / columns
        var h = (height - (rows - 1) * gapY) / rows
        for (var i = 0; i < columns * rows; ++i)
            result.push({x: (i % columns) * (w + gapX), y: Math.floor(i / columns) * (h + gapY), w: w, h: h})
    }
    return result
}
