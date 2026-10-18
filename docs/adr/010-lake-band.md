# ADR-010: An alpine lake band between the hills and the mountains

- **Status:** Accepted
- **Date:** 2026-10-18

## Context
Phase 19 adds lakes. The user chose:
- **an alpine lake district between the hills and the mountains**, so the snowy peaks rise
  behind the water
- **large, clear lakes**: turquoise water, beaches, wooded islands and shallow lagoons
- **islands worth exploring** (a later PR) and **otters, beavers and swans** (later PRs)

This needs three things:
- **Islands:** the height layers make broad hills and valleys. Lowered under the water level,
  they give lakes with few, steep-sided islands.
- **Clear water:** the water plane shares one material, the same murky green-blue everywhere.
- **A new ADR:** like ADR-006, ADR-008 and ADR-009, a new band moves every band beyond it and
  changes the golden heights.

## Decision
- **`lakes.tres`**, an 800 m band after the hills.
  - **Shape:** offset −12 m, continental ×1.8, detail ×0.8, ridged ×0.3.
  - **Climate:** warmth −0.3 (fresh).
  - **Ground:** pale sand and green.
  - **Vegetation:**
    - pines and Kenney's `tree_thin` (a slender, birch-like tree), above 0.8 m
    - flat pebbles on the beaches, 0–2 m above the water
    - grass and bushes
    - reeds in the shallows
  - **Fauna:** deer and stags. The ducks and fish already live on any water.
  - **Cycle:** it grows to **7.8 km**. The lakes span ≈ 4.0–4.8 km, the mountains
    4.8–6.0 km, the desert 6.0–7.0 km and the savanna 7.0–7.8 km.
- **The island layer**, part of the sand layers (ADR-009) and driven by the same sand noise
  (`LAYER_SALT[3]`, ≈ 170 m).
  - Where that noise passes `island_threshold` (0.05), `smoothstep` over `island_softness`
    (0.6 noise units) raises the ground by up to `island_amplitude` (16 m).
  - The result is rounded islands with gentle shores. A softness of 0.3 made 11 % of the
    land steeper than the fox can climb; 0.6 brings that to 0.9 %.
  - It is scaled by `BiomeDefinition.island_scale`: 1.1 in the lakes, 0 everywhere else. It
    blends like the other scales.
  - The chunk generator's fast path passes it on, and `max_deviation` counts it.
- **Clear water per chunk.**
  - `BiomeDefinition.water_clarity` (0–1) and `water_tint` blend with the biome weights.
  - `ChunkGenerator` stores the values at the chunk's centre in `ChunkData`.
  - `TerrainChunk` sets them on its water plane as **instance uniforms** (`clarity` and
    `clear_tint`). That keeps one material, with no per-chunk duplicates.
  - In `water.gdshader`, clarity mixes both colours towards the tint (turquoise) and lowers
    the opacity when looking down, so the bed shows near the shore.
  - The lakes have clarity 0.85. Every other biome keeps 0, so their water looks exactly as
    before.
  - The uniforms work in Compatibility as well as Forward+ (checked with a red test tint
    in a capture).
- **Results (seeds 12345, 777, 2024):**
  - 57–58 % of the band is water, 87–89 % of it deeper than 2 m
  - ≈ 0.7 % of the sampled points lie on islands with water all around at 90 m
  - 0.9 % of the land is steeper than 45°
  - a grid walk in which water counts as swimmable crosses the band in every direction
    tested (3 seeds × 4)
- **Golden heights:** the river-valley point (−9000, 4200) changes (it gains the new cycle
  phase). The old mountain peak (4446.8, −1359.5) is now in the lakes. The old mesa point is
  now in the mountains. All are re-pinned.
  - Tests that used fixed places in the mountains or the desert now find them from the band
    layout (`tests/world/places.gd`), so the next band won't break them again.
- **Palms:** their height band narrows to 0.5–3 m above the water, from 4.5 m. With the
  desert moved, a dune hollow 3.6 m above the water grew a stray palm grove; the oasis shores
  stay within the new band.

## Consequences
- Saved games beyond ≈ 4 km load into different terrain, as with ADR-006, ADR-008 and
  ADR-009. A fox saved in the old mountains may wake up in a lake. The spawn finder and the
  swimming code handle it.
- The 10 km probe now crosses the lakes on its way out.
- Islands are now a first-class shape, which the island treasures (PR 2) build on.
