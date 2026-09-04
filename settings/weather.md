# Dashboard weather

The clock tile now reads Open-Meteo current model conditions through the
`WeatherService` singleton and the Rust backend's `weather` command. Temperature remains Celsius;
the provider's WMO weather code and day/night flag select the icon and texture.
This is a weather-model estimate, not a local sensor or warning service.

## Local configuration

The user's selected city and city-centre coordinates are saved outside Git at
`~/.config/aeris-dashboard/weather.json` (or under `XDG_CONFIG_HOME`). Fields:

```json
{"name": "Your city", "latitude": 0.0, "longitude": 0.0}
```

Replace the example coordinates with the chosen city centre; zero is not a default
location. The deployed workstation already has its user-approved city configured.
No GPS, IP geolocation, API key, GTK package, or separate daemon is required.
The native adapter uses verified HTTPS. Coordinates are sent to Open-Meteo over
HTTPS; no vault contents, hardware telemetry, or account details are sent.
Changing the city invalidates any cached reading from the previous location.

## Refresh and failure behavior

- Startup reuses a valid cache younger than ten minutes; otherwise it fetches.
- Normal refresh: ten minutes. Failed update retry: two minutes.
- Tap the temperature/condition to refresh, rate-limited to once a minute.
- An in-flight request does not blank the tile or block the clock.
- Last-known data is retained on failure and visibly labelled `cached`; its
  original timestamps are preserved. Data older than six hours is hidden.
- A reading also becomes visibly stale after 30 minutes without a successful
  fetch, or one hour after its provider timestamp. Wall-clock age is checked
  every 30 seconds, including after suspend. The clock/date remain independent.
- Missing location, corrupt cache, timeout, or malformed API data never falls
  back to a made-up temperature. The tile shows `--°C` when unavailable.
- Open-Meteo attribution is in the weather tooltip, alongside city, condition,
  fetch time, and the refresh action. No additional line occupies the tile.
  Stale data prefixes the existing condition line with `Cached:` in amber.

The cache is atomically replaced at `~/.cache/aeris-dashboard/weather.json`.
No additional startup setup is needed beyond the existing dashboard service.
The city file persists through restarts; copy it separately when migrating machines.

```bash
quickshell/aeris-dashboard/bin/aeris-dashboard-backend weather
quickshell/aeris-dashboard/bin/aeris-dashboard-backend weather --refresh
bash scripts/run-dashboard.sh ipc call weather status
bash scripts/run-dashboard.sh ipc call weather refresh
# Presentation-only preview: clear, night, partly-cloudy, fog, rain, snow, storm.
bash scripts/run-dashboard.sh ipc call weather preview rain
python3 -m unittest discover -s tests -p test_weather.py
```

Previews show `--°C` and a `preview` label, never overwrite live weather/cache,
and automatically return to live data after 30 seconds (or an empty preview name).

Tests redirect files with `AERIS_WEATHER_CONFIG` and `AERIS_WEATHER_CACHE`, mock
network access, and cover WMO mapping, night icons, invalid payloads, cache expiry,
cross-location isolation, missing configuration, offline fallback, and failed writes.
The current city API response and live QML tile were also checked visually.

`WeatherAtmosphere.qml` presents layered weather in the clipped tile, with a
33 ms scene-clock target. Daylight uses a single compiled fragment shader;
clouds and fog are cached Canvas textures moved by Qt's scene graph. Rain/snow
use small scene-graph rectangles, and lightning is cached once per strike.
`WeatherScene.js` supplies shared geometry and retains the full CPU renderer
for A/B checks and the daylight fallback on software/shader-error backends.
Cloud banks cross the scene at 14–35 design pixels/second, with distinct
depths and shading. Clear daylight has drifting, softly feathered god rays from
an off-tile source, with independently varying light and diffuse haze, rather
than rings. Clear night has moonlight and stars; `night` is a presentation variant
of WMO clear/mainly-clear after sunset, not a separate meteorological condition.
Partly cloudy also selects daylight or moonlight from the provider's day flag.
Fog uses overlapping soft volumes, not line bands. Fine rain streaks travel
downward with a consistent wind angle at different depths; storms increase rain
density, speed, slant, and cloud cover. Storms also have occasional fine branched
lightning behind the cloud deck, with a localized blue-white glow. Bright cores
and wider soft glows run from above the cloud deck past the tile's bottom edge.
Seeded jagged, leaning, and forked paths vary by strike without jittering between
frames. Strikes are spaced roughly 10–18 seconds apart, rise over 90 ms, and fade
out within 1.2 seconds.
There are no repeated flickers or full-tile flashes; foreground text is untouched.
The scene clock resets on a condition change so a storm preview shows a strike
within its first six seconds, but freezes in place when off-page/collapsed.
Snow uses small falling flakes at varied depths instead of floating asterisks.

Motion pauses in place while Idle is off-page or the dashboard is collapsed.
Text, icons, tile geometry, and weather polling are unchanged. The original
cloud SVG is retained as an inactive design asset. Rendering-geometry tests run
with `node --test tests/test_weather_scene.cjs` (Node is only needed for tests).
Foreground weather icons are the same pinned Pictogrammers MDI set used elsewhere
(with the existing Feather sun/moon). Neither fan nor lighting state is changed.

See [performance measurements and renderer diagnostics](dashboard-performance.md)
for the before/after CPU/GPU results, shader build command, and fixed-time comparisons.

Sources: [forecast API and WMO codes](https://open-meteo.com/en/docs),
[geocoding API](https://open-meteo.com/en/docs/geocoding-api),
[data licence and attribution](https://open-meteo.com/en/licence).
