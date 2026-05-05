# Architectural Decisions Log

One row per decision. Append-only. Don't rewrite history; if a decision is reversed, add a new row that supersedes it.

| # | Date | Decision | Rationale | Supersedes |
|---|---|---|---|---|
| 1 | 2026-05-01 | TraCI (TCP) as the v1 backend, not embedded SUMO | Pure Swift, no C++ interop, no dylib bundling/codesigning headaches. Performance is good enough for large scenarios if subscriptions are used, and SUMO remains a separate user-installed runtime. | — |
| 2 | 2026-05-01 | Metal, not SwiftUI Canvas, for the network view | Canvas is CPU-bound on large networks. Need GPU draws to hit interactive frame rates. | — |
| 3 | 2026-05-01 | Streaming SAX `.net.xml` parser, not full DOM | Large `.net.xml` files can be tens or hundreds of MB. DOM load multiplies that in memory; SAX keeps the working set bounded. | — |
| 4 | 2026-05-01 | Subscriptions, not polling, for vehicle state | TraCI per-call round-trip dominates at scale. `subscribeContext` ships a bundle per step. | — |
| 5 | 2026-05-01 | Two SwiftPM modules: `SumoKit` (engine) + `SumoGUIMac` (app) | Lets contributors and CI run the engine headlessly. Also lets future tools (CLI replayer, headless validator) reuse `SumoKit`. | — |
| 6 | 2026-05-01 | Target SUMO 1.26.0 first, version-gate later | TraCI protocol has minor version churn; pin one to ship, then expand. | — |
| 7 | 2026-05-01 | macOS 14+ only | SwiftUI APIs we want (Inspector modifier, Observation, Swift Charts) need 14. Drops <2% of users. | — |
| 8 | 2026-05-01 | App Sandbox **off** at first | We spawn `sumo` and read user-chosen `.sumocfg` paths anywhere. Re-enable with proper entitlements before notarized release. | — |
| 9 | 2026-05-01 | External TraCI attach mode is first-class | Dissertation/controller workflows can run SUMO and scheduling code outside the GUI, while SumoGUIMac attaches as a viewer client with its own TraCI order. | 1 |
| 10 | 2026-05-03 | NetEdit comes in as a bridge first, then clean-room native editing | Upstream `netedit` is a large EPL-2.0 C++/FOX application. SumoGUIMac can launch the user-installed editor for full editing workflows now, while native Swift editing should be ported feature-by-feature without copying upstream implementation code into the MIT app. | — |
| 11 | 2026-05-03 | Native editing starts from public SUMO file behavior | The first in-app editor writes public `.nod.xml` and `.edg.xml` inputs and optionally calls `netconvert`; it does not copy or translate upstream NetEdit implementation code. | 10 |
