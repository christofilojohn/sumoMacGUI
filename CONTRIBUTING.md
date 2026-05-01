# Contributing

This project is built to be picked up by anyone.

## The handoff loop

1. **Read [`docs/CHECKLIST.md`](docs/CHECKLIST.md).** It's the only source of truth on what's done.
2. Pick the first unchecked box. If you want to grab a different one, leave a note on the previous one (`[~]` + your handle).
3. Find where the code lives via [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)'s file-level map.
4. Implement it. Write a unit test if it's `SumoKit` code.
5. Test UI-facing work against a real SUMO `.sumocfg` or `.net.xml`; use large scenarios as benchmarks, not as the definition of correctness.
6. Append one line to `docs/CHANGELOG.md` and update the "Handoff state" block at the bottom of the checklist.

## House rules

- **No silent scope creep.** If you need to add something not on the checklist, add a row first, then do it.
- **No dead code.** If you ripped something out, delete it; don't leave commented blocks.
- **No comments explaining what code does.** Only why — non-obvious constraints, workarounds for specific bugs.
- **Architectural choices go in [`docs/DECISIONS.md`](docs/DECISIONS.md).** Append-only.

## Code style

- Swift 5.10, `swift-format` on default settings (config will land in Day 1).
- Prefer value types and `actor` for mutable shared state.
- `MainActor`-annotate anything UI-touching.

## Reporting issues

Open a GitHub issue with: SUMO version, macOS version, the `.sumocfg` or `.net.xml` you used, and a stderr/console excerpt.
