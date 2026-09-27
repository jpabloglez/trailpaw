# ADR-004: Floating origin instead of a double-precision engine build

- **Status:** Accepted
- **Date:** 2026-09-27

## Context
32-bit floats lose precision a few kilometres from the origin, causing jittery animation
and physics. The world is effectively endless. Godot can be compiled with
`precision=double`, but that means custom engine and export-template builds.

## Decision
Use the stock engine and a `FloatingOrigin` autoload: when the player is further than
`REBASE_DISTANCE` (e.g. 2 km) from the local origin, shift every root node back by the
offset and accumulate it in `GameState` as an absolute world offset.

## Consequences
- Official Godot binaries and templates, simple CI and upgrades.
- Everything that stores positions must tolerate a rebase (listen for it or store
  positions relative to chunks).
- Distance-driven logic (biomes, saves) must use absolute coordinates, never the rebased
  local position.
- Revisit if rebasing proves fragile with physics or particles.
