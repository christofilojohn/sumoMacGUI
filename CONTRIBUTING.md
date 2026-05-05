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

## SUMO and NetEdit license boundary

SumoGUIMac is MIT-licensed and interoperates with Eclipse SUMO as a separate,
user-installed runtime. Keep that boundary intact:

- Do not copy, paste, translate, or mechanically port SUMO / NetEdit source code,
  tests, UI resources, or generated implementation tables into this repository.
- It is fine to implement fresh Swift code from public behavior: SUMO file
  formats, TraCI protocol behavior, command-line behavior, documentation,
  screenshots, and hands-on observation of the official apps.
- Keep upstream SUMO clones under ignored scratch paths such as `.build/`.
  Never commit upstream source snapshots unless a license review says to do so.
- If a change truly needs copied or derived SUMO code, stop before committing it.
  Preserve upstream notices, document the affected files, and decide explicitly
  whether those files or the project need EPL-2.0 licensing.

## Code style

- Swift 5.10, `swift-format` on default settings (config will land in Day 1).
- Prefer value types and `actor` for mutable shared state.
- `MainActor`-annotate anything UI-touching.

## Reporting issues

Open a GitHub issue with: SUMO version, macOS version, the `.sumocfg` or `.net.xml` you used, and a stderr/console excerpt.
