const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const frames = {};
vm.createContext(frames);
vm.runInContext(fs.readFileSync(path.join(__dirname,
    '../quickshell/aeris-dashboard/components/HeatmapFrames.js'), 'utf8'), frames);
const c = (r,g,b) => ({r,g,b,a:1});

test('initial cells appear immediately; identical colors do not restart or upload', () => {
    const packet = frames.retarget([],0,[c(0,0,0),c(1,0,0)],220);
    assert.equal(packet.longest,0);
    assert.equal(frames.retarget(packet.frames,0,[c(0,0,0),c(1,0,0)],220),null);
});
test('retargeting starts from the currently displayed color, without jumps', () => {
    const first = frames.retarget([],0,[c(0,0,0)],220);
    const next = frames.retarget(first.frames,0,[c(1,0,0)],220);
    const third = frames.retarget(next.frames,110,[c(0,1,0)],220);
    assert.equal(third.frames[0].from[0],0.5);
    assert.equal(third.frames[0].remaining,220);
    assert.deepEqual(Array.from(frames.sample(third.frames[0],220)),[0,1,0,1]);
});
test('unchanged transitioning cells keep their original completion time', () => {
    const first = frames.retarget([],0,[c(0,0,0),c(0,0,0)],340);
    const next = frames.retarget(first.frames,0,[c(1,0,0),c(1,0,0)],340);
    const third = frames.retarget(next.frames,100,[c(1,0,0),c(0,1,0)],340);
    assert.equal(third.frames[0].remaining,240);
    assert.equal(third.frames[1].remaining,340);
    assert.equal(third.longest,340);
});
test('CPU maps 16 side-by-side thread pairs, with only four outer chamfers', () => {
    const cells = frames.cells(285,132,0,0,0,0,true);
    assert.equal(cells.length,32);
    for(let i=0;i<32;i+=2){
        assert.equal(cells[i].y,cells[i+1].y);
        assert.equal(cells[i].x+cells[i].w,cells[i+1].x);
    }
    assert.ok(cells[0].tl>0 && cells[12].bl>0 && cells[19].tr>0 && cells[31].br>0);
    assert.equal(cells.reduce((sum,c)=>sum+['tl','tr','bl','br'].filter(k=>c[k]>0).length,0),4);
});
test('memory grid remains square and reaches the intended last column', () => {
    const cells=frames.cells(14*9+13*3,10*9+9*3,14,10,3,3,false);
    assert.equal(cells.length,140);
    for(const c of cells){assert.equal(c.w,9);assert.equal(c.h,9);}
    assert.equal(cells.at(-1).x+cells.at(-1).w,165);
});
