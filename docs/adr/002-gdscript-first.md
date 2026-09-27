# ADR-002: GDScript first, GDExtension (C++) only after profiling

- **Status:** Accepted
- **Date:** 2026-09-27

## Context
The project is developed part-time with fast iteration as a priority. GDScript is
Godot's native language, needs no build step and, fully statically typed, is fast enough
for most gameplay. Some systems (chunk generation, vegetation scattering) may become CPU
hotspots on the GTX 1050 / Core i5 target.

## Decision
Write all gameplay in fully statically typed GDScript. Move a system to C++ via
GDExtension only when the profiler shows it is a bottleneck that GDScript optimisation
cannot fix — not before Phase 11.

## Consequences
- One language, no native toolchain, simple CI.
- Hot paths must state their budget and avoid per-frame allocations (CLAUDE.md §5.8).
- A later GDExtension port adds a C++ build to CI; keep hotspot code in pure, data-in /
  data-out classes so it can be ported in isolation.
- Autoload scripts omit `class_name` (it would hide the singleton) — the only exception to
  the "every script declares `class_name`" rule.
