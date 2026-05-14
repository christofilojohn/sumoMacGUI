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
- [~] Command/type constants — expanded for currently wired Simulation, Vehicle, Edge, Lane, Junction, TrafficLight, Route, POI, Polygon, and GUI id/count paths; keep extending variable constants as inspectors land
- [x] `TraCIConnection.swift` — Darwin BSD socket actor, TCP_NODELAY, retrying connect (2026-05-01, claude)
- [x] `SumoLauncher.swift` — spawns `sumo --remote-port`, picks free port, exposes stderr (2026-05-01, claude)
- [x] **Live round-trip**: getVersion + 2× simulationStep + close against real SUMO (`swift test` currently live-smokes the located SUMO 1.25.0 binary; original target was 1.26.0) (2026-05-03, codex)
- [~] Domain APIs: typed helpers exist for `Simulation`, `Vehicle`, `Edge`, `Lane`, `Junction`, `TrafficLight`, `Route`, `POI`, `Polygon`, and `GUI`; live-smoked Simulation/Edge/Lane/Junction/Route against a real `.sumocfg`, broader per-variable coverage pending
- [~] **Subscriptions**: viewport-aware junction-context vehicle subscriptions plus selected-vehicle variable subscriptions are wired in the app; broaden object/domain coverage still pending
- [x] Subscription result block parser (post-SIMSTEP trailer) — centralized parser handles variable and context subscription responses with unit coverage (2026-05-03, codex)
- [~] Reconnect / version-negotiation guard — connected SUMO identifier is checked against the supported target and the app warns on mismatches; reconnect retry policy still pending
- [x] App smoke path: launch SUMO from opened `.sumocfg`, connect TraCI, step, and read live vehicle snapshots (2026-05-01, codex)
- [~] External TraCI attach mode: app can load matching geometry and attach as an ordered viewer client for controller/MAPPO runs; live external smoke test pending

## Day 2 — Network parsing & spatial index

### `.net.xml` parser (`SumoKit/Net/`)
- [x] `NetXMLParser.swift` — streaming `XMLParser`, no full-DOM load, fixture-tested with parser metadata assertions (2026-05-03, codex)
- [x] Entities: `<location>`, `<edge>`, `<lane>`, `<junction>`, `<connection>`, `<tlLogic>`, `<roundabout>` are fixture-tested, including metadata and bounds fallback validation (2026-05-03, codex)
- [x] Lane shape decoding (PointList strings, projection metadata) is fixture-tested (2026-05-03, codex)
- [~] `NetGraph.swift` — value-typed POD structs, `ContiguousArray<Lane>` etc., no class boxing; bounds now union declared metadata with parsed content and benchmark estimates POD memory, large-network measurement pending
- [x] Quadtree spatial index for viewport culling — lane/edge/junction indexes are fixture-tested and feed the viewport subscription planner; GPU render culling remains Day 3/7 work (2026-05-03, codex)
- [~] Bench: `NetParseBenchmark` target and `Scripts/benchmark-net-parse.sh` added; tiny fixture smoke passes, large `.net.xml` < 5s / < 500MB measurement pending

## Day 3 — Metal renderer

### Pipelines (`SumoGUIMac/Render/`)
- [~] `NetworkView.swift` — `NSViewRepresentable` wrapping `MTKView` (static parsed network display works; lanes, junctions, and vehicles now use Metal; renderer polish pending)
- [~] Camera: cursor-anchored zoom, pinch, double-click zoom, drag pan, and trackpad pan are wired; native-editor rubber-band selection is wired, broader camera polish pending
- [~] Lane shader: instanced quad pass with per-lane width, speed-derived colour, selected-edge highlight, and CPU LOD culling below 0.5 px is wired; line joins polish pending
- [~] Junction shader: filled triangle-fan polygons from parsed junction shapes are wired; robust concave triangulation/styling pending
- [~] Vehicle shader: instanced triangle pass with speed/type-derived colour, render-side interpolation, selected-vehicle highlight, and physical screen-size metrics is wired; richer sizing/selection overlay polish pending
- [x] Level-of-detail: cull lanes < 0.5px wide, drop vehicle shape under 2px (2026-05-03, codex)
- [~] Hit-testing: CPU nearest-live-vehicle picking plus nearest non-internal edge/lane picking are wired for map clicks; GPU id-buffer pass still pending
- [ ] Bench: 60 fps with large network + 50k vehicles

## Day 4 — SwiftUI shell

### Window chrome
- [x] Three-pane `NavigationSplitView`: left objects sidebar, centre `NetworkView`, right inspector (2026-05-03, codex)
- [x] Bottom transport bar: open / play / pause / step / delay slider / sim-time / measured speed factor (2026-05-03, codex)
- [x] CLI/open-file launch path: accept `.sumocfg` / `.net.xml` on startup (`-c path` or bare path) plus persisted Open Recent menu (2026-05-03, codex)
- [x] Menu bar: File (Open, Open Recent, Attach to TraCI, Export Screenshot), View (fit/zoom/follow), and Simulation (play/pause/step/stop) command menus (2026-05-03, codex)
- [x] Keyboard shortcuts matching sumo-gui where possible (`⌘O`, `⇧⌘O`, `⌘0`, `⌘=`, `⌘-`, `⌘F`, `space=play/pause`, `s=step`, `⌘.=stop`, `⇧⌘S=export screenshot`) (2026-05-03, codex)
- [x] Inspector tabs: Parameters, Subscriptions, Tracker with Swift Charts time-series (2026-05-03, codex)

## Day 5 — Visualization parity

### Color schemes (matching `GUIColorScheme.cpp`)
- [x] Lane: by speed-limit, by lane number, by occupancy, by edge type, uniform (occupancy polls visible lane values when the mode is active; 2026-05-03, codex)
- [x] Vehicle: by speed, by acceleration, by route, by type, by CO2, by colour-attr, uniform (viewport subscriptions request the broader variables and renderer falls back safely when SUMO omits a value; 2026-05-03, codex)
- [x] Junction: by type, by load (load uses live nearby-vehicle counts with static incoming-lane fallback; 2026-05-03, codex)
- [~] Custom palette editor with import/export to SUMO XML format (SwiftUI palette editor plus SUMO-style `<viewsettings>` XML round-trip is wired; exact upstream schema parity still needs fixture testing against sumo-gui)
- [~] Background: PNG/GeoTIFF decal with georeferencing (PNG/JPEG/TIFF texture decals, manual world bounds, and adjacent world-file georeferencing are wired; native GeoTIFF tag extraction pending)
- [x] POI rendering, polygon rendering (parsed from `.net.xml` and `.sumocfg` additional files; rendered as Metal overlays; 2026-05-03, codex)

### Visualization Settings dialog
- [x] Tabs: Background, Streets, Vehicles, Persons, Containers, Junctions, Detectors, POIs, Legend (2026-05-03, codex)
- [~] Save/load `.xml` settings file (SUMO-style viewsettings import/export is tested; exact sumo-gui compatibility validation pending)

## Day 6 — Inspection, breakpoints, trackers

- [x] Right-click context menu per object class (edge/vehicle sidebar menus support select, add/remove from selection, copy ID, clear selection, follow/stop-follow, select route, and copy route edges; 2026-05-03, codex)
- [x] Selection set persistence + selection-driven colour overlay (persistent edge/vehicle sets are highlighted in the sidebar and Metal renderer while the focused inspector object can change; 2026-05-03, codex)
- [x] Breakpoints panel — list of sim-times to halt at (add/remove/clear, pause-on-crossing, run-to-breakpoint button, and double-click jump/run are wired; 2026-05-03, codex)
- [~] Tracker windows (Swift Charts) — time-series of TraCI-backed global and selected-object variables (vehicle count, playback speed, selected vehicle speed/accel/CO2, selected edge occupancy) are available in the inspector; detached SUMO-style tracker windows and arbitrary variable picking pending
- [x] Vehicle tracking camera (centre-on-selected-vehicle follow mode and rotate-with-heading camera mode are wired; 2026-05-03, codex)
- [x] Route highlighting on hover/selection (hover previews cached route edges; selecting/copying a live vehicle route uses TraCI route-edge fetch and persistent route overlays; 2026-05-03, codex)

## Day 7 — Stability, scale, ship

- [x] Large benchmark scenario script (OSM import via `osmGet.py`/`osmBuild.py`, random-trip route generation, and parser benchmark handoff; 2026-05-03, codex)
- [ ] Run a large benchmark for 1 hour sim time, profile with Instruments — fix top 3 hot paths
- [x] Crash test: kill `sumo` subprocess / drop TraCI connection mid-session, verify UI recovers gracefully without leaving a runnable dead session (2026-05-03, codex)
- [~] Screenshot/video export (PNG export from the current native view is wired; MP4 via AVFoundation pending)
- [~] Notarization-ready build path (`SumoGUIMacApp` Xcode scheme builds a signed local `.app`; `Scripts/build-alpha-release.sh` creates an ad-hoc signed alpha zip; developer-team signing and notarization still pending)
- [x] README with screenshot, install instructions, contributing guide (README includes app icon, live FlowDemo screenshot, build/run/release instructions, interaction notes, contribution loop, and SUMO citation/credits; 2026-05-03, codex)
- [x] NetEdit bridge: open current `.sumocfg`/`.net.xml`, choose a file for NetEdit, or create a new NetEdit network using the user-installed SUMO tools (2026-05-03, codex)
- [x] First clean-room native NetEdit slice: in-app draft network editor with junction creation, edge creation, custom junction shapes, Metal preview, and export to public SUMO node/edge files plus `netconvert` compilation when available (2026-05-03, codex)
- [~] Native editor parity plan: `docs/EDITOR_PARITY_PLAN.md` defines clean-room milestones from simple node/edge editing to demand/additional-object editing and viewer-grade UX parity (2026-05-03, codex)
- [ ] First public tag: `v0.1.0`

---

## Deferred to v2

- [-] 3D view (SceneKit / Metal 3D)
- [-] Multiple synchronised viewports
- [-] Person/pedestrian rendering with full sumo-gui modes
- [-] OSG-equivalent decals
- [-] Full native netedit replacement beyond the bridge workflow
- [-] FMI co-simulation hookup
- [-] Replay mode driven from `.fcd-output` without running SUMO

---

## Handoff state (update at end of every session)

- **Last touched:** 2026-05-04 — codex — Continued native editor precision work. Native Select mode now supports custom junction shape handles: the inspector and Editor menu can convert a radius junction into an editable SUMO node polygon, add/remove shape points, drag visible handles on the canvas, preserve custom shapes when moving junctions, and export node `shape` attributes. Tests now cover custom junction shape editing, graph preview shape updates, node XML export, handle exposure, and reset behavior alongside the existing renderer coordinate conversion, transform round-tripping, grid snapping, edge geometry-point editing/export, duplicate/reverse edges, endpoint editing, junction radius preview/export, Shift-click multi-select, rubber-band selection including crossing edges, bulk delete/undo, rename propagation, public SUMO XML export attributes, and preview graph lane width.
- **Next action:** Continue E1/E2 from `docs/EDITOR_PARITY_PLAN.md`: add object endpoint/background-map hint snapping, begin connection display/selection after `netconvert`, add XML snapshot tests for exported public files, extract editor state from `SimulationViewModel`, and factor shape/geometry handle drawing into a reusable editor overlay. Also run the generated large OSM benchmark for one hour of sim time, profile with Instruments, and live-smoke external attach with `sumo --remote-port <port> --num-clients 2`.
- **Known blockers:** External attach mode needs a live multi-client SUMO smoke test with the controller at one TraCI order and SumoGUIMac at another. The local active SUMO binary reports 1.25.0 while the app target constant is 1.26.0, so the compatibility guard warns until the local runtime is upgraded or the target is intentionally changed. Tracker charts are embedded in the inspector rather than detached SUMO-style tracker windows, and arbitrary TraCI variable picking is still pending. Visualization XML is SUMO-style but has not yet been validated as byte-for-byte compatible with upstream sumo-gui view settings, and background georeferencing currently supports manual bounds plus adjacent world files rather than native GeoTIFF tags. Release signing is local/ad-hoc only; Developer ID signing and notarization are still pending. Junction triangulation is simple fan triangulation, so unusual concave junction shapes may need a more robust tessellator.
- **Local SUMO version targeted:** App target = 1.26.0. Current located binary = `/Library/Frameworks/EclipseSUMO.framework/Versions/Current/EclipseSUMO/bin/sumo`, which reports 1.25.0. SUMO_HOME for the python tools should point at the matching framework's `share/sumo`.

## Lessons learned (read these before debugging)

- **Don't hand-write `.net.xml` for tests.** SUMO validates internal-link geometry strictly and bails before TraCI ever opens. Use `netconvert` to build fixtures from `.nod.xml` + `.edg.xml`. See `Tests/SumoKitTests/Fixtures/tiny.net.xml`.
- **TraCI response shape is per-command.** Status block (lenByte, cmdID, result, descString) is always present. After it: GET-style commands wrap their payload in a `lenByte+cmdID` echo block; SIMSTEP appends a 4-byte sub-result count + N sub-result blocks; CLOSE has nothing. `sendCommand` returns the bytes after status; each domain method parses its own tail.
- **`NWConnection` is finicky here.** We use raw `Darwin.socket` + `TCP_NODELAY` to mirror SUMO's Python client; that worked first try.
- **SUMO boolean options can be passed bare.** Prefer `--no-step-log` / `--no-warnings` without `true`; SUMO also accepts `--flag value` form for bool options, but the value is not required.
