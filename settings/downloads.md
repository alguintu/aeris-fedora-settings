# Free Download Manager

## Fedora installation — 2026-09-05

Installed for the current user from the existing Flathub remote:

```bash
flatpak install --user flathub org.freedownloadmanager.Manager
flatpak run org.freedownloadmanager.Manager
```

Verified version: **6.34.2.6926**, Flatpak commit
`7d33bf843a4fcd81778c237497bb724e92c70394eca4a8f4e48be03fe959f25b`.
FDM's official download page links to Flathub. The package's upstream DEB
SHA-256 matches the published checksum:
`299c5bef180b578ae223e03a108279c3b80ec7f9bce3e1792469d46dee2fc6cd`.

The application was opened successfully on the primary display. Launching it
again returned to the existing instance instead of creating a second download
manager. At installation, no test downloads, remote-access configuration, login autostart, or
additional filesystem permissions were enabled.

The sandbox grants the Downloads directory, not all host storage. Broader
download destinations should be granted individually when selected. The
existing host Chrome extension is installed, but its native messaging bridge
is **not configured** by this Flatpak installation; browser interception still
needs a separate integration check.

## Torrent associations — 2026-09-05

Registered FDM as the host desktop's default for torrent files and magnet links:

```bash
xdg-mime default org.freedownloadmanager.Manager.desktop application/x-bittorrent
xdg-mime default org.freedownloadmanager.Manager.desktop x-scheme-handler/magnet
```

The user desktop entry declares both types in addition to its existing HTTP/HTTPS
support; browser defaults are unchanged. The Rust launcher uses Flatpak document
portal forwarding for explicitly opened local files, including those outside
Downloads, without granting broad filesystem access. Magnet/web URLs pass through
unchanged. Both initial and existing-instance launches retain the monitor bridge.
Host association queries confirm both defaults. FDM's sandbox-internal default
client prompt may still fail to recognize host associations; its button is not
the source of truth. No torrent download was started for this configuration.

## CasaOS Move correction — 2026-09-08

Working destination: `/home/drei/CasaOS/Media/Movies`,
`/home/drei/CasaOS/Media/TV Shows`, or subfolders. The CIFS mount is
`//raspberrypi.local/DATA` at `/home/drei/CasaOS`, with a scoped FDM Flatpak
filesystem grant. System-wide units `home-drei-CasaOS.mount` and
`home-drei-CasaOS.automount` now make the mount available on demand after reboot.
The automount is enabled under `multi-user.target`. The initial manual CIFS mount
was subsequently unmounted, the automount activated, and opening the Remote
shortcut verified to trigger a fresh CIFS mount. The automount is active now. Unit sources are in `config/casaos/` and installed
under `/etc/systemd/system/`. The mount waits for networking and has a 15-second
mount timeout. No idle unmount is configured.

The KDE Places bookmark **CasaOS** is under **Remote**, points to `remote:/CasaOS`, and uses
`/usr/share/icons/breeze-dark/places/22/folder-cloud.svg`, a cloud outline icon.
`~/.local/share/remoteview/CasaOS.desktop` is a KDE network shortcut with
`URL=file:///home/drei/CasaOS`, so browsing redirects to the working mount instead
of using the SMB KIO bridge. Its source is `config/casaos/CasaOS.desktop`.
The automatic duplicate CIFS device entry is hidden with its `IsHidden` metadata.
The idle FDM instance was reopened after activating the automount.
The prior Places file was backed up to
`~/.local/state/aeris/backups/user-places-before-casaos-permanent-20260908.xbel`.
Unit syntax, boot enablement, existing CIFS access, and icon rendering were verified.
The original KIO network-folder bridge reports zero free space and failed a
separate real-file move test even after the picker correction. Use the CIFS path.

FDM 6.34.2's embedded Move dialog reads `currentFolder` on acceptance while the
native Qt picker returns the chosen destination through `selectedFolder`.
`MoveFolderFix.js` substitutes only that dialog in the current bundled main UI,
using `selectedFolder` to move and remember the destination. Exact source checks
reject an incompatible future UI and fall back to the bundled stock component.
The installer enables `QML_XHR_ALLOW_FILE_READ=1` to read the embedded resources;
this setting adds no filesystem grants.

The dynamically created main window must have a **nonvisual QtObject owner**.
Parenting it to the monitor's invisible Item prevents the native window from
appearing. The current `Monitor.qml` uses `uiOwner`; do not replace that owner
with the bridge Item. An earlier revision with the Item parent was rolled back.

Validation used an isolated FDM profile, separate configuration/database/temp
paths, and Flatpak `--sandbox` to avoid the normal single-instance connection.
The exact deployed Monitor.qml and MoveFolderFix.js downloaded a 1 MiB localhost
test file, moved it into Movies, then into a TV Shows subfolder containing spaces.
The prior copies disappeared and the SHA-256 remained
`fbbab289f7f94b25736c58be46a994c441fd02552cc6022352e3d86d2fab7c83`.
The real monitored FDM instance was then reopened and its native window and fresh
dashboard snapshots were verified. Drei confirmed the actual Move operation
worked. Remote test files/directories were cleaned up. User download records
were not edited outside FDM.

## Dashboard monitor

- The `Settings` table currently reports `MaxDownloads = 4`, matching the
  intended four active-download bars. No setting change was necessary.
- A standard `org.kde.StatusNotifierItem` identifies itself as
  `Free Download Manager` and exposes `Activate`. Resolve its current bus name
  through the status-notifier watcher; do not hardcode a transient bus ID.
- Normal app launch also activates the existing instance. Repeated Rust-launcher
  activation was verified to reuse the same window on the main monitor, retaining
  its placement. There is currently no FDM-specific KWin window rule.
- FDM listens on a private local socket, `/tmp/fdm6fs1000` in its sandbox on
  this machine. No FDM TCP listener was observed with default settings.
- Its UI metadata exposes title, size/selected size, downloaded bytes, speed,
  running/downloading state, errors, and progress change signals. These are
  **internal interfaces**, not a verified externally callable monitoring API.
- Its SQLite database is at
  `~/.var/app/org.freedownloadmanager.Manager/data/Softdeluxe/Free Download Manager/db.sqlite`.
  Schema inspection found binary resume/file/runtime-related state, not a
  straightforward table of live percentages. Do not write into its database or
  infer progress from preallocated file lengths. It also contains sensitive
  download/authentication state; never copy it into this repository.
- The browser native host exposes handshake, settings, and download submission
  tasks; no supported queue-monitoring call has been verified.

### Implemented QML + Rust bridge — 2026-09-05

Drei approved the small FDM-side QML adapter. `quickshell/fdm/Monitor.qml` uses
FDM's `--qurl` entry point, loads **its own bundled stock interface unchanged**,
and samples `App.downloads.tracker.runningIds()` plus `infos.info(id)` once per
second. This does not depend on the selected category, search, or UI model.
Only IDs, titles, selected total/downloaded bytes, speed and running state are
exported; no URLs, cookies, credentials, destination paths, or database copies.
The snapshot also includes `completedCount`: FDM's own `finishedDownloadsCount`
from its UI tracker, independent of the current list filter. A notified property
binding includes this existing aggregate in the one-second snapshot. It is not a
lifetime total or filesystem scan. Older adapters yield an unknown count, not
a fabricated zero. The widget hides zero-speed text and zero/unknown counts;
positive counts appear green at the right edge (99+ cap, exact tooltip count).
When speed is also visible, the right-aligned statistics read `speed · count`;
otherwise the lone value stays right-aligned without a separator.

The Rust `fdm launch` command hosts FDM and captures tagged JSON from stderr.
Other diagnostics are discarded rather than logged. Validated snapshots are
atomically stored as `$XDG_RUNTIME_DIR/aeris-fdm/state.json` (0600, directory
0700). The shared Rust dashboard watcher reads once per second and clears
stale/disconnected slots after five seconds. No new HTTP listener or remote API
is enabled. The launcher lives with FDM, independently of dashboard restarts.

Home now has four fixed gray tracks, stable active-download-to-slot assignment,
real progress fill, and a moving segment for unknown totals. Finished/paused
downloads vacate their slots. Whole-tile tapping launches/raises FDM; it never
starts, stops, reorders or otherwise manages a download. FDM alone owns scheduling.
Tooltip-only diagnostics keep the approved tile geometry uncluttered.

### Dashboard window activation correction

The tile uses `fdm open`, not a blind second `fdm launch`. Rust asks KWin to
restore and activate FDM's existing main window without changing its geometry.
The scoped script matches only FDM, reports through a private session-bus
callback, and is unloaded immediately; no global focus policy or persistent
window watcher is installed. A missing window starts the monitored launcher in
an independent, collected transient user unit. Bounded startup retries handle
FDM starting hidden; repeated taps are coalesced by a separate lock. No download
is started, paused, or cancelled by this action. API/status capture is unchanged.

Verified live: fully quit → open; minimized → restored and focused;
closed to tray → reopened. Geometry stayed at 950×515, (8,531) on the main
display throughout. `fdm window-status` is a read-only diagnostic. KWin's
scripting D-Bus interface is required; the helper fails explicitly if unavailable.
See the [KWin scripting API](https://develop.kde.org/docs/plasma/kwin/api/).

Install after building the Rust backend:

```bash
bash scripts/build-dashboard-backend.sh
bash scripts/install-fdm-monitor.sh
aeris-fdm
```

The installer deploys the QML adapter into the app's existing Flatpak config,
a `~/.local/bin/aeris-fdm` symlink to the Rust backend, and a user desktop-entry
override with the same application ID. App-launcher and dashboard launches use
the bridge; subsequent launches activate the existing FDM instance. The repo
must remain at its installed path; rerun the installer after moving it.
No FDM login autostart was added. If FDM was started outside this launcher,
quit it once and reopen through the installed entry: a second `--qurl` cannot
inject an adapter into an already-running stock instance.

This uses FDM's **internal QML interfaces**, not a supported public progress API.
After an FDM update, verify the resource path and live-property contract. A
broken exporter fails to unavailable rather than showing stale/fake progress.
To return to stock launching, remove the user desktop-entry override and launch
`flatpak run org.freedownloadmanager.Manager` after quitting FDM. Download data
and its stock UI are not modified by the bridge.

Validation includes four concurrent controlled localhost downloads (16MiB each),
real byte/speed progression, UI-filter independence, and completion returning to
empty slots. Rust tests cover stable assignment, unknown sizes, stale/corrupt
state and private snapshots. QML tests cover four aligned tracks, progress,
offscreen freezing, indeterminate motion and disconnect clearing.
The five generated test downloads (one probe plus the four-slot run) were removed
from FDM through its own API; their files were moved to Trash. Temporary test
QML entry points were also removed; normal launching uses only `Monitor.qml`.

Sources:

- [Official downloads](https://www.freedownloadmanager.org/download.htm)
- [Flathub packaging](https://github.com/flathub/org.freedownloadmanager.Manager)
- [Official custom-UI announcement](https://www.freedownloadmanager.org/board/viewtopic.php?t=18517)
