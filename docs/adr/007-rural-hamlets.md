# ADR-007: Rural hamlets placed on the existing terrain

- **Status:** Accepted
- **Date:** 2026-10-10

## Context
Phase 16 adds rural hamlets: 3–6 houses, a well, a stable with a pen and props, rare, in the
meadow and the hills. The user asked for sparse places to explore from a distance, without
changing the biome bands. Buildings need flat ground and no trees growing through them.

## Decision
- **The terrain height function is not changed.** A hamlet is placed only where the ground is
  already flat and dry. `HamletPlan` splits the world into 1.5 km cells, and each cell
  (seeded per world and cell, 45 % chance) tries up to 8 sites. A site is accepted if:
  - it lies fully inside a meadow or hills band
  - every sample of a 90 m grid (11.25 m apart) is ≥ 0.5 m above the water
  - the ground between neighbouring samples rises faster than 8° at most 10 % of the time,
    and never faster than 16°
- **Pieces stand on the ground at their centre:** their foundations sink a little where the
  ground isn't level.
- **Vegetation is the only generated content that changes, and only near hamlets.**
  `VegetationScatterer` skips every plant inside a piece's footprint and every tall plant
  (one with a collider: trees, bushes, rocks, logs) within 40 m of the well.
  - Chunks that no hamlet touches are byte-identical to before.
  - The clearing circles are computed from the same pure plan on worker threads (a static
    per-seed cache under a mutex).
- **Hamlets are built as scenes near the player** (`HamletDirector`, 300 m) from CC0 models
  (Quaternius *Medieval Village Pack*) and freed beyond 400 m. They aren't part of chunk
  data.

## Consequences
- The hills are too uneven for these rules (half of their 11 m steps exceed 8°). With the
  current terrain, hamlets appear in the meadow only: about one per 13 km² with seed 12345,
  the nearest ≈ 370 m from the start. The hills stay in the data, so a gentle spot can still
  host one. Flattening terrain for hamlets would change the height function and needs its
  own ADR.
- Saves are unaffected: hamlets come from the seed, and eaten food (Phase 16, PR 4) uses the
  existing chunk deltas.
- Fauna and critters can still wander into a hamlet: they treat the colliders like any
  other obstacle.
