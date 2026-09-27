# Trailpaw — Incremental Roadmap

Each phase ends in a **playable, testable build**. Never start a phase until the previous
one meets its exit criteria. Estimates assume part-time work (~8–10 h/week) with
Claude Code; one sprint = 2 weeks.

| Phase | Theme | Sprints | Cumulative |
|---|---|---|---|
| 0 | Project setup and tooling | 1 | 2 w |
| 1 | Placeholder movement and camera | 1 | 4 w |
| 2 | Procedural terrain chunks | 2 | 8 w |
| 3 | Distance-driven biomes | 1.5 | 11 w |
| 4 | Vegetation and props | 1.5 | 14 w |
| 5 | Quadruped character | 2 | 18 w |
| 6 | Needs system and HUD | 1 | 20 w |
| 7 | Interactions (eat, drink, cool off, rest) | 1.5 | 23 w |
| 8 | Fauna AI and social interactions | 2 | 27 w |
| 9 | Day/night, weather, audio | 1.5 | 30 w |
| 10 | Save/load, settings, menus | 1 | 32 w |
| 11 | Performance and polish | 2 | 36 w |
| 12 | Vertical slice release | 1 | 38 w |

Milestones: **M1 "Walk the world"** (end of Phase 3), **M2 "A day in the life"**
(end of Phase 7), **M3 "Living world"** (end of Phase 10), **M4 Vertical slice** (Phase 12).

---

## Phase 0 — Project setup and tooling

- [x] Install pinned Godot 4.x stable; write version to `.godot-version`.
- [x] Create project with Forward+ renderer; set physics tick 60 Hz, window 1920×1080, stretch mode `canvas_items`.
- [x] Create folder layout from `CLAUDE.md` §3 with `.gitkeep` files.
- [x] Git + Git LFS (`.gitattributes`), `.gitignore` for `.godot/`, `*.import` cache, exports.
- [x] Install gdUnit4 in `addons/`; one smoke test passes headless.
- [x] `pip install gdtoolkit ruff pytest`; add `gdlintrc`, `requirements-dev.txt`.
- [x] Autoload stubs: `EventBus`, `GameState`, `Settings`, `SaveSystem`, `FloatingOrigin`.
- [x] Define full `InputMap` from ARCHITECTURE §4.5.
- [x] GitHub Actions: lint → headless import → tests.
- [ ] `docs/adr/` with ADR-001…004 as short records.
- [ ] Optional: `.claude/commands/` with custom commands (`/phase-status`, `/check` running lint + tests).

**Exit criteria:** fresh clone → `--import` clean → tests and lint green locally and in CI.

> Prompt idea: *"Read CLAUDE.md and ROADMAP.md. Execute Phase 0 task by task in plan
> mode. Stop after each task and show me the diff and the commands you ran."*

---

## Phase 1 — Placeholder movement and camera

- [ ] `debug/movement_sandbox.tscn`: flat plane, ramps, steps, obstacles.
- [ ] `Animal` scene: `CharacterBody3D` + box/capsule placeholder with a visible "nose".
- [ ] `MovementComponent`: camera-relative input, acceleration, arc turning, walk/trot/run, jump, gravity, slope limit.
- [ ] `StateMachine` component (generic, reusable by fauna later) with Idle/Locomotion/Jump/Fall.
- [ ] `CameraRig`: SpringArm3D, mouse orbit with captured cursor, zoom, collision, auto-recentre.
- [ ] Tunables in `data/species/placeholder.tres` (`AnimalSpecies` resource).
- [ ] Debug overlay (F3): FPS, speed, state, position.

**Tests:** state transitions; speed never exceeds species max; movement is camera-relative.
**Manual check:** controls feel responsive; camera never clips into geometry.
**Exit:** you can run, jump and orbit comfortably for 5 minutes without friction.

---

## Phase 2 — Procedural terrain chunks

- [ ] `HeightSampler` (pure class): layered `FastNoiseLite`, seeded, deterministic.
- [ ] `ChunkGenerator`: builds mesh arrays + collision data off the main thread.
- [ ] `TerrainChunk` scene: MeshInstance3D + StaticBody3D + HeightMapShape3D.
- [ ] `WorldStreamer`: load/unload ring with hysteresis, nearest-first queue, main-thread budget (N chunks/frame).
- [ ] Seam-free edges (shared border vertices, consistent normals).
- [ ] Two LOD resolutions for far chunks.
- [ ] `FloatingOrigin` rebase with absolute-position tracking in `GameState`.
- [ ] `debug/terrain_sandbox.tscn` with a free-fly camera and chunk-border gizmos.

**Tests:** same seed → identical chunk hash; neighbour chunk edges match; streamer loads
exactly the expected set for a given position; rebase preserves absolute position.
**Perf:** no main-thread spike > 4 ms while running at full speed.
**Exit:** run in a straight line for 10 km with no hitches, holes or jitter.

---

## Phase 3 — Distance-driven biomes → **M1**

- [ ] `BiomeDefinition` resource + 4 biomes in `data/biomes/` (meadow, forest, river valley, hills).
- [ ] `BiomeResolver.weights_at()` using distance bands + boundary noise + blend width.
- [ ] Biome-dependent height parameters and ground vertex colours.
- [ ] Terrain shader: blends ground palettes by weight, slope-based rock tint, distance fog.
- [ ] Rivers/lakes v1: water plane at sea level in low areas (river valley biome raises frequency).
- [ ] `EventBus.biome_entered` + HUD toast with biome name.

**Tests:** weights sum to 1; bands appear in configured order along any direction; transitions are continuous.
**Exit (M1):** walking outwards visibly changes landscape in a smooth, pleasing way.

---

## Phase 4 — Vegetation and props

- [ ] Import CC0 low-poly plants/rocks/trees; record in `assets/CREDITS.md`.
- [ ] `VegetationTable` per biome (type, density, slope/height limits, scale range).
- [ ] Seeded scattering on worker threads → one `MultiMeshInstance3D` per type per chunk.
- [ ] Collision only for trees and large rocks (simple shapes).
- [ ] Visibility ranges and dithered fade; wind sway vertex shader for grass/foliage.
- [ ] Density scales with the quality preset.

**Tests:** deterministic placement; nothing placed underwater or on steep slopes beyond limits.
**Perf:** Medium preset ≥ 60 FPS on GTX 1050 in the densest biome.
**Exit:** the world looks alive and still streams without hitches.

---

## Phase 5 — Quadruped character

- [ ] Choose first species (e.g. capybara or dog); create `data/species/<name>.tres`.
- [ ] Source or model a rigged animal in Blender (Quaternius animated animals are a good start); export `.glb`.
- [ ] Animation set: idle, walk, trot, run, jump, fall, eat, drink, lie down, sniff, swim.
- [ ] `AnimationController`: `AnimationTree` state machine + `BlendSpace1D` locomotion.
- [ ] Ground alignment with front/rear raycasts, smoothed pitch/roll.
- [ ] Swim state when in water (float at surface, slower speed).
- [ ] Footstep events from animation for later audio.

**Tests:** alignment angles clamped; swim state enters/exits at water line.
**Manual check:** no foot sliding at normal speeds; transitions look natural.
**Exit:** the animal is charming to control and look at.

---

## Phase 6 — Needs system and HUD

- [ ] `NeedDefinition` resources: hunger, thirst, temperature, energy.
- [ ] `NeedsModel` (pure logic) + `NeedsComponent` (4 Hz tick, modifiers from activity/biome).
- [ ] Soft consequences: slowed movement, tired idle animation, visual vignette hint.
- [ ] Minimal, cozy HUD: four icon meters that fade when full.

**Tests:** decay rates, clamping, modifiers, critical-threshold signals.
**Exit:** needs create gentle motivation to explore without stress.

---

## Phase 7 — Interactions → **M2**

- [ ] `Interactable` component and `Interactor` (shape-cast, target scoring, prompt UI).
- [ ] EAT: berry bushes, grass patches, fallen fruit with depletion/regrowth.
- [ ] DRINK and COOL_OFF: water edges and shallow water.
- [ ] REST: shaded spots and dens (restores energy, advances time).
- [ ] `sniff` action: highlights nearby resources briefly.
- [ ] Per-chunk delta storage for depleted resources.

**Tests:** interactor picks correct target; effects applied once; regrowth timing; deltas persist across chunk reload.
**Exit (M2):** a full loop — explore, get thirsty, find water, drink, eat, rest — feels good.

---

## Phase 8 — Fauna AI and social interactions

- [ ] `FaunaAgent` scene reusing `StateMachine` and a slimmed `MovementComponent`.
- [ ] Behaviours: Wander, Graze, Flee, Approach, Follow, Rest; steering on terrain.
- [ ] Species temperaments (shy/curious/friendly) in data.
- [ ] `FaunaDirector`: spawn from biome tables per chunk, global cap, AI LOD by distance.
- [ ] SOCIAL interaction: greet/sniff, play; friendly animals may follow for a while.
- [ ] 3–4 species using CC0 models (birds, deer, ducks, other capybaras…).

**Tests:** FSM transitions; spawn caps; despawn with chunk; follow ends correctly.
**Perf:** AI ≤ 1.5 ms/frame with max population.
**Exit:** meeting animals feels like a highlight of the walk.

---

## Phase 9 — Day/night, weather and audio

- [ ] Day/night cycle (sun, sky, fog colours, ambient light).
- [ ] Weather state machine: clear, cloudy, rain (GPU particles, wet ground tint).
- [ ] Temperature affected by time and weather.
- [ ] Biome ambience with cross-fades, footsteps by surface, animal sounds, UI sounds.
- [ ] Audio buses: Master, Music, SFX, Ambience.

**Exit:** a full in-game day is atmospheric and varied.

---

## Phase 10 — Save/load, settings and menus → **M3**

- [ ] `SaveData` resource with schema version and migrations.
- [ ] Autosave (biome change + interval) and manual save.
- [ ] Main menu (new game with seed, continue, settings, quit), pause menu.
- [ ] Settings: quality presets, resolution/render scale, V-Sync, FOV, mouse sensitivity, invert Y, volumes, key remapping.

**Tests:** round-trip save/load equality; migration from v1 fixture; settings persist.
**Exit (M3):** you can quit anywhere and continue exactly where you were.

---

## Phase 11 — Performance and polish

- [ ] `tools/perf_probe`: scripted path through all biomes, logs frame times; Python report (p50/p95/p99).
- [ ] Profile with Godot's profiler; fix top offenders; consider GDExtension (C++) for chunk generation only if it is still the bottleneck.
- [ ] Procedural foot IK, head-look at interesting objects.
- [ ] Juice: dust puffs, water splashes, camera shake on landing (subtle), UI transitions.
- [ ] Accessibility: text size, colour-blind-safe meters, hold-vs-toggle options.

**Exit:** p95 frame time ≤ 16.6 ms on Medium on the target PC.

---

## Phase 12 — Vertical slice release → **M4**

- [ ] Export presets for Windows and Linux; CI export job producing artifacts.
- [ ] Onboarding: first 5 minutes teach movement, sniff, drink and eat without text walls.
- [ ] Playtest with 3–5 people; collect feedback in `docs/playtests/`.
- [ ] README with build instructions, credits and licences.

**Exit:** a stranger can download, play 30 minutes and want to keep going.

---

## Backlog (post-slice ideas)

Gamepad support · more species selectable at start · seasons · photo mode · collectible
discoveries journal · companion system · more biomes (wetlands, coast, snow) · Steam Deck profile.
