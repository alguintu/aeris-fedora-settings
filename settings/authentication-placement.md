# Authentication prompt placement

The 1920×480 touchscreen (`DP-3`) is normally covered by the Aeris Quickshell
dashboard. KDE PolicyKit prompts must therefore appear on the 3840×2160 primary
display (`HDMI-A-1`).

`kwin/aeris-auth-primary` is a narrowly scoped KWin script. It matches only the
observed KDE PolicyKit identity,
`org.kde.polkit-kde-authentication-agent-1`, and resolves the destination by
the stable connector name `HDMI-A-1`. It deliberately does not use KWin's
numeric screen indices, whose mapping has differed from the display priority.

Install or update the user-local package and enable it at login:

```bash
./scripts/install-auth-placement.sh
```

Verify the installed copy, enabled setting, and current KWin load state:

```bash
./scripts/install-auth-placement.sh --check
```

Remove the script and its KWin setting:

```bash
./scripts/install-auth-placement.sh --remove
```
