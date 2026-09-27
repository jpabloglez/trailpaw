# ADR-005: Biome-blended terrain height function

- **Status:** Accepted
- **Date:** 2026-09-28

## Context
Phase 3 makes the landscape change with the distance travelled from the spawn point. The
terrain height function (`HeightSampler`) is part of the world's identity: the same seed
must always produce the same world, and a golden-value test pins it. Adding biomes changes
that function on purpose.

## Decision
Terrain height = base + Σ biome offset + Σ layer noise × (layer amplitude × blended biome
scale). `BiomeResolver` blends at most two neighbouring bands (weights sum to 1), so the
modifiers are blended first and each noise layer is evaluated once. Chunks lying wholly
inside one band (proved with a Lipschitz bound on the noisy distance) take a fast path with
constant modifiers that is bit-identical to per-sample blending. The golden values were
updated in the same change.

## Consequences
- Worlds generated before this change (none shipped) differ: acceptable pre-release.
- Generation cost on worker threads rose from ≈ 6.3 to ≈ 15.6 ms per LOD0 chunk (GDScript
  call overhead of per-sample blending). Main-thread budgets are unaffected; streaming
  throughput is re-verified with the 10 km probe. Chunk generation is the first candidate
  for GDExtension in Phase 11 if profiling on target hardware demands it.
- Any future change to the height function or biome data values that alters the golden
  values needs a new ADR.
