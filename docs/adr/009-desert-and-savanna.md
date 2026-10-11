# ADR-009: Desert and savanna after the mountains

- **Status:** Accepted
- **Date:** 2026-10-11

## Context
Phase 18 adds a desert. The user chose:
- **a desert and a savanna after the mountains** (the mountains' rain shadow):
  mountains → desert → savanna → meadow. The savanna softens the return to the meadow.
- **dunes and mesas**
- **a gentle challenge with rare oases** (later PRs)

This needs two things:
- **New relief:** the height layers (continental, detail, ridged) can make neither dunes nor
  flat-topped mesas.
- **A new ADR:** like ADR-006 and ADR-008, two new bands move every band beyond them and change
  the golden heights.

## Decision
- **The sand layers** in `HeightSampler`, driven by a fourth noise (`LAYER_SALT[3]`, the
  "sand" noise, ≈ 170 m wavelength). They run only where a biome's `dune_scale` or
  `mesa_scale` is above 0, at one extra noise lookup per sample.
  - **Dunes:** `(1 − |sin(k·(x·cosθ + z·sinθ) + warp·sand)|)^sharpness`.
    - Crests 60 m apart, across a 30° wind, bent by the sand noise (warp 3.5).
    - Their height (7 m) varies with the sand noise (×0.1–1.0), so they read as big and small
      dunes, not a washboard.
  - **Mesas:** where the sand noise passes 0.4, `smoothstep` over 0.08 noise units raises the
    ground 20 m. The result is a flat top and near-vertical sides (the rock shader greys
    them).
    - Dunes stop at a mesa's edge (×(1 − plateau)), so its top stays flat.
  - The scales live in `BiomeDefinition` and `BiomeBlend` and blend with the biome weights.
  - The chunk generator's uniform fast path passes them on, and `max_deviation` counts them.
- **`desert.tres`:**
  - shape: 1000 m wide; offset 6, continental ×0.8, detail ×0.4, ridged ×0.1, dunes ×1,
    mesas ×1
  - climate: warmth 1.5 (the range opens to ±2)
  - ground: golden sand
  - vegetation: cacti (Kenney `cactus_tall` / `cactus_short`, which collide), dry bushes,
    rocks
  - fauna: none yet; the fauna-director test allows an empty biome only with `fauna_chance`
    0
- **`savanna.tres`:**
  - shape: 800 m wide; offset 4, gentle relief
  - climate: warmth 0.8
  - ground: golden grass
  - vegetation: Kenney `tree_plateau` (acacia-like), a procedural `dry_grass` tuft, bushes
  - fauna: horses and deer
- **Results:**
  - **Desert (seeds 12345 and 777):** median ≈ 8 m, mesas up to 40–52 m, ≈ 4 % steeper than
    45° (the mesa sides).
  - **Savanna:** median ≈ 4 m, 0.1 % steep.
  - A slope-limited grid walk crosses both bands in every strip tested (3 seeds × 6 strips).

## Consequences
- **The cycle is 7.0 km.** The desert runs from 5.2 to 6.2 km, the savanna from 6.2 to 7.0
  km.
- **Golden values:**
  - (−9000, 4200) changes from 144.569 m (mountains) to −4.267 m: it is in the wetland now.
  - The mountain peak (194.626 m) and the two points within 4 km are unchanged.
  - A mesa top (36.666 m) and a dune point (8.887 m) are pinned.
- **Saved games from beyond ≈ 5.2 km load into a different landscape**, as in ADR-006. The
  spawner drops the animal onto the ground there.
- **The 10 km probe** crosses the desert and savanna once (5.2–7.0 km).
- **Revisit:**
  - reddish mesa cliffs (they need a per-biome rock colour, which has no free vertex
    attribute today)
  - dunes that read better from far away (fog hides them beyond ≈ 200 m)
