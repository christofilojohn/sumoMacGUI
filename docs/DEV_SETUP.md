# Dev Setup

## Prerequisites

- macOS 14+ (Sonoma) on Apple Silicon or Intel
- Xcode 15.4+
- Swift 5.10+
- SUMO 1.26.0 (we target a specific version; newer may work but isn't tested)

### Install SUMO

Either:

**A. Official Eclipse framework (recommended, what this repo targets):**
Download the `.pkg` from <https://eclipse.dev/sumo/> → `EclipseSUMO.framework` lands in `/Library/Frameworks/`.
`sumo` resolves to `/Library/Frameworks/EclipseSUMO.framework/Versions/Current/EclipseSUMO/bin/sumo`.

**B. Homebrew tap:**
```sh
brew tap dlr-ts/sumo
brew install --cask sumo-gui
```

`Scripts/find-sumo.sh` resolves either layout.

## Build & run

```sh
git clone <this-repo>
cd SumoGUIMac
swift run SumoGUIMac
```

Build the macOS app bundle from the shared Xcode scheme:

```sh
xcodebuild -project SumoGUIMac.xcodeproj -scheme SumoGUIMacApp -configuration Debug -destination platform=macOS build
```

Build an alpha release zip:

```sh
Scripts/build-alpha-release.sh 0.1.0-alpha
```

The release script builds the shared Xcode scheme with `Release` configuration,
verifies the local ad-hoc signature, and writes:

- `.build/XcodeDerivedData-Release/Build/Products/Release/SumoGUIMac.app`
- `.build/releases/SumoGUIMac-0.1.0-alpha-macOS-arm64.zip`

These alpha artifacts are suitable for local testing and GitHub pre-releases,
but they are not Developer ID signed or notarized yet.

Open a config directly on launch:

```sh
swift run SumoGUIMac -- -c Examples/Tiny/tiny.sumocfg
```

Headless engine tests:
```sh
swift test
```

## Smoke scenario

```sh
swift run SumoGUIMac
# File > Open... and choose any .sumocfg or .net.xml
```

or:

```sh
swift run SumoGUIMac -- Examples/Tiny/tiny.sumocfg
```

Large real-world networks are used as scale benchmarks once the core GUI path works, but they are not required for the basic smoke path.

## Scale benchmark scenario

Generate an Athens, Greece OSM-derived benchmark network and route set under `.build/benchmarks`:

```sh
Scripts/make-large-benchmark-scenario.sh --preset athens
```

The script locates the installed SUMO tools, downloads or imports OSM data, builds a `.net.xml` with `osmBuild.py`, generates roughly 50k random trips over one simulated hour with `randomTrips.py`, writes a matching `.sumocfg`, and runs `NetParseBenchmark` against the generated network.

Use your own OSM extract when working offline or benchmarking a dissertation scenario:

```sh
Scripts/make-large-benchmark-scenario.sh --osm ~/Downloads/city.osm.xml --prefix city-benchmark --vehicles 25000
```

Open the generated `.sumocfg` in SumoGUIMac for an app-level smoke test, or run the generated `.net.xml` directly through:

```sh
Scripts/benchmark-net-parse.sh .build/benchmarks/osm-large/sumogui-large.net.xml
```

## Attach to an external TraCI run

For controller experiments, including a separate MAPPO scheduler, run SUMO yourself and attach the native app as a viewer:

```sh
sumo -c path/to/scenario.sumocfg --remote-port 8813 --num-clients 2
```

Then choose **File > Attach to TraCI...** and select the matching `.sumocfg` or `.net.xml` so the renderer has static geometry. Use a client order that does not collide with your controller. For example, keep the controller at order `1` and attach SumoGUIMac at order `2`.

## Editing with NetEdit

The first editing integration is a bridge to SUMO's installed `netedit` application:

- **File > Open Current in NetEdit** opens the currently loaded `.sumocfg` with `netedit --sumocfg-file` or the currently loaded `.net.xml` with `netedit -s`.
- **File > Open File in NetEdit...** lets you choose another `.sumocfg` or `.net.xml`.
- **File > New Network in NetEdit** launches `netedit --new-network`.

The first clean-room native editing slice lives beside that bridge:

- **File > New Native Network Draft** starts an in-app editable network.
- Use the native editor bar to switch between Select, Junction, and Edge tools.
- Select mode supports junction dragging plus undo/redo from the editor bar or
  **Editor > Undo/Redo Native Editor Change**.
- Shift-click or Command-click native junctions/edges in Select mode, or drag a
  selection rectangle across empty canvas, to build a multi-selection; Delete
  removes the selected objects as a group.
- Enable the grid button in the native editor bar to snap canvas-created
  junctions and dragged junction moves to the configured meter interval.
- Select an edge and use **Add Point** in the inspector to insert a bend point
  on the longest segment. Drag bend points in Select mode; exported `.edg.xml`
  files include the resulting SUMO `shape` attribute.
- Select a junction and use **Customize Shape** to turn its radius box into an
  editable SUMO node polygon. Drag the visible shape handles in Select mode;
  exported `.nod.xml` files include the resulting node `shape` attribute.
- Use the selected-edge inspector or **Editor** menu to duplicate an edge or
  create its reverse-direction counterpart.
- Use the selected-edge inspector to retarget From/To junction endpoints.
- The inspector can edit junction/edge IDs, junction type/position, and edge
  priority, lanes, speed, width, spread type, and allow/disallow vehicle classes.
  Junction radius edits affect the Metal preview and export as SUMO node
  `radius` attributes when changed from the default and no custom shape is set.
- Export writes public SUMO `.nod.xml` and `.edg.xml` files. If `netconvert` is installed, the app also compiles a `.net.xml` and matching `.sumocfg`.

This keeps full editing workflows available while native Swift editing is ported feature-by-feature. Do not copy upstream NetEdit implementation code into the MIT app; use upstream behavior as reference and implement native editing cleanly.

## Where things go

See [ARCHITECTURE.md](ARCHITECTURE.md). TL;DR: engine code in `Sources/SumoKit/`, app code in `Sources/SumoGUIMac/`.
