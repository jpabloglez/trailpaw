# Trailpaw — Technical Architecture

Status: living document. Update it whenever a system's contract changes.

## 1. Goals and constraints

| Goal | Target |
|---|---|
| Hardware floor | Intel Core i5, 16 GB RAM, GTX 1050 (2–4 GB VRAM) |
| Performance | 60 FPS @1080p on "Medium"; 30 FPS minimum on "Low" with integrated GPUs as stretch |
| Frame budget | 16.6 ms total; main-thread world streaming ≤ 2 ms/frame; AI ≤ 1.5 ms/frame |
| Memory | ≤ 3 GB RAM, ≤ 1.5 GB VRAM on Medium |
| World | Effectively endless, seeded, deterministic; biomes change with travelled distance |
| Input | Keyboard + mouse first, fully remappable; gamepad later |
| Art direction | Stylized / low-poly with soft lighting and fog — cheap to render, readable, cozy |

The art direction is a technical decision: flat-shaded or lightly textured assets, vertex
colours and distance fog are what keep an open world viable on a GTX 1050.

## 2. High-level architecture

```
Main (scene)
├── World (Node3D)
│   ├── WorldStreamer ──► ChunkGenerator (WorkerThreadPool)
│   │                    └── BiomeResolver ◄── data/biomes/*.tres
│   ├── ChunkRoot (loaded TerrainChunk instances)
│   ├── Environment (WorldEnvironment, Sun, DayNightCycle, Weather)
│   ├── FaunaDirector ──► FaunaAgent instances
│   └── Player (Animal)
│       ├── MovementComponent  ├── CameraRig
│       ├── NeedsComponent     ├── Interactor
│       └── AnimationController
└── UI (CanvasLayer): HUD, InteractionPrompt, PauseMenu, Settings

Autoloads: EventBus · GameState · Settings · SaveSystem · FloatingOrigin
```

### Autoloads (singletons)

| Autoload | Responsibility |
|---|---|
| `EventBus` | Global signals only (`need_critical`, `biome_entered`, `interaction_performed`, ...). No state. |
| `GameState` | World seed, distance travelled, current biome, elapsed time, pause state. |
| `Settings` | Graphics presets, input remaps, audio volumes; persisted in `user://settings.cfg` via `ConfigFile`. |
| `SaveSystem` | Serialises/deserialises a `SaveData` resource to `user://saves/`. Versioned schema. |
| `FloatingOrigin` | Re-centres the world when the player exceeds a threshold distance from the origin. |

Autoload scripts live in `scripts/autoload/` and are the one exception to the "every script
declares `class_name`" rule: a `class_name` equal to the autoload name would hide the
singleton. Access them by their autoload name (`EventBus.some_signal`).

## 3. World generation and streaming

### 3.1 Coordinates and chunks
- World is a grid of square chunks (`CHUNK_SIZE = 64 m`, resolution 65×65 vertices, tunable).
- `Vector2i` chunk coordinates; the streamer keeps a ring of radius `R_LOAD` (e.g. 4)
  loaded around the player and unloads beyond `R_UNLOAD` (hysteresis avoids thrashing).
- Load order: nearest first, prioritised by camera direction.
- Implementation: `WorldStreamer` (node) + `StreamingPlan` (pure decisions) +
  `data/world/streaming_settings.tres` (load 4 / unload 5 chunks, 2 ms build budget, 4
  worker tasks). Each `ChunkJob` owns a settings copy; the main thread reads its result only
  after `WorkerThreadPool.wait_for_task_completion`. Stale results are discarded, chunk
  nodes are pooled, and `_exit_tree` waits for every pending task.

### 3.2 Terrain choice (ADR-001)
**Decision:** custom procedural chunked terrain (`ArrayMesh` built from a height function)
rather than a sculpted-terrain plugin.
**Why:** the world is endless and generated from a seed; a heightmap-region plugin such as
Terrain3D is excellent for hand-authored worlds but adds friction for infinite, on-the-fly
generation. Revisit if the design moves to a finite, hand-crafted map.

### 3.3 Generation pipeline (per chunk)
1. **Worker thread** (`WorkerThreadPool.add_task`):
   - Sample heights with layered `FastNoiseLite` (continental + detail + ridged for mountains)
     via `HeightSampler` (tunables in `data/world/terrain_settings.tres`). Each task builds its
     own sampler from a settings copy; layer seeds use an explicit integer mix of the world
     seed, and a golden-value test pins the output so upgrades cannot silently change worlds.
   - Resolve biome weights per vertex (see 3.4) → vertex colours / splat weights.
   - Build `PackedVector3Array` vertices, normals, UVs, indices (`ChunkGenerator` → `ChunkData`).
     **Seam-free:** samples use the integer global grid index
     (`coord * (resolution - 1) + i`) times the step, so neighbours evaluate identical
     coordinates on shared borders; normals use central differences over a one-sample apron.
   - Build `HeightMapShape3D` data for collision.
   - Scatter vegetation/props with a seeded RNG (Poisson-disk or jittered grid) → transform lists.
2. **Main thread** (budgeted, a few chunks per frame):
   - Create `ArrayMesh`, `MeshInstance3D`, `StaticBody3D` + collision.
   - Create one `MultiMeshInstance3D` per vegetation type per chunk.
   - Register interactables (water, food sources) with their `Area3D`s.
3. LOD: distant chunks use a lower vertex resolution (LOD0 65² at 1 m with collision within
   `lod0_radius` = 1.5 chunks — the 3×3 block incl. diagonals; LOD1 17² at 4 m beyond, with
   1 chunk of hysteresis). Every chunk has a vertical **skirt** (`skirt_depth`) that hides
   LOD T-junction cracks; chunks changing LOD are rebuilt in place (never missing a frame).
   Vegetation fades out via
   `visibility_range_end` and shader dithering.

Scene-tree mutations happen only on the main thread; worker threads produce plain data.

### 3.4 Distance-driven biomes
- Data: `BiomeDefinition` (`data/biomes/{meadow,forest,river_valley,hills}.tres`: id, display
  name, band width, height offset/scales, two-colour ground palette) ordered by `BiomeTable`
  (`data/biomes/biome_table.tres`): 800 m bands that **repeat in a cycle**, 150 m blend,
  ±110 m boundary noise, measured from the spawn point.
- `BiomeDefinition` (Resource): name, height params, ground palette, vegetation table,
  fauna table, ambient audio, temperature, water frequency.
- `BiomeResolver` (pure, seeded, one per worker task): noisy distance
  `d' = |pos − spawn| + noise(pos) · amplitude`; the band containing `d'` cross-fades with
  its neighbour over `blend_width` (smoothstep), so weights sum to exactly 1, at most two
  biomes mix and transitions are continuous. `amplitude × frequency ≤ 0.15` (validated;
  measured noise gradient ≤ 4.6× frequency) keeps `d'` increasing along every outward ray,
  so bands always appear in order. `blend_into()` fills a reused `BiomeBlend` (no
  allocation) for generation; `weights_at()` / `dominant_at()` for gameplay and tests.
- Original sketch — `BiomeResolver.weights_at(world_pos) -> Dictionary[StringName, float]`:
  `progress = distance_from_spawn / BIOME_SPAN` selects the dominant biome band
  (meadow → forest → river valley → hills → alpine…), then a low-frequency noise
  perturbs the boundary so transitions look organic. Weights are blended across a
  transition width to avoid hard seams.
- Terrain: height modifiers (offset, per-layer scales) and the two ground colours are blended
  per vertex from the biome weights (`HeightSampler.sample`, ADR-005). Colour A goes in
  `COLOR`, colour B in `CUSTOM0` (RGBA8). Chunks wholly inside one band use a bit-identical
  constant-blend fast path. Each `ChunkJob` builds its sampler on the main thread so worker
  threads never read the shared biome resources.
- Distance is computed in **absolute world coordinates** (tracked by `FloatingOrigin`),
  never from the rebased local position.

### 3.5 Floating origin
32-bit floats lose precision several kilometres from the origin (jittery animation and
physics). When the tracked target is further than `rebase_distance` (2 km, in
`streaming_settings.tres`) from the local origin, `FloatingOrigin` shifts the world back by a
**whole number of chunks**:
- every node in the `origin_shiftable` group (player, camera rig, debug camera) gets
  `global_position -= offset` and `reset_physics_interpolation()` (no interpolated streak);
- `GameState.origin_chunk: Vector2i` advances by the same chunks — an exact integer, so
  `GameState.absolute_position(local)` = local + `origin_chunk * chunk_size` never drifts;
- `EventBus.origin_shifted(offset)` fires: `WorldStreamer` re-derives every chunk position from
  its integer coordinate and `CameraRig` corrects its cached follow goal.
Y is never shifted. This avoids needing a custom double-precision engine build (ADR-004).

## 4. Player (quadruped animal)

### 4.1 Species as data
`AnimalSpecies` (Resource): mesh scene, animation library, walk/trot/run speeds,
acceleration, turn rate, jump height, swim ability, need modifiers, sounds.
Swapping species = swapping a `.tres`; no code changes.

### 4.2 Movement
- Scene: `scenes/player/animal.tscn` — `Animal` (CharacterBody3D) with `%MovementComponent`,
  `%PlayerInput` and `%StateMachine` (Idle, Locomotion, Jump, Fall). Forward is `-Z`.
- Physics layers (named in `project.godot`): **1 `world`** (static geometry, terrain),
  **2 `player`**. The player collides with `world`; camera collision only checks `world`.
- `CharacterBody3D` with capsule collider oriented horizontally (or two-sphere approximation).
- Camera-relative input; smooth acceleration and turning (quadrupeds turn in arcs, not in place).
- Gaits: walk / trot / run (Shift) driven by speed thresholds.
- **Ground alignment:** raycasts at front and rear feet → body pitch/roll follows terrain
  normal with smoothing and clamping.
- States (`StateMachine` component): Idle, Locomotion, Jump, Fall, Swim, Interact, Rest.
- **Intent-based control:** `MovementComponent` never reads `Input`. A controller writes
  its intent (`move_input`, `sprint`, `request_jump()`): `PlayerInput` for the player,
  the AI for fauna (Phase 8). The maths lives in the pure `LocomotionModel` (unit-tested).
- **Gaits in Phase 1:** full input = trot, `sprint` = run; walk is the band below the
  walk/trot midpoint (starting, stopping, analogue input later). Velocity always follows
  the heading, and the heading turns at a speed-dependent rate, so turns are arcs.

### 4.3 Camera
`SpringArm3D` third-person rig with mouse orbit, collision, zoom (wheel), slight lag and
auto-recentre behind the animal while moving. Sensitivity and invert-Y in Settings.

- Scene `scenes/player/camera_rig.tscn`: `CameraRig` (top-level) → `%Yaw` → `%Pitch` →
  `%SpringArm3D` (mask `world`, sphere probe) → `%Camera3D`. Tunables in
  `data/camera/default_camera_rig.tres` (`CameraRigSettings`); sensitivity/invert-Y move to
  `Settings` in Phase 10.
- **Physics interpolation is enabled project-wide.** The rig itself opts out and follows the
  target's `get_global_transform_interpolated()` in `_process`, so the view is smooth on
  high-refresh displays while gameplay stays at a 60 Hz physics tick.
- Cursor: captured on left click, released with `pause` (Esc).

### 4.4 Animation
`AnimationTree` with a state machine; locomotion via `BlendSpace1D` (speed) and additive
head-look. Procedural foot placement using Godot's `SkeletonModifier3D`-based IK is a
Phase 11 polish item.

### 4.5 Default input map

| Action | Default |
|---|---|
| `move_forward/back/left/right` | W / S / A / D |
| `sprint` | Shift (hold) |
| `jump` | Space |
| `interact` | E / left click on highlighted target |
| `sniff` (highlight nearby resources) | Q |
| `rest` | R (hold) |
| `camera_zoom_in` / `camera_zoom_out` | Mouse wheel up / down |
| `pause` | Esc |
| `toggle_debug_overlay` (debug) | F3 |
| *camera orbit* | Mouse move (captured) — not an action, see below |

All actions are defined in `project.godot` `InputMap` and remappable at runtime. Keys are
bound by `physical_keycode` so the layout works on non-QWERTY keyboards (e.g. AZERTY).

- Camera orbit reads `InputEventMouseMotion` directly in `CameraRig`; `InputMap` cannot
  bind mouse motion to an action.
- Zoom is split into two actions because a wheel event has no analogue axis.
- "Hold" behaviour (`sprint`, `rest`) is gameplay logic on top of the action, not part of
  the `InputMap`.

## 5. Needs system

- `NeedDefinition` (Resource): id, max, decay per minute, critical threshold, effects.
- Initial needs: **hunger**, **thirst**, **temperature comfort**, **energy**.
- `NeedsComponent` ticks at a fixed rate (e.g. 4 Hz), applies biome/weather/activity
  modifiers (running drains energy and thirst faster; hot biomes raise temperature).
- Emits `need_changed(id, value)` and `need_critical(id)`. Critical needs slow movement —
  the game is cozy, so there is **no death**; consequences are soft (slower, tired animation).
- Pure logic lives in a `RefCounted` class (`NeedsModel`) so it is unit-testable without scenes.

## 6. Interaction system

- `Interactable` component (on `Area3D`): `interaction_type` (EAT, DRINK, COOL_OFF, REST,
  SOCIAL), prompt text, duration, need effects, cooldown/regrowth time.
- `Interactor` on the player: shape-casts forward, picks the best target by distance and
  facing angle, shows prompt, runs the interaction (locks movement, plays animation, applies effects).
- Water: chunks with water planes expose DRINK and COOL_OFF (wading/swimming).
- Food sources (berries, grass, fallen fruit) deplete and regrow; state stored per chunk
  as a delta so saves stay small.

## 7. Fauna AI

- `FaunaDirector` spawns animals per loaded chunk from the biome's fauna table, caps the
  global count and despawns with the chunk.
- `FaunaAgent`: lightweight FSM (Wander, Graze, Flee, Approach, Follow, Rest), steering
  on terrain (seek, avoid, separation) instead of navmesh baking per chunk.
- Perception: distance + angle checks at 5–10 Hz with staggered updates.
- Temperament per species: shy (flees), curious (approaches), friendly (can follow player
  after a SOCIAL interaction). Social interactions: greet/sniff, play, follow.
- Distant agents degrade to cheaper update rates (AI LOD).

## 8. Environment and audio

- Day/night cycle drives sun angle, sky colours and fog; temperature reacts to time of day.
- Weather states (clear, cloudy, rain) with GPU particles; rain boosts cooling, reduces thirst.
- Ambient audio layered per biome with cross-fades on biome transitions; footsteps by surface.

## 9. Persistence

- `SaveData` (Resource, schema version): seed, world offset + player position, needs,
  time of day, species, discovered biomes, per-chunk deltas (depleted food, befriended fauna).
- Autosave on biome change and every N minutes; manual save from pause menu.
- Migration functions keyed by schema version.

## 10. Quality presets

| Setting | Low | Medium | High |
|---|---|---|---|
| Load radius (chunks) | 3 | 4 | 6 |
| Vegetation density | 40 % | 70 % | 100 % |
| Shadows | 1 cascade, 1024 | 2 cascades, 2048 | 4 cascades, 4096 |
| SSAO / glow | off | glow only | on |
| Render scale (FSR 1) | 0.75 | 1.0 | 1.0 |

## 11. Testing strategy

| Level | What | Tool |
|---|---|---|
| Unit | NeedsModel, BiomeResolver, noise determinism, chunk math, save migration | gdUnit4 |
| Scene | Player spawns and moves on flat ground, interactor picks targets, streamer loads ring | gdUnit4 scene runner |
| Determinism | Same seed → identical chunk hash | gdUnit4 |
| Performance | Terrain streaming probe: `terrain_sandbox.tscn -- --auto-travel=<m>` (spikes, holes, frame percentiles; results in `docs/notes/terrain-streaming-perf.md`); full `tools/perf_probe` in Phase 11 | Godot (+ Python report later) |
| Manual | Game feel, camera, visuals | Checklist in each ROADMAP phase |

## 12. Architecture Decision Records

Stored in `docs/adr/NNN-title.md`. Initial set:
- [ADR-001](adr/001-custom-chunked-terrain.md) Custom procedural chunked terrain instead of a terrain plugin.
- [ADR-002](adr/002-gdscript-first.md) GDScript first, GDExtension (C++) only after profiling.
- [ADR-003](adr/003-no-death-soft-consequences.md) No death mechanic; soft consequences for critical needs.
- [ADR-004](adr/004-floating-origin.md) Floating origin instead of a double-precision engine build.
- [ADR-005](adr/005-biome-blended-terrain.md) Biome-blended terrain height function.

New ADRs start from [`000-template.md`](adr/000-template.md).
