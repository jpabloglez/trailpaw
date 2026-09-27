# ADR-001: Custom procedural chunked terrain instead of a terrain plugin

- **Status:** Accepted
- **Date:** 2026-09-27

## Context
The world is effectively endless and generated from a seed at runtime, with biomes that
change with the distance travelled (ARCHITECTURE §3). Heightmap-region plugins such as
Terrain3D are excellent for finite, hand-sculpted maps but assume authored data on disk,
which fits poorly with on-the-fly, infinite generation.

## Decision
Build terrain ourselves: square chunks whose `ArrayMesh` and `HeightMapShape3D` data are
generated from a seeded height function on worker threads and attached on the main thread
within a per-frame budget.

## Consequences
- Full control over determinism, streaming, LOD, seams and biome blending.
- No third-party dependency to track across Godot upgrades.
- We own seam handling, LOD and performance work (Phase 2, Phase 11).
- Revisit if the design moves to a finite, hand-crafted map.
