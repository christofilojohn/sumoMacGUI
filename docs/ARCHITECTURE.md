# Architecture

## Layered view

```
┌─────────────────────────────────────────────────────────────┐
│  SumoGUIMac (app target — SwiftUI + Metal)                  │
│  ───────────────────────────────────────                    │
│  App/         scenes, commands, document model              │
│  UI/          MainWindow, Inspector, TransportBar,          │
│               ViewSettings, Tracker, ContextMenus           │
│  Render/      NetworkView (MTKView), NetworkRenderer,       │
│               Camera, Picker, ColorScheme, Shaders.metal    │
│  ViewModels/  SimulationViewModel (ObservableObject)        │
└──────────────────────────┬──────────────────────────────────┘
                           │ depends on
┌──────────────────────────▼──────────────────────────────────┐
│  SumoKit (engine — pure Swift, no UI)                       │
│  ───────────────────────────────                            │
│  Backend/   SumoBackend protocol                            │
│             TraCI client, SUMO launcher, socket transport   │
│             SumoLauncher (Process), TraCIWire, TraCIConn    │
│             Domains: Simulation, Vehicle, Edge, Lane, ...   │
│  Net/       NetXMLParser → NetGraph (POD structs)           │
│             Quadtree spatial index                          │
│  Model/     SimulationState, ViewportState, Selection       │
└──────────────────────────┬──────────────────────────────────┘
                           │ talks TCP to
┌──────────────────────────▼──────────────────────────────────┐
│  sumo (subprocess or external TraCI server, 1.26+)           │
│  spawned or attached over TCP with TraCI subscriptions       │
└─────────────────────────────────────────────────────────────┘
```

## Key contracts

### `SumoBackend` protocol
The app-facing backend API is async-only. The current implementation talks to a separate SUMO process over TraCI TCP, whether the app launched that process or attached to one started by an external controller.

```swift
protocol SumoBackend: AnyObject {
    func open(config: URL) async throws
    func step(_ count: Int = 1) async throws
    func close() async

    // bulk reads driven by subscriptions, not point queries
    var liveState: AsyncStream<SimulationState> { get }

    // typed domains
    var simulation: SimulationDomain { get }
    var vehicle: VehicleDomain { get }
    var edge: EdgeDomain { get }
    var lane: LaneDomain { get }
    var junction: JunctionDomain { get }
    var trafficLight: TrafficLightDomain { get }
    var gui: GUIDomain { get }
}
```

### Why subscriptions, not polling
TraCI round-trips are expensive. For a viewport showing N vehicles we issue **one** `subscribeContext` and SUMO pushes a per-step bundle of `(id, x, y, angle, speed, type)` rows. Without this, large scenarios fall over.

### Why streaming `.net.xml`
OSM-derived and city-scale networks can be 50–200MB XML. Loading the whole DOM blows out memory; SAX-style streaming keeps it under 500MB resident.

### Renderer = pure data sink
`NetworkRenderer` only consumes:
- a `NetGraph` (immutable after load)
- the latest `SimulationState` snapshot
- a `ViewportState` (camera + selection)

It owns no simulation logic. This keeps it testable and lets us swap app-facing data sources such as live TraCI or replay-from-FCD.

## External controller workflow

For dissertation experiments, a scheduler/controller can run in a separate process and own the algorithm. SumoGUIMac loads the same `.sumocfg`/`.net.xml` for geometry and attaches to the already-running SUMO TraCI server as another client. That keeps MAPPO or other scheduling code outside the GUI while still allowing native visualization, selection, and inspection.

## File-level map

| Concern | Lives in | Notes |
|---|---|---|
| Spawning SUMO | `SumoKit/Backend/SumoLauncher.swift` | wraps `Process`, parses port, forwards stderr |
| TraCI bytes | `SumoKit/Backend/TraCIWire.swift` | unit-tested against captured fixtures |
| TraCI commands | `SumoKit/Backend/Domains/*.swift` | one file per domain |
| `.net.xml` | `SumoKit/Net/NetXMLParser.swift` + `NetGraph.swift` | quadtree in `SumoKit/Net/Quadtree.swift`; graph builds lane/edge/junction indexes |
| Metal pipelines | `SumoGUIMac/Render/NetworkRenderer.swift` + `Shaders.metal` | instanced draw calls |
| Hit-testing | `SumoGUIMac/Render/Picker.swift` | id-buffer pass on a 1×1 scissor |
| Color schemes | `SumoGUIMac/Render/ColorScheme.swift` | mirrors `GUIColorScheme.cpp` |
| App state | `SumoGUIMac/ViewModels/SimulationViewModel.swift` | `@MainActor` + `ObservableObject` |

## Threading

- TraCI I/O: dedicated `actor TraCIConnection` on a background `DispatchQueue`.
- Step loop: `Task` driven by transport bar play/pause; awaits `step` then publishes a new `SimulationState` to the main actor.
- Metal: render thread is `MTKView`'s draw callback; reads an immutable snapshot, never blocks on TraCI.

## Where new contributors should start
1. Pick the first unchecked task in `CHECKLIST.md`.
2. Open the matching file from the table above (or create it under the right folder).
3. Add a unit test in `Tests/SumoKitTests/` if it's engine code.
4. Tick the box, add a CHANGELOG line.
