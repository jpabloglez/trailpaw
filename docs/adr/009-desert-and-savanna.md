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

- **Oases (PR 2):**
  - **Placement:** the world is cut into 600 m cells, and an integer hash of the seed and
    the cell gives 85 % of them an oasis at a random spot. Nothing is stored.
    - An oasis exists only if the sand noise at its centre is 0.15 under the mesa threshold,
      so it never opens a crater in a mesa.
  - **The bowl:** 90 m across, with a wobbly rim (two lobed sines) and a flat bottom (22 %
    of the radius) 1.5 m under the water level.
    - It is scaled by the biome's `oasis_scale` (desert 1, every other biome 0).
    - Inside it the mesas fade out (`plateau × (1 − smoothstep(0, 0.08, bowl))`), so a mesa
      may stand at the rim but never as a cliff beside the water.
  - **Everything else works unchanged:** the water plane, the shore shader, drinking, the
    water scent and the map.
  - **Palms** (Kenney `tree_palm*`), grass and reeds grow only 0.4–4.5 m above the water,
    which in the desert happens only at oases.
  - **Results:** ≈ 50–60 oases on the desert ring of each seed. From anywhere in the desert
    one lies within the water scent's 1.5 km. Cost: one hash and a distance per desert
    sample, plus one noise lookup inside a bowl.

- **Desert climate (PR 3):** three new `BiomeDefinition` fields.
  - `night_drop`: the desert is 3.6 colder at midnight than at noon, eased with the hour (the
    savanna 1.0). Its warmth runs from 1.5 at noon (+0.2 global) to ≈ −2.4 at midnight.
    - Noon is hot: comfort turns critical in ≈ 6 minutes of trotting.
    - Midnight, standing still, crosses the Phase 17 cold knee a little: a faint frost
      vignette. Running warms the fox up.
  - `need_multipliers`: thirst ×1.6 in the desert, ×1.2 on the savanna.
  - `dry`: the weather stays global, but in a dry biome `Weather.shelter` eases to 1.
    `rain_here` (the particles, the wind and the ambience) is then 0, the ground dries and
    the needs don't count the rain.
  - **Ambience:** the mountains (missed in Phase 17), desert and savanna get their sounds:
    wind, savanna birds by day, crickets at night. A test now checks that no biome is
    silent.

- **Fauna (PRs 4–7):**
  - lizards and desert hares (critters in code)
  - vultures (a second `Soarers`)
  - the zebra (the Quaternius Farm Animal Pack model, CC0)
  - the fennec, built by `tools/make_fennec.py` from the fox like the ibex (bpy stays an
    optional tool, ADR-008)
  - `FaunaSpecies.hours` lets the fennec come out only at dusk and night.

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
