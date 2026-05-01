# Parity Checklist

> One source of truth for project state. Tick a box only when the feature works against a real `.sumocfg`. Add the date + your handle when you tick.

Legend: `[ ]` todo · `[~]` in progress · `[x]` done · `[-]` deferred to v2

---

## Day 1 — Skeleton & TraCI

### Project scaffolding
- [x] Repo structure, docs, license (2026-05-01, claude)
- [x] `Package.swift` for `SumoKit` (Swift 5.10, macOS 14+) (2026-05-01, claude)
- [x] App target with SwiftUI lifecycle (SwiftPM executable plus Xcode `.app` target, shared `SumoGUIMacApp` scheme, and app icon scaffold build successfully) (2026-05-01, codex)
- [~] CI: GitHub Actions running `swift test` on macOS-14 runner (workflow added at `.github/workflows/ci.yml`; needs first run on push)
- [x] `Scripts/find-sumo.sh` — locates `sumo` binary across Homebrew / official framework / `$PATH` (2026-05-01, claude)
- [x] MIT project license with SUMO treated as an external user-installed runtime, not bundled source/binaries (2026-05-01, codex)

### TraCI client (`SumoKit/Backend/TraCI*`)
- [x] Wire protocol: `TraCIWire.swift` — length-prefixed framing, big-endian, primitive codecs (2026-05-01, claude)
- [x] Type-code subset: byte/int/double/string/string-list (full set still in `TraCIConstants.swift`; expand as needed) (2026-05-01, claude)
- [~] Command/type constants — minimal hand-maintained TraCI subset for currently wired domains; expand as APIs are added
- [x] `TraCIConnection.swift` — Darwin BSD socket actor, TCP_NODELAY, retrying connect (2026-05-01, claude)
- [x] `SumoLauncher.swift` — spawns `sumo --remote-port`, picks free port, exposes stderr (2026-05-01, claude)
- [x] **Live round-trip**: getVersion + 2× simulationStep + close against real SUMO 1.26.0 (2026-05-01, claude)
- [ ] Domain APIs: `Simulation`, `Vehicle`, `Edge`, `Lane`, `Junction`, `TrafficLight`, `POI`, `GUI`
- [~] **Subscriptions**: viewport-aware junction-context vehicle subscriptions plus selected-vehicle variable subscriptions are wired in the app; broaden object/domain coverage still pending
- [~] Subscription result block parser (post-SIMSTEP trailer) — context and selected vehicle-variable trailers work for current app path; broaden coverage for more domains
- [ ] Reconnect / version-negotiation guard (warn if TraCI version on the wire differs from supported target)
- [x] App smoke path: launch SUMO from opened `.sumocfg`, connect TraCI, step, and read live vehicle snapshots (2026-05-01, codex)
- [~] External TraCI attach mode: app can load matching geometry and attach as an ordered viewer client for controller/MAPPO runs; live external smoke test pending

## Day 2 — Network parsing & spatial index

### `.net.xml` parser (`SumoKit/Net/`)
- [~] `NetXMLParser.swift` — streaming `XMLParser`, no full-DOM load (fixture-tested; large-network bench pending)
- [~] Entities: `<location>`, `<edge>`, `<lane>`, `<junction>`, `<connection>`, `<tlLogic>`, `<roundabout>` (fixture-tested; broader validation pending)
- [~] Lane shape decoding (PointList strings, projection metadata) (fixture-tested; projection use in renderer pending)
- [~] `NetGraph.swift` — value-typed POD structs, `ContiguousArray<Lane>` etc., no class boxing (implemented; memory bench pending)
- [~] Quadtree spatial index for viewport culling (lane/edge/junction indexes implemented; renderer integration pending)
- [ ] Bench: parse a large `.net.xml` < 5s, NetGraph memory < 500MB

## Day 3 — Metal renderer

### Pipelines (`SumoGUIMac/Render/`)
- [~] `NetworkView.swift` — `NSViewRepresentable` wrapping `MTKView` (static parsed network display works; lanes, junctions, and vehicles now use Metal; renderer polish pending)
- [~] Camera: cursor-anchored zoom, pinch, double-click zoom, drag pan, and trackpad pan are wired; rubber-band select pending
- [~] Lane shader: instanced quad pass with per-lane width, speed-derived colour, and selected-edge highlight is wired; line joins/LOD polish pending
- [~] Junction shader: filled triangle-fan polygons from parsed junction shapes are wired; robust concave triangulation/styling pending
- [~] Vehicle shader: instanced triangle pass with speed/type-derived colour, render-side interpolation, and selected-vehicle highlight is wired; sizing/selection overlay polish pending
- [ ] Level-of-detail: cull lanes < 0.5px wide, drop vehicle shape under 2px
- [~] Hit-testing: CPU nearest-live-vehicle picking plus nearest non-internal edge/lane picking are wired for map clicks; GPU id-buffer pass still pending
- [ ] Bench: 60 fps with large network + 50k vehicles

## Day 4 — SwiftUI shell

### Window chrome
- [~] Three-pane `NavigationSplitView`: left objects sidebar, centre `NetworkView`, right inspector (initial shell works)
- [~] Bottom transport bar: open / play / pause / step / delay slider / sim-time / speed factor (stop now halts without destroying the run; speed factor pending)
- [~] CLI/open-file launch path: accept `.sumocfg` / `.net.xml` on startup (`-c path` or bare path); recent-files/open-document polish pending
- [~] Menu bar: File (Open, Attach to TraCI), View (fit/zoom), and Simulation (play/pause/step/stop) command menus are wired; recents, screenshots, settings, breakpoints, and multi-view polish pending
- [~] Keyboard shortcuts matching sumo-gui where possible (`⌘O`, `⌘0`, `⌘=`, `⌘-`, `space=play/pause`, `s=step`, `⌘.=stop` wired; more parity shortcuts pending)
- [ ] Inspector tabs: Parameters, Subscriptions, Tracker (Swift Charts time-series)

## Day 5 — Visualization parity

### Color schemes (matching `GUIColorScheme.cpp`)
- [ ] Lane: by speed-limit, by lane-index, by occupancy, by edge type, uniform
- [ ] Vehicle: by speed, by acceleration, by route, by type, by CO₂, by colour-attr
- [ ] Junction: by type, by load
- [ ] Custom palette editor with import/export to SUMO XML format
- [ ] Background: PNG/GeoTIFF decal with georeferencing
- [ ] POI rendering, polygon rendering

### Visualization Settings dialog
- [ ] Tabs: Background, Streets, Vehicles, Persons, Containers, Junctions, Detectors, POIs, Legend
- [ ] Save/load `.xml` settings file (sumo-gui-compatible)

## Day 6 — Inspection, breakpoints, trackers

- [ ] Right-click context menu per object class (Vehicle: track, follow, copy id, show route, remove)
- [~] Selection set persistence + selection-driven colour overlay (single selected edge/vehicle render feedback and edge inspector details are wired; persistence/multi-select pending)
- [ ] Breakpoints panel — list of sim-times to halt at; double-click to jump
- [ ] Tracker windows (Swift Charts) — time-series of any TraCI variable for selected object(s)
- [ ] Vehicle tracking camera (centre + rotate-with-heading)
- [ ] Route highlighting on hover

## Day 7 — Stability, scale, ship

- [ ] Large benchmark scenario script (OSM import via `osmGet.py`/`netconvert`)
- [ ] Run a large benchmark for 1 hour sim time, profile with Instruments — fix top 3 hot paths
- [ ] Crash test: kill `sumo` subprocess mid-step, verify UI recovers gracefully
- [ ] Screenshot/video export (PNG, MP4 via AVFoundation)
- [~] Notarization-ready build path (`SumoGUIMacApp` Xcode scheme builds a signed local `.app`; release archive script, developer-team signing, and notarization still pending)
- [ ] README with screenshot, install instructions, contributing guide
- [ ] First public tag: `v0.1.0`

---

## Deferred to v2

- [-] 3D view (SceneKit / Metal 3D)
- [-] Multiple synchronised viewports
- [-] Person/pedestrian rendering with full sumo-gui modes
- [-] OSG-equivalent decals
- [-] netedit replacement
- [-] FMI co-simulation hookup
- [-] Replay mode driven from `.fcd-output` without running SUMO

---

## Handoff state (update at end of every session)

- **Last touched:** 2026-05-01 — codex — Added external TraCI attach mode for controller/MAPPO workflows and added an Xcode `.app` target with a generated app icon. `swift test` passes 26/26, and `xcodebuild -project SumoGUIMac.xcodeproj -scheme SumoGUIMacApp -configuration Debug -destination platform=macOS -derivedDataPath .build/XcodeDerivedData-App build` succeeds.
- **Next action:** Live-smoke external attach with `sumo --remote-port <port> --num-clients 2` and a second controller client, then prepare the first alpha commit once the working tree is reviewed.
- **Known blockers:** External attach mode needs a live multi-client SUMO smoke test with the controller at one TraCI order and SumoGUIMac at another. Release signing is local/ad-hoc only; developer-team signing, archive export, and notarization are still pending. Junction triangulation is simple fan triangulation, so unusual concave junction shapes may need a more robust tessellator. Lane joins are segment-based rather than full SUMO-style stroked joins, and viewport subscriptions are junction-radius based, so very sparse networks may still overfetch until a true viewport query/filter strategy lands.
- **Local SUMO version targeted:** 1.26.0 at `/Library/Frameworks/EclipseSUMO.framework/Versions/1.26.0/EclipseSUMO`. SUMO_HOME for the python tools = `$FW/share/sumo`.

## Lessons learned (read these before debugging)

- **Don't hand-write `.net.xml` for tests.** SUMO validates internal-link geometry strictly and bails before TraCI ever opens. Use `netconvert` to build fixtures from `.nod.xml` + `.edg.xml`. See `Tests/SumoKitTests/Fixtures/tiny.net.xml`.
- **TraCI response shape is per-command.** Status block (lenByte, cmdID, result, descString) is always present. After it: GET-style commands wrap their payload in a `lenByte+cmdID` echo block; SIMSTEP appends a 4-byte sub-result count + N sub-result blocks; CLOSE has nothing. `sendCommand` returns the bytes after status; each domain method parses its own tail.
- **`NWConnection` is finicky here.** We use raw `Darwin.socket` + `TCP_NODELAY` to mirror SUMO's Python client; that worked first try.
- **`--no-step-log true` etc. needs the `true` argument** even though they look boolean. SUMO's option parser accepts `--flag value` form for bool options.
