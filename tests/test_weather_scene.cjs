const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const scene = {};
vm.createContext(scene);
vm.runInContext(fs.readFileSync(path.join(__dirname,
    '../quickshell/aeris-dashboard/components/WeatherScene.js'), 'utf8'), scene);

function render(kind, time, day = true) {
    const operations = [];
    const gradient = { addColorStop: (...args) => operations.push(['stop', ...args]) };
    const ctx = new Proxy({}, {
        get: (_, key) => (...args) => {
            for (const value of args) {
                if (typeof value === 'number') assert.ok(Number.isFinite(value), `${key}: ${value}`);
            }
            operations.push([key, ...args]);
            return key.startsWith('create') ? gradient : undefined;
        },
        set: (_, key, value) => { operations.push([key, value]); return true; }
    });
    scene.paint(ctx, 480, 206, kind, day, time);
    return JSON.stringify(operations);
}

for (const kind of ['clear', 'night', 'partly-cloudy', 'cloudy', 'fog', 'rain', 'snow', 'storm']) {
    test(`${kind}: finite geometry, deterministic placement, visible motion`, () => {
        const first = render(kind, 0);
        assert.equal(first, render(kind, 0));
        assert.notEqual(first, render(kind, 1));
        for (const time of [7, 60, 3600, 86400]) render(kind, time);
    });
}
test('partly cloudy changes illumination after sunset', () => {
    assert.notEqual(render('partly-cloudy', 3, true), render('partly-cloudy', 3, false));
});
test('missing weather stays blank', () => {
    assert.equal(render('unknown', 0), JSON.stringify([['reset'], ['scale', 1, 1]]));
});

test('daylight shafts drift smoothly, breathe independently and stay bounded', () => {
    for (const t of [0, 1, 7, 60, 3600, 86400]) {
        const shafts = scene.sunShafts(t);
        const next = scene.sunShafts(t + 1 / 30);
        assert.equal(shafts.length, 6);
        for (let i = 0; i < shafts.length; ++i) {
            const s = shafts[i];
            assert.ok(s.light >= 0.19 && s.light <= 0.371);
            assert.ok(s.spread >= 0.18 && s.spread <= 0.315);
            assert.ok(Math.abs(s.slope - next[i].slope) < 0.001);
            assert.ok(Math.abs(s.x - next[i].x) < 0.13);
        }
    }
});

test('lightning is localized, bounded, infrequent and fades away', () => {
    let previousStart = -100;
    for (let cycle = 0; cycle < 20; cycle++) {
        const start = cycle * 14 + 2.2 + scene.seed(cycle + 501) * 3.6;
        assert.ok(start - previousStart > 10);
        previousStart = start;
        assert.equal(scene.lightningState(start - 0.01).strength, 0);
        const peak = scene.lightningState(start + 0.09);
        assert.ok(peak.strength > 0.99 && peak.strength <= 1);
        assert.ok(peak.x >= 155 && peak.x <= 340);
        assert.ok(scene.lightningState(start + 0.5).strength < peak.strength);
        assert.equal(scene.lightningState(start + 1.21).strength, 0);
        render('storm', start + 0.09);
    }
});

test('lightning reaches off-tile and varies without frame-to-frame jitter', () => {
    const paths = new Set();
    for (let cycle = 0; cycle < 12; cycle++) {
        const g = scene.lightningGeometry(cycle, 250);
        assert.ok(g.points[0][1] < 0);
        assert.ok(g.points.at(-1)[1] > 206);
        assert.ok(g.branches.length >= 3);
        const serialized = JSON.stringify(g);
        assert.equal(serialized, JSON.stringify(scene.lightningGeometry(cycle, 250)));
        paths.add(serialized);
        if (cycle % 3 === 2) assert.ok(g.branches.some(branch => branch.at(-1)[1] > 206));
    }
    assert.equal(paths.size, 12);
});
