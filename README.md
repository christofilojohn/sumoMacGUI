<p align="center">
  <img src="Sources/SumoGUIMac/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png" alt="SumoGUIMac app icon" width="128" height="128">
</p>

<h1 align="center">SumoGUIMac</h1>

<p align="center">
  Native macOS SUMO GUI
</p>

A native macOS port of [Eclipse SUMO](https://eclipse.dev/sumo/)'s `sumo-gui` — SwiftUI + Metal, full TraCI connectivity, built to open normal SUMO `.sumocfg` workflows on macOS.

> **Status: pre-alpha.** The engine core builds and the native app can open `.sumocfg`, launch SUMO, step/play, render lanes/junctions/live vehicles in Metal, and inspect selected vehicles or edges. Track real progress in [`docs/CHECKLIST.md`](docs/CHECKLIST.md).

<p align="center">
  <img src="assets/sumoguimac-flowdemo-running.png" alt="SumoGUIMac running the included FlowDemo SUMO scenario on macOS" width="900">
</p>

<p align="center">
  <sub>SumoGUIMac running <code>Examples/FlowDemo/flowdemo.sumocfg</code> with live vehicles, lane coloring, inspector metrics, and playback controls.</sub>
</p>

## Why

`sumo-gui` works with some severe visual issues and lacks a lot of the functionalities of a native mac app. It's a FOX-toolkit/OpenGL app that doesn't feel native on macOS. This is a from-scratch SwiftUI rewrite that talks to the same SUMO engine over TraCI, so any existing `.sumocfg` Just Works.

## Goals

- Functionally indistinguishable from `sumo-gui` for everyday use
- Smooth rendering for large real-world networks
- Native macOS HIG, dark mode, sandboxing-ready
- Open-source (MIT) and contributor-friendly

## Status snapshot

See [`docs/CHECKLIST.md`](docs/CHECKLIST.md) — single source of truth.

## Requirements

- macOS 14+, Xcode 15.4+ / Swift 5.10+
- A working Eclipse SUMO install (provides the `sumo` binary used over TraCI). `Scripts/find-sumo.sh` checks common Homebrew / `EclipseSUMO.framework` locations.
- The included `Examples/Tiny/tiny.sumocfg` is a small smoke scenario for local testing.
- The included `Examples/FlowDemo/flowdemo.sumocfg` is the better visual smoke test shown in the screenshot.

## Build & run

```sh
swift build
swift run SumoGUIMac
```

For a real macOS `.app` bundle with the app icon:

```sh
xcodebuild -project SumoGUIMac.xcodeproj -scheme SumoGUIMacApp -configuration Debug -destination platform=macOS build
```

For an alpha release zip:

```sh
Scripts/build-alpha-release.sh 0.1.0-alpha
```

The script writes `SumoGUIMac.app` and `SumoGUIMac-0.1.0-alpha-macOS-arm64.zip` under `.build/`. Alpha builds are ad-hoc signed for local testing and are not notarized yet.

To open a file on launch, more like `sumo-gui`:

```sh
swift run SumoGUIMac -- -c Examples/Tiny/tiny.sumocfg
# or
swift run SumoGUIMac -- Examples/Tiny/tiny.sumocfg
```

The example path is only a smoke-test input. The GUI is intended to open ordinary SUMO `.sumocfg` and `.net.xml` files, not a specific scenario.

For scale testing, generate a larger Athens, Greece OSM-derived scenario under `.build/benchmarks`:

```sh
Scripts/make-large-benchmark-scenario.sh --preset athens
```

This builds a SUMO network, generates random-trip demand, writes a runnable `.sumocfg`, and records parser benchmark output beside the generated files.

To visualize an existing controller/MAPPO run, start SUMO externally with TraCI enabled and enough clients, then use **File > Attach to TraCI...** in the app:

```sh
sumo -c path/to/scenario.sumocfg --remote-port 8813 --num-clients 2
```

Your controller and SumoGUIMac should use different TraCI client orders. The app loads the matching `.sumocfg`/`.net.xml` for geometry, then attaches as a viewer client.

To edit or create scenarios with SUMO's official editor, use **File > Open Current in NetEdit**, **File > Open File in NetEdit...**, or **File > New Network in NetEdit**. This launches the user-installed `netedit` binary beside SUMO; full native editing is planned as a later clean-room port.

The first native editing slice is also available under **File > New Native Network Draft**. It lets you add junctions, connect them with edges on the canvas, drag junctions, Shift-click or drag a selection box to multi-select, add and drag edge bend points, edit edge endpoints, tune junction radius or custom junction shape points, duplicate/reverse edges, toggle grid snapping, undo/redo edits, adjust core junction/edge attributes, preview the result in Metal, and export SUMO-compatible `.nod.xml` / `.edg.xml` sources plus a compiled `.net.xml` when `netconvert` is installed.

## Tests

```sh
swift test
```

Some tests round-trip against a live SUMO process; if `sumo` isn't on `PATH`, those skip.

## Map interaction

- Drag — pan
- Scroll (precise) — pan
- Cmd+scroll, Option+scroll, scroll wheel — zoom at cursor
- Two-finger pinch — zoom at cursor *(Apple trackpad only — Magic Mouse does not generate pinch events at the OS level)*
- Double-click — zoom in (Option+double-click — zoom out)
- `Cmd+=` / `Cmd+-` — zoom in / out
- `Cmd+0` — fit network to window
- `Space` — play / pause
- `s` — step once
- `Cmd+.` — stop the current run without closing the SUMO session
- Toolbar **Fit** — refit network to window
- Toolbar **Zoom In** / **Zoom Out** — device-agnostic zoom buttons
- Click a live vehicle or lane — select it and show details in the inspector

See [`docs/DEV_SETUP.md`](docs/DEV_SETUP.md) for full SUMO setup and test details.

## Contributing

1. Read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
2. Pick an unchecked box in [`docs/CHECKLIST.md`](docs/CHECKLIST.md).
3. Open a PR. Tick the box, add a `CHANGELOG.md` line.
4. New architectural decisions go in [`docs/DECISIONS.md`](docs/DECISIONS.md).

## License

MIT. See [`LICENSE`](LICENSE).

## Credits and Citation

SumoGUIMac builds on the ecosystem around [Eclipse SUMO](https://eclipse.dev/sumo/) ("Simulation of Urban MObility"), the open-source microscopic traffic simulation package used as the external simulation runtime for this app.

Eclipse SUMO is mainly developed by employees of the [Institute of Transportation Systems at the German Aerospace Center (DLR)](https://www.dlr.de/ts/en/). Please credit and cite the SUMO project when using SumoGUIMac for research, publications, demos, or derived work:

- Eclipse SUMO project: <https://github.com/eclipse-sumo/sumo>
- SUMO documentation: <https://sumo.dlr.de/docs>
- SUMO DOI: [10.5281/zenodo.18406080](https://doi.org/10.5281/zenodo.18406080)
- SUMO license: [Eclipse Public License 2.0](https://www.eclipse.org/legal/epl-2.0/)

SumoGUIMac does not bundle or redistribute SUMO binaries or SUMO source code. It talks to a user-installed SUMO runtime over TraCI. This project is **not** affiliated with or endorsed by the SUMO maintainers.
