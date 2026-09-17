import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../quickshell/aeris-backend/src/fdm_window.js', import.meta.url), 'utf8');
function run(windows, restore) {
    const workspace = {windowList: () => windows, activeWindow: null};
    let report;
    runInNewContext(source.replace('__DESTINATION__', '":1.123"').replace('__RESTORE__', String(restore)), {
        workspace,
        callDBus: (dest, path, iface, method, payload) => {
            assert.equal(dest, ':1.123');
            assert.equal(method, 'report');
            report = JSON.parse(payload);
        }
    });
    return {workspace, report};
}
const window = (app) => ({normalWindow: true, desktopFileName: app, resourceClass: '',
    minimized: true, active: false, frameGeometry: {x: 8, y: 531, width: 950, height: 515}});

test('restores only FDM without changing its placement', () => {
    const other = window('some-other-app');
    const fdm = window('org.freedownloadmanager.Manager');
    const before = {...fdm.frameGeometry};
    const {workspace, report} = run([other, fdm], true);
    assert.equal(workspace.activeWindow, fdm);
    assert.equal(fdm.minimized, false);
    assert.equal(other.minimized, true);
    assert.deepEqual(fdm.frameGeometry, before);
    assert.equal(report.found, true);
});
test('read-only status does not activate or unminimize', () => {
    const fdm = window('org.freedownloadmanager.Manager');
    const {workspace, report} = run([fdm], false);
    assert.equal(workspace.activeWindow, null);
    assert.equal(fdm.minimized, true);
    assert.equal(report.found, true);
});
test('missing main window reports absent; similarly named apps are not matched', () => {
    assert.deepEqual(run([window('fdm-lookalike')], true).report, {found: false});
    const dialog = window('org.freedownloadmanager.Manager');
    dialog.normalWindow = false;
    assert.deepEqual(run([dialog], true).report, {found: false});
});
