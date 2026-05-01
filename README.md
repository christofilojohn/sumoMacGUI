<p align="center">
  <img src="Sources/SumoGUIMac/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png" alt="SumoGUIMac app icon" width="128" height="128">
</p>

<h1 align="center">SumoGUIMac</h1>

<p align="center">
  Native macOS SUMO GUI
</p>

A native macOS port of [Eclipse SUMO](https://eclipse.dev/sumo/)'s `sumo-gui` — SwiftUI + Metal, full TraCI connectivity, built to open normal SUMO `.sumocfg` workflows on macOS.

> **Status: pre-alpha.** The engine core builds and the native app can open `.sumocfg`, launch SUMO, step/play, render lanes/junctions/live vehicles in Metal, and inspect selected vehicles or edges. Track real progress in [`docs/CHECKLIST.md`](docs/CHECKLIST.md).

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

- macOS 14+, Xcode 15+ / Swift 5.9+
- A working Eclipse SUMO install (provides the `sumo` binary used over TraCI). `Scripts/find-sumo.sh` checks common Homebrew / `EclipseSUMO.framework` locations.
- The included `Examples/Tiny/tiny.sumocfg` is a small smoke scenario for local testing.

## Build & run

```sh
swift build
swift run SumoGUIMac
```

For a real macOS `.app` bundle with the app icon:

```sh
xcodebuild -project SumoGUIMac.xcodeproj -scheme SumoGUIMacApp -configuration Debug -destination platform=macOS build
```

To open a file on launch, more like `sumo-gui`:

```sh
swift run SumoGUIMac -- -c Examples/Tiny/tiny.sumocfg
# or
swift run SumoGUIMac -- Examples/Tiny/tiny.sumocfg
```

The example path is only a smoke-test input. The GUI is intended to open ordinary SUMO `.sumocfg` and `.net.xml` files, not a specific scenario.

To visualize an existing controller/MAPPO run, start SUMO externally with TraCI enabled and enough clients, then use **File > Attach to TraCI...** in the app:

```sh
sumo -c path/to/scenario.sumocfg --remote-port 8813 --num-clients 2
```

Your controller and SumoGUIMac should use different TraCI client orders. The app loads the matching `.sumocfg`/`.net.xml` for geometry, then attaches as a viewer client.

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
