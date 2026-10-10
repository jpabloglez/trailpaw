# ADR-008: A mountain band after the hills

- **Status:** Accepted
- **Date:** 2026-10-10

## Context
Phase 17 adds mountains. The user chose:
- a **1.2 km band after the hills**, so the hills act as foothills
- **peaks and passes**: high, snowy summits and cliffs the fox can't climb, but always a way
  across
- cold only on the snow (the needs part comes in a later PR)

Bands are rings measured from the spawn (ADR-005), so a new band moves every band beyond it.
That changes the terrain past ≈ 4 km, and the golden heights pin it. Two other problems:
- With the 150 m cross-fade, a band that much higher than its neighbours would end in a wall
  where it meets the next meadow.
- The offset range (±50 m) was too small.

## Decision
- **`data/biomes/mountains.tres`**, inserted after the hills:
  - shape: offset 85 m, continental ×5, detail ×0.8, ridged ×3.5, `band_width` 1200 m
  - climate: warmth −0.5 (cool)
  - ground: an alpine green and olive palette
  - vegetation: pines below ≈ 70–80 m, grass and flowers on gentle ground, rocks
    everywhere
  - fauna: alpacas, deer and stags
- **Relief profile:** a new `BiomeDefinition.edge_relief`, from 0 to 1 (mountains 0.15; every
  other biome 1, which means no profile).
  - `BiomeResolver` multiplies the band's offset and its continental and ridged scales by
    `lerp(edge_relief, 1, sin(π·t))`, with t the position across the band.
  - So the range rises to a central crest and comes down gently on both sides.
  - A profiled band is never "uniform" for heights, so its chunks take the per-vertex blend
    path that boundary chunks already use. Vegetation still uses the uniform path
    (`uniform_blend(..., heights = false)`) because it only needs the biome.
  - `max_modifiers()` stays a valid bound because the factor is ≤ 1.
- **Snow:** `TerrainSettings.snow_line` (90 m absolute) and `snow_blend` (8 m) are published as
  shader globals.
  - `terrain.gdshader` paints snow above the line, with a patchy edge from the macro pattern.
    It fades out between 32° and 48°, so cliffs stay rock.
  - The map renders the snow too.
  - Only the mountains reach the line: the hills top out at ≈ 56 m.
  - No plant of the mountains grows within `snow_blend` of it; rocks do.
- **Results for seeds 12345, 777 and 2024:**
  - median ≈ 61 m, highest peak 171–188 m
  - ≈ 21 % of the band above the snow line
  - ≈ 4 % of the band (≈ 12 % of its inner flank) steeper than 45°
  - a slope-limited walk on an 8 m grid crosses the band in every strip tested
- `BiomeDefinition.height_offset` now ranges from −50 to 150 m.
- **The ibex (PR 5)** is built by `tools/make_ibex.py` from the CC0 Quaternius alpaca. No
  animated CC0 ibex or goat exists. The script reshapes the mesh, adds horns, recolours it and
  re-exports it with the same rig and clips.
  - It needs **bpy** (Blender as a Python module), which is an optional tool, not a project
    dependency: it is not in `requirements-dev.txt` and not run in CI.
  - Its geometry helpers are plain Python and are tested in `tools/tests`.
  - The generated `.glb` is committed (LFS), like any other asset.

## Consequences
- **Golden values:** the height at (−9000, 4200) changes from 3.591 to 144.569 m, because
  that point now lies in the mountains. The peak at (4446.8, −1359.5) is pinned at 194.626 m.
  The two points within 4 km are unchanged.
- **Saved games from beyond ≈ 4 km load into a different landscape**, as in ADR-006.
  - The absolute position is kept and `AnimalSpawner` drops the animal onto the ground there.
  - Explored-area marks stay, and the map draws the new terrain under them.
- **The cycle is 5.2 km.** The 10 km probe crosses the mountains about twice (4.0–5.2 km and
  9.2–10 km); mountain chunks cost like boundary chunks.
- **The walkability test** allows up to 15 % of the mountains' inner flank to be too steep,
  while `test_mountains` proves passes exist.
- **Revisit** if the peaks should be seen from farther than the fog and streaming edge
  (≈ 200 m): that would need distant impostors.
