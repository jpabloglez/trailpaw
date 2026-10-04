# ADR-006: A wetland band after the river valley

- **Status:** Accepted
- **Date:** 2026-10-04

## Context
Phase 14 adds a water biome. The user chose wetlands, placed after the river valley, so the
cycle becomes meadow → forest → river valley → **wetland** → hills (five 800 m bands, a 4 km
cycle instead of 3.2 km). Biomes come from the distance to the spawn, so a new band moves
every band beyond it. That changes the terrain the height function produces past ≈ 2.4 km,
and the golden values pin that function (ADR-005: such changes need an ADR).

## Decision
- `data/biomes/wetland.tres`: height offset −5.8 m with low continental (0.12), moderate
  detail (1.3) and almost no ridged relief (0.03). It sits just under the water level
  (−6 m), so the band is **≈ 43 % water (seed 12345), 93 % of it shallower than 1.2 m**:
  channels, pools and islets that can be waded, and ≈ 56 % of the water deep enough for
  ducks.
  - Muddy green/brown ground, cool (warmth −0.2).
  - Valley vegetation for now, deer and donkeys, birds, ducks, butterflies by day,
    fireflies at night.
- It is inserted after the river valley in `biome_table.tres`. The golden height at
  (−9000, 4200) changes from 10.089 to 3.591 m; the other two pinned points are unchanged.

## Consequences
- **Saved games from beyond ≈ 2.4 km load into a different landscape.** Their absolute
  position is kept: the hills that were there are now wetland, the next band is hills, and
  so on.
  - Nothing breaks: `AnimalSpawner` drops the animal onto the ground (or keeps it afloat on
    water), and the map re-renders from the height function. A test places an old save
    where the wetland now is and checks it lands.
  - Explored-area marks from such a save describe a place that has changed; they stay, and
    the map shows the new terrain there.
- The cycle is 4 km, so the 10 km probe now crosses every band twice and a half.
- Tests that hard-coded the four-biome order or a "hills" chunk coordinate were updated
  (hills chunk (43, 0) → (56, 0)).
