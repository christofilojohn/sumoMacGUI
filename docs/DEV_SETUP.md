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

## Where things go

See [ARCHITECTURE.md](ARCHITECTURE.md). TL;DR: engine code in `Sources/SumoKit/`, app code in `Sources/SumoGUIMac/`.
