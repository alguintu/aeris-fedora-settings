// Canvas-only atmosphere. Coordinates are in the tile's 480 × 206 design space.
// Seeded placement keeps weather stable across frames; wrapping occurs off-tile.
function seed(i) { return ((Math.sin(i * 127.1 + 311.7) * 43758.5453) % 1 + 1) % 1 }
function rgba(rgb, alpha) { return "rgba(" + rgb + "," + alpha + ")" }

function mist(ctx, x, y, rx, ry, rgb, opacity, density) {
    ctx.save()
    ctx.translate(x, y)
    ctx.scale(rx, ry)
    var g = ctx.createRadialGradient(0, 0, 0, 0, 0, 1)
    g.addColorStop(0, rgba(rgb, opacity))
    g.addColorStop(density, rgba(rgb, opacity * 0.75))
    g.addColorStop(1, rgba(rgb, 0))
    ctx.fillStyle = g
    ctx.fillRect(-1, -1, 2, 2)
    ctx.restore()
}

function sunShafts(t) {
    var shafts = []
    for (var i = 0; i < 6; ++i) {
        shafts.push({
            // The shared source stays above the tile; only atmospheric light is visible.
            x: 296 + Math.sin(t * 0.21) * 18,
            slope: -1.65 + i * 0.47 + Math.sin(t * 0.32 + i * 0.8) * 0.09,
            spread: 0.18 + seed(i + 1200) * 0.135,
            light: 0.28 + 0.09 * Math.sin(t * 0.65 + i * 1.7)
        })
    }
    return shafts
}

function sun(ctx, t, strength) {
    // Volumetric god rays: perspective widening, feathered across each shaft,
    // and fading along its length. No visible sun disk or sharply outlined fan.
    mist(ctx, 295, -95, 360, 290, "250,235,200", 0.15 * strength, 0.08)
    var shafts = sunShafts(t)
    ctx.save()
    for (var i = 0; i < shafts.length; ++i) {
        var s = shafts[i], top = -60, bottom = 370
        var near = top + 180, far = bottom + 180
        var ray = ctx.createLinearGradient(0, top, 0, bottom)
        ray.addColorStop(0, rgba("255,240,195", s.light * strength))
        ray.addColorStop(0.32, rgba("250,234,195", s.light * strength * 0.88))
        ray.addColorStop(0.7, rgba("239,227,200", s.light * strength * 0.40))
        ray.addColorStop(1, rgba("239,227,200", 0))
        ctx.fillStyle = ray
        // Nested low-opacity shells approximate a smooth Gaussian cross-section.
        // One longitudinal gradient per ray avoids per-pixel or per-row rendering.
        var previous = 0
        for (var layer = 0; layer < 24; ++layer) {
            var extent = 1 - layer / 24
            var density = Math.exp(-4 * extent * extent)
            ctx.globalAlpha = density - previous
            previous = density
            var nearWidth = near * s.spread * extent
            var farWidth = far * s.spread * extent
            ctx.beginPath()
            ctx.moveTo(s.x + near * s.slope - nearWidth, top)
            ctx.lineTo(s.x + far * s.slope - farWidth, bottom)
            ctx.lineTo(s.x + far * s.slope + farWidth, bottom)
            ctx.lineTo(s.x + near * s.slope + nearWidth, top)
            ctx.closePath(); ctx.fill()
        }
    }
    ctx.restore()
    // A little drifting illuminated haze joins the beams without obscuring text.
    mist(ctx, 175 + Math.sin(t * 0.30) * 65, 170, 270, 85,
         "239,228,202", 0.06 * strength, 0.1)
}

function starLayer(ctx, layer, layerCount, count) {
    for (var i = layer; i < count; i += layerCount) {
        var x = seed(i + 1) * 480, y = seed(i + 41) * 155
        var alpha = 0.13 + seed(i + 470) * 0.1
        ctx.fillStyle = rgba("216,222,233", alpha)
        ctx.beginPath(); ctx.arc(x, y, 0.6 + seed(i + 80) * 0.9, 0, Math.PI * 2); ctx.fill()
    }
}

function moon(ctx, cx, cy, radius, phase, illumination) {
    phase = Math.max(0, Math.min(1, Number(phase)))
    illumination = Math.max(0, Math.min(1, Number(illumination)))
    ctx.save()
    ctx.translate(cx, cy)
    ctx.rotate(-15 * Math.PI / 180)
    cx = 0
    cy = 0
    var waxing = phase <= 0.5
    var highlightX = cx + (waxing ? 1 : -1) * radius * 0.28 * (1 - illumination)
    // The exterior halo belongs only to bright gibbous/full phases. Fade it
    // in continuously so a changing phase can never visibly pop.
    var halo = Math.max(0, Math.min(1, (illumination - 0.55) / 0.45))
    if (halo > 0)
        mist(ctx, highlightX, cy, radius * 1.6, radius * 1.5,
             "203,218,244", halo * 0.18, 0.38)
    // The unlit face is still physically present: keep a restrained full disc
    // under the bright phase instead of making the missing portion transparent.
    ctx.fillStyle = rgba("111,127,153", 0.11)
    ctx.beginPath(); ctx.arc(cx, cy, radius, 0, Math.PI * 2); ctx.fill()
    // Draw only the illuminated region. The terminator advances from a
    // right-hand waxing crescent through full to a left-hand waning crescent.
    var steps = 48
    var terminator = waxing ? Math.cos(phase * Math.PI * 2)
                            : -Math.cos(phase * Math.PI * 2)
    ctx.beginPath()
    for (var i = 0; i <= steps; ++i) {
        var y = -radius + radius * 2 * i / steps
        var edge = Math.sqrt(Math.max(0, radius * radius - y * y))
        var x = terminator * edge
        if (i === 0) ctx.moveTo(cx + x, cy + y)
        else ctx.lineTo(cx + x, cy + y)
    }
    for (var j = steps; j >= 0; --j) {
        var outerY = -radius + radius * 2 * j / steps
        var outerX = Math.sqrt(Math.max(0, radius * radius - outerY * outerY))
        ctx.lineTo(cx + (waxing ? outerX : -outerX), cy + outerY)
    }
    ctx.closePath()
    var light = Math.sqrt(illumination)
    // Luminance stays inside the active face: a bright, cool center falls off
    // gently toward the lunar edge independently of the bright-phase halo.
    var face = ctx.createRadialGradient(highlightX, cy - radius * 0.18,
                                        radius * 0.04, cx, cy, radius * 1.18)
    face.addColorStop(0, rgba("239,246,255", 0.46 + light * 0.28))
    face.addColorStop(0.56, rgba("216,229,248", 0.36 + light * 0.20))
    face.addColorStop(1, rgba("184,202,226", 0.24 + light * 0.13))
    ctx.fillStyle = face
    ctx.fill()
    ctx.restore()
}

function clearNight(ctx, t, phase, illumination) {
    for (var layer = 0; layer < 3; ++layer) {
        ctx.save()
        ctx.globalAlpha = (0.76 + 0.1 * Math.sin(t * (0.42 + layer * 0.09) + layer * 2.1))
            * (0.94 - illumination * 0.22)
        starLayer(ctx, layer, 3, 39)
        ctx.restore()
    }
    moon(ctx, 286, 42, 29, phase, illumination)
}

function cloud(ctx, x, y, size, opacity, dark) {
    var rgb = dark ? "130,145,168" : "216,222,233"
    // Uneven upper lobes merge into a flatter shaded cloud bank.
    var lobes = [[-70, 5, 58, 32], [-32, -14, 57, 46], [16, -27, 65, 59],
                 [68, -7, 59, 42], [106, 7, 46, 29], [15, 16, 116, 33]]
    for (var i = 0; i < lobes.length; ++i) {
        var p = lobes[i]
        mist(ctx, x + p[0] * size, y + p[1] * size, p[2] * size, p[3] * size,
             rgb, opacity * (i === 5 ? 0.6 : 1), 0.62)
    }
    mist(ctx, x + 15 * size, y + 32 * size, 125 * size, 22 * size,
         "27,34,46", opacity * 0.55, 0.25)
}

function clouds(ctx, t, kind) {
    var storm = kind === "storm", broken = kind === "partly-cloudy"
    var count = broken ? 3 : 5
    for (var i = 0; i < count; ++i) {
        var speed = (storm ? 25 : broken ? 14 : 18) + i * 2.5
        var x = ((i * 257 + t * speed + 200) % 1000) - 260
        var y = broken ? 110 + (i % 2) * 48 : 28 + (i % 3) * 39
        var size = broken ? 0.7 + i * 0.15 : 1 + (i % 2) * 0.22
        cloud(ctx, x, y, size, storm ? 0.2 : broken ? 0.105 : 0.13, storm)
    }
}

function fog(ctx, t) {
    // Overlapping soft volumes at different depths, no strokes or line bands.
    for (var layer = 0; layer < 3; ++layer) {
        for (var i = 0; i < 6; ++i) {
            var n = i + layer * 9
            var x = ((i * 163 + t * (7 + layer * 5) + layer * 103) % 1000) - 250
            var y = 55 + layer * 66 + Math.sin(t * 0.24 + n) * 16
            mist(ctx, x, y, 145 + seed(n) * 100, 34 + seed(n + 30) * 38,
                 "201,211,222", 0.065 + layer * 0.018, 0.08)
        }
    }
}

function rain(ctx, t, storm) {
    var count = storm ? 90 : 52
    var slant = storm ? 0.44 : 0.18
    ctx.lineCap = "round"
    for (var i = 0; i < count; ++i) {
        var depth = seed(i + 7), speed = (storm ? 235 : 145) + depth * 100
        var travel = (seed(i + 70) * 272 + t * speed) % 272
        var y = travel - 24, x = seed(i + 130) * 640 - 25 - travel * slant
        var length = 6 + depth * (storm ? 13 : 9)
        var fade = Math.min(1, Math.max(0, (y - 18) / 40))
        ctx.strokeStyle = rgba("188,207,226", (0.07 + depth * 0.12) * fade)
        ctx.lineWidth = 0.6 + depth * 0.7
        ctx.beginPath(); ctx.moveTo(x + length * slant, y - length)
        ctx.lineTo(x, y); ctx.stroke()
    }
    if (storm) mist(ctx, 230, 190, 330, 50, "161,179,202", 0.06, 0.1)
}

function snow(ctx, t) {
    for (var i = 0; i < 38; ++i) {
        var depth = seed(i + 40), speed = 13 + depth * 22
        var y = (seed(i + 4) * 248 + t * speed) % 248 - 20
        var x = seed(i + 84) * 500 + Math.sin(t * 0.8 + i) * (4 + depth * 8) - 10
        ctx.fillStyle = rgba("225,233,243", 0.1 + depth * 0.17)
        ctx.beginPath(); ctx.arc(x, y, 0.7 + depth * 1.5, 0, Math.PI * 2); ctx.fill()
    }
}

function lightningState(t) {
    var cycle = Math.floor(t / 14)
    var delay = 2.2 + seed(cycle + 501) * 3.6
    var age = t - cycle * 14 - delay
    // One localized strike per window, never a repeating flicker/strobe.
    var strength = age < 0 || age > 1.2 ? 0
        : age < 0.09 ? age / 0.09 : Math.pow(1 - (age - 0.09) / 1.11, 1.7)
    return { cycle: cycle, strength: strength, x: 155 + seed(cycle + 701) * 185 }
}

function lightningGeometry(cycle, x) {
    // Seed once per strike: paths do not jitter between animation frames.
    // Alternate jagged, leaning, and forked profiles, with varied side branches.
    var variant = cycle % 3
    var lean = (seed(cycle + 820) - 0.5) * (variant === 1 ? 160 : 65)
    var points = [], branches = []
    for (var i = 0; i < 12; ++i) {
        var jitter = (seed(cycle * 17 + i + 910) - 0.5) * (variant === 0 ? 58 : 38)
        points.push([x + lean * i / 11 + jitter, -12 + i * 24])
    }
    var count = 3 + Math.floor(seed(cycle + 640) * 3)
    for (var b = 0; b < count; ++b) {
        var at = 2 + Math.floor(seed(cycle * 13 + b + 230) * 6)
        var p = points[at], side = seed(cycle * 7 + b + 318) > 0.5 ? 1 : -1
        var length = 28 + seed(cycle * 9 + b + 470) * 42
        branches.push([p, [p[0] + side * length * 0.55, p[1] + 13],
            [p[0] + side * length * 0.4, p[1] + 29], [p[0] + side * length, p[1] + 55]])
    }
    if (variant === 2) {
        var fork = [points[5]]
        for (var j = 6; j < 12; ++j)
            fork.push([points[5][0] - (j - 5) * 12 + (seed(cycle + j + 77) - 0.5) * 25, points[j][1]])
        branches.push(fork)
    }
    return { points: points, branches: branches }
}

function lightning(ctx, t) {
    var strike = lightningState(t)
    if (strike.strength <= 0) return
    var glow = strike.strength, x = strike.x
    mist(ctx, x, 55, 155, 105, "181,205,246", glow * 0.28, 0.18)
    mist(ctx, x, 160, 68, 160, "178,204,246", glow * 0.1, 0.08)
    var geometry = lightningGeometry(strike.cycle, x), points = geometry.points
    ctx.save()
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
    for (var pass = 0; pass < 3; ++pass) {
        ctx.lineWidth = [11, 4, 1.8][pass]
        ctx.strokeStyle = rgba("216,233,255", glow * [0.09, 0.28, 0.88][pass])
        ctx.beginPath(); ctx.moveTo(points[0][0], points[0][1])
        for (var j = 1; j < points.length; ++j) ctx.lineTo(points[j][0], points[j][1])
        ctx.stroke()
    }
    ctx.lineWidth = 1.1
    ctx.strokeStyle = rgba("204,225,255", glow * 0.5)
    for (var b = 0; b < geometry.branches.length; ++b) {
        var branch = geometry.branches[b]
        ctx.beginPath(); ctx.moveTo(branch[0][0], branch[0][1])
        for (var k = 1; k < branch.length; ++k) ctx.lineTo(branch[k][0], branch[k][1])
        ctx.stroke()
    }
    ctx.restore()
}

function paint(ctx, width, height, kind, isDay, t, moonPhase, moonIllumination) {
    ctx.reset()
    ctx.scale(width / 480, height / 206)
    moonPhase = moonPhase === undefined ? 0.75 : moonPhase
    moonIllumination = moonIllumination === undefined ? 0.5 : moonIllumination
    // Night is a backdrop shared by every nighttime condition. Fog, rain,
    // snow, storm, and cloud layers are drawn over it below.
    if (kind === "night" || (!isDay && kind !== "unknown"))
        clearNight(ctx, t, moonPhase, moonIllumination)
    if (kind === "clear") sun(ctx, t, 1)
    else if (kind === "night") { /* backdrop already painted */ }
    else if (kind === "fog") fog(ctx, t)
    else if (["partly-cloudy", "cloudy", "rain", "storm", "snow"].indexOf(kind) >= 0) {
        if (kind === "partly-cloudy") {
            if (isDay) sun(ctx, t, 0.7)
        }
        if (kind === "rain" || kind === "storm") rain(ctx, t, kind === "storm")
        if (kind === "snow") snow(ctx, t)
        if (kind === "storm") lightning(ctx, t)
        // The overhead deck sits in front of the beginning of falling precipitation.
        clouds(ctx, t, kind)
    }
}
