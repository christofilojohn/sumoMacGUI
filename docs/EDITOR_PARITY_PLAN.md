# Native Editor Parity Plan

This plan describes how SumoGUIMac can grow a NetEdit-style editor while keeping
the project MIT-licensed. The editor must be implemented from public SUMO file
formats, command-line behavior, documentation, screenshots, and hands-on use of
the official tools. Do not copy, paste, translate, or mechanically port upstream
SUMO / NetEdit implementation code.

## License Position

SumoGUIMac can stay MIT while it provides both:

- a viewer / simulation GUI that talks to a user-installed SUMO runtime over
  TraCI, and
- a native editor that writes public SUMO input files and optionally invokes
  user-installed SUMO tools such as `netconvert`, `duarouter`, and `netedit`.

The bright line is source provenance. Public behavior and public formats are
fine. Copied or mechanically translated SUMO / NetEdit implementation code is
not fine in the MIT app unless it is isolated, attributed, and explicitly
licensed under EPL-2.0 after review.

## Current State

- Official NetEdit bridge exists: open current file, choose another file, or
  start a new network in the installed `netedit` app.
- Clean-room native draft mode exists: Select, Junction, and Edge tools create a
  simple editable network, rebuild a Metal preview graph, and export `.nod.xml`
  / `.edg.xml` plus compiled `.net.xml` when `netconvert` is available.
- Native junction shapes can be customized as public SUMO node polygons and
  exported through the node `shape` attribute.
- Contributor guidance now records the no-copying boundary.

## What Editor Parity Means

Editor parity with the current SumoGUIMac viewer does not mean full upstream
NetEdit parity immediately. It means the native editor should feel as complete
and coherent as the current viewer:

- It has a visible mode/tool model, stable canvas interactions, keyboard
  shortcuts, inspector state, sidebar state, and context menus.
- It can round-trip useful SUMO scenarios through public source files.
- It validates edits and explains SUMO tool errors in the UI.
- It hands edited networks back to the simulation viewer without leaving the app.
- It has tests for model behavior, exported XML, and tool handoff paths.

Full upstream NetEdit parity remains a larger multi-release goal.

## Milestones

### E0 — Bridge and First Draft Slice

Status: mostly done.

- [x] Launch installed NetEdit for full official editing workflows.
- [x] Add clean-room contributor license boundary.
- [x] Add native draft mode with Select / Junction / Edge tools.
- [x] Export public `.nod.xml` and `.edg.xml` files.
- [x] Compile with `netconvert` when available.

Acceptance: a user can create two junctions, connect them, export a network, and
open or simulate the compiled output.

### E1 — Editor Architecture

Move editor code out of `SimulationViewModel` into a small editor module once
the behavior stabilizes.

- [ ] Add `NativeEditorDocument` for draft state, source URLs, dirty flag, and
  export targets.
- [ ] Add `NativeEditorModel` for junctions, edges, lanes, connections, and
  additional objects.
- [ ] Add `NativeEditorController` or focused view-model methods for tool
  actions.
- [x] Add command stack for undo / redo.
- [~] Add stable ID generation and rename validation. Generated IDs are stable
  and junction/edge rename validation is wired; broader SUMO ID diagnostics are
  pending.

Acceptance: editor state is testable without booting the full simulation
view-model, and every edit can be undone/redone.

### E2 — Network Editing Core

Bring the basic road-network workflow to parity with the viewer's current
selection and inspection polish.

- [x] Move selected junctions with drag.
- [x] Move selected edge geometry points.
- [x] Delete with keyboard and context menu.
- [x] Multi-select via Shift-click and rubber-band selection.
- [~] Edit edge attributes: ID, priority, speed, lane count, lane width, spread
  type, from/to junctions, and allowed/disallowed classes are wired; richer
  lane attributes are pending.
- [x] Edit junction attributes: ID, type, position, radius, and custom node
  shape points are wired.
- [~] Add snapping to junctions, lane endpoints, grid, and background map hints.
  Grid snapping is wired for canvas add and drag move; object endpoint and map
  hint snapping are pending.
- [x] Add duplicate edge and reverse edge actions.

Acceptance: a user can create, inspect, adjust, delete, and export a small
multi-edge road network without opening official NetEdit.

### E3 — Connections and Traffic Lights

SUMO networks become useful when lane-to-lane connections and TLS programs are
visible and editable.

- [ ] Display generated connections after `netconvert`.
- [ ] Add connection selection and inspector details.
- [ ] Write explicit `.con.xml` files for user-edited connections.
- [ ] Add traffic-light junction mode.
- [ ] Add TLS phase table editor using public SUMO TLS XML.
- [ ] Show connection conflicts and missing-turn diagnostics from SUMO tools.

Acceptance: a user can create an intersection, choose allowed turns, assign a
traffic light, export it, and run it in the simulation viewer.

### E4 — Demand Editing

Match the first workflows people use NetEdit for after drawing a network:
vehicles, trips, routes, and flows.

- [ ] Add demand mode beside network mode.
- [ ] Add vehicle type editor.
- [ ] Add route editor with edge picking.
- [ ] Add trip and flow creation tools.
- [ ] Export `.rou.xml`.
- [ ] Validate routes with user-installed SUMO routing tools where appropriate.
- [ ] Preview demand overlays in the viewer.

Acceptance: a user can draw a small network, add flows, export a runnable
`.sumocfg`, and watch vehicles move in SumoGUIMac.

### E5 — Additional Objects

Add the common non-road objects needed for practical scenarios.

- [ ] POIs and polygons with shape editing.
- [ ] Bus stops, charging stations, parking areas, calibrators, detectors.
- [ ] Additional-file manager in the inspector.
- [ ] Object visibility filters and sidebar grouping.
- [ ] Export `.add.xml` files.

Acceptance: common additional objects can be edited, saved, reloaded, and
rendered in the same viewer.

### E6 — Import and Round Trip

Editing existing scenarios safely is harder than creating new ones. Treat this
as its own milestone.

- [ ] Import public source files when present: `.nod.xml`, `.edg.xml`,
  `.con.xml`, `.tll.xml`, `.rou.xml`, `.add.xml`.
- [ ] For `.net.xml`-only inputs, support simplified editing with clear warnings
  about generated/internal data.
- [ ] Preserve unknown XML attributes where possible through structured sidecars
  or explicit unsupported-field warnings.
- [ ] Add "Open in official NetEdit" escape hatch from every editor document.

Acceptance: editing an existing public-source SUMO scenario does not silently
drop supported objects or attributes.

### E7 — Editor UX Parity With Viewer

Make the editor feel like a first-class part of SumoGUIMac rather than a side
panel bolted on.

- [ ] Dedicated Editor menu with tool shortcuts.
- [ ] Context menus for every editable object class.
- [ ] Inspector tabs for Parameters, Validation, and Generated Output.
- [ ] Inline validation badges in sidebar rows.
- [ ] Save, Save As, Revert, Export Compiled Network, and Open Compiled Network.
- [ ] Dirty-state window title and close confirmation.
- [ ] Palette/visibility settings shared with viewer.

Acceptance: the editor follows the same interaction quality as the simulation
GUI: discoverable, keyboard-friendly, inspectable, and resilient.

### E8 — Hardening and Release Gate

Before claiming alpha editor support:

- [ ] Unit tests for editor model operations.
- [ ] XML snapshot tests for exported public files.
- [ ] Tool-integration tests for `netconvert` when installed.
- [ ] App smoke test: create network, export, run simulation.
- [ ] Large-edit performance test with hundreds of junctions/edges.
- [ ] Documentation with a tiny "build a network from scratch" tutorial.

Acceptance: editor workflows survive repeated use and failures are readable
instead of destructive.

## Recommended Next Slice

Continue E1/E2 with the next precision and structure work:

1. Extract editor state from `SimulationViewModel`.
2. Add object endpoint and background-map hint snapping.
3. Add connection display/selection after `netconvert`.
4. Add XML snapshot tests for exported public files.
5. Extract shape/geometry handle rendering into a reusable editor overlay.

That will make the native editor feel like the current viewer: not complete yet,
but coherent enough to use and iterate on.
