# SumoGUIMac

A native macOS port of [Eclipse SUMO](https://eclipse.dev/sumo/)'s `sumo-gui`, written in SwiftUI + Metal, targeting feature parity with `sumo-gui` 1.26.0 over TraCI.

**Status:** pre-alpha native app in progress — TraCI core green; native SwiftUI app opens `.sumocfg`, launches SUMO, attaches to external TraCI runs, steps/plays, renders lanes/junctions/live vehicles in Metal, supports basic object inspection, and builds as a local Xcode `.app` bundle.
**License:** MIT (open-source, contributions welcome)
**SUMO distribution:** not bundled; users install SUMO separately and the app talks to it over TraCI.
**Author:** christoi@tcd.ie

---

## Why

`sumo-gui` is a FOX-toolkit C++/OpenGL app — functional, but not a native Mac citizen. This project provides:

- A SwiftUI shell that follows macOS HIG (menubar, sidebars, dark mode, sandboxing-friendly).
- A Metal renderer that scales to large real-world SUMO networks.
- TraCI connectivity against a separate user-installed SUMO runtime.
- An open-source codebase that any contributor — or another agent — can pick up via `CHECKLIST.md`.

## North-star use case

Open existing SUMO `.sumocfg` files in a native macOS GUI, watch and control the simulation, inspect objects, and swap controllers via TraCI. For algorithm experiments, the controller can run SUMO directly while SumoGUIMac attaches as a viewer over TraCI.

## Non-goals (v1)

- `netedit` (network editor) — separate effort, defer.
- Windows/Linux builds — Mac-only, by design.
- 3D mode (OSG/SceneKit) — defer to v2.

---

## Architecture (one paragraph)

Two Swift Packages: `SumoKit` (engine: TraCI client, `.net.xml` parser, spatial index, render data model) and `SumoGUIMac` (the macOS app: SwiftUI views + Metal `NetworkView`). The app can spawn `sumo --remote-port` as a subprocess or attach to an already-running TraCI server; the renderer reads from a `NetGraph` (static geometry, parsed once) and a `SimulationState` (live, updated per step via TraCI subscriptions). See [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Quick links

- [CHECKLIST.md](docs/CHECKLIST.md) — parity progress + handoff state. **Update this every session.**
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the pieces fit, where to add things.
- [DECISIONS.md](docs/DECISIONS.md) — log of architectural choices and their rationale.
- [DEV_SETUP.md](docs/DEV_SETUP.md) — how to build & run.

## How to continue this work (for humans and agents)

1. Read `docs/CHECKLIST.md` top-to-bottom. Find the first unchecked box.
2. Read `docs/ARCHITECTURE.md` to know where that box's code lives.
3. Implement, then check the box and append a one-line entry to `docs/CHANGELOG.md`.
4. If you make an architectural decision, add a row to `docs/DECISIONS.md`.
5. Never claim a feature works without testing it against a real `.sumocfg`. Large scenarios are scale tests, not prerequisites for everyday app features.
