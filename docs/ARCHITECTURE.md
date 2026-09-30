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
| `GameState` | World seed, floating-origin chunk, current biome, water level, game clock (`game_minutes`, `clock_scale`, `time_of_day()`; pace in `data/world/clock.tres`: 1 real s = 1 game min, starts 08:00, ×10 while resting). |
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
  fauna table, ambient audio, temperature (`warmth`, Phase 6), water frequency.
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
  `COLOR.rgb`, colour B in `(UV2.xy, COLOR.a)` — standard attributes, because the
  Compatibility renderer misreads custom (`CUSTOM0`) attributes. Chunks wholly inside one band use a bit-identical
  constant-blend fast path. Each `ChunkJob` builds its sampler on the main thread so worker
  threads never read the shared biome resources.
- Shading: `shaders/terrain.gdshader` (`data/world/terrain_material.tres`, all tunables set
  in the material) mixes palette A↔B with a seamless world-space noise pattern, adds fine
  brightness detail and tints slopes between 28° and 40° with rock (at/under the 45° walk
  limit, so unwalkable ground reads as rock). Patterns use absolute coordinates through the
  `world_origin_offset` global shader uniform, which `FloatingOrigin` updates on every
  rebase (verified pixel-identical across a rebase). Distance fog comes from the
  Environment; the debug sandbox uses depth fog closing (90→200 m) before the streaming
  edge (~210 m) with `fog_sky_affect = 1` so the edge never shows.
- Water v1: `TerrainSettings.sea_level` (−6 m). A chunk whose ground dips below it shows a
  translucent plane (`shaders/water.gdshader`, ripples in absolute coordinates, no depth
  texture so Forward+ and Compatibility match) — one shared 1×1 `PlaneMesh` scaled to the
  chunk. The valley has mid-scale relief (detail ×2.5) so water forms several smaller lakes
  with coves and islands (≈ 21 % coverage, seed 12345) rather than one sheet. The terrain
  shader reads the `water_level` global (set by `WorldStreamer`) to paint a sand/mud shore
  band and darken the bed with depth; semi-transparent water then shows light shallows and
  dark deeps without a depth texture.
  Swimming since Phase 5 (see §4.2); drinking in Phase 7.
  **Known issue (M2 playtest):** water only forms under the global sea level, so the spawn
  meadow has none (0 of 52 sampled chunks; forest 8/54, valley 21/48, hills 1/46) and the
  nearest lake is ≈ 770 m from the spawn. Deferred until the map/navigation aid (ROADMAP
  backlog), then revisited.
- Events: `BiomeTracker` samples the focus node's absolute position at 4 Hz and announces a
  new biome only once its weight reaches 0.6 (hysteresis; the first sample announces the
  start biome): it sets `GameState.current_biome` and emits
  `EventBus.biome_entered(biome_id, display_name)`. `BiomeToast` (HUD) shows the name with
  fade in / hold / fade out from `data/ui/biome_toast.tres`.
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

### 3.6 Vegetation and props (Phase 4)
- Data: one `VegetationType` per model (`data/vegetation/*.tres`: scene, scale range, ground
  alignment, visibility range, `near_only`, wind sway, collision cylinder in model units) and a
  `VegetationEntry` table per biome (`BiomeDefinition.vegetation`: density per 100 m², max
  slope, height band relative to the water — never below it — and clumping).
- Models: a curated Kenney Nature Kit selection (CC0) in `assets/environment/nature/`, each a
  single mesh standing on its origin (MultiMesh-friendly, test-enforced).
- Scattering (`VegetationScatterer`, inside each `ChunkJob` on the worker): per type a
  jittered grid sized for its densest biome; a candidate is kept with probability
  Σ(biome weight × biome density passing that biome's slope/height rules) / max density,
  shaped by a clumping noise, so boundaries mix vegetation smoothly. Height and slope come
  from the exact mesh triangle under the point (instances sit on the rendered surface at any
  LOD). Seeded per (world seed, chunk, type) and LOD-independent, so trees keep their place
  when a chunk changes LOD; `near_only` types only in LOD 0. Output per type is a
  `PackedFloat32Array` in `MultiMesh.buffer` layout. The scatterer is an immutable snapshot
  built once by `WorldStreamer` and shared read-only by all jobs. Cost ≈ +6–8 ms per LOD 0
  chunk on the worker (+17 ms at band boundaries).
- Rendering: `VegetationLibrary` extracts each type's mesh once (original materials) and
  `TerrainChunk` keeps one reused `MultiMeshInstance3D` per type, filled by copying the
  worker's buffer (`multimesh.buffer = …`). Near-only plants cast no shadows. Tree and rock
  draw distances stop at the fog end (≤ 200 m): nothing is drawn that fog hides. Note:
  `visibility_range` applies to the whole chunk MultiMesh, not per instance.
- Collision: trees and large rocks get an upright `CylinderShape3D` per instance (model-unit
  size × instance scale) in the chunk's `StaticBody3D` (`world` layer), LOD 0 chunks only.
  Shape nodes and shapes are pooled per chunk node and reused across applies.
- Look: every vegetation surface uses `shaders/foliage.gdshader` (created once per surface by
  `VegetationLibrary`): the imported colour, recoloured by `data/vegetation_palettes/natural.tres`
  (Kenney's teal/salmon palette clashed with the terrain; user chose the natural palette),
  plus wind sway ∝ (height above base)² so bases stay planted, a per-instance phase in absolute
  coordinates and a coherent world wind direction. Wind is the `wind` global uniform (set from
  `data/world/wind.tres` by `WorldStreamer`, ready for weather). Each type fades over the last
  10 % of its range (`VISIBILITY_RANGE_FADE_SELF`: dithered in Forward+, a cut in Compatibility).
- Quality: `Settings.quality` (a `QualityPreset`, default `data/quality/medium.tres`) scales
  every vegetation density (Low 0.4 / Medium 0.7 / High 1.0, §10). On `quality_changed`,
  `WorldStreamer.refresh()` bumps a generation counter and regenerates every chunk in place
  (old chunks stay visible until replaced).

## 4. Player (quadruped animal)

### 4.1 Species as data
`AnimalSpecies` (Resource): mesh scene, animation library, walk/trot/run speeds,
acceleration, turn rate, jump height, swim ability, diet (Phase 7), need modifiers, sounds.
Swapping species = swapping a `.tres`; no code changes.
First species: **Husky** (`data/species/husky.tres`), Quaternius' Ultimate Animated Animal
Pack (CC0) in `assets/animals/husky/husky.glb`: 49-bone skeleton, 12 clips (Idle, Idle_2,
Idle_2_HeadLow, Walk, Gallop, Gallop_Jump, Jump_ToIdle, Eating, Attack, Death, hit reacts),
none looped in the file. `model_scale` 0.34 fits the 1.3 m capsule; `model_yaw_degrees` 180
turns its +Z-facing rig to the game's −Z forward.
**The player currently plays the Fox** (`data/species/fox.tres`, user's choice after the Husky):
same Quaternius rig and clip names (51 bones, longer 8-bone tail), `model_scale` 0.28 (≈ 1.3 m
nose to tail tip), clip speeds Walk 0.45 / Gallop 2.27 m/s, `walk_speed` 1.1 m/s. The Husky
stays in `data/species/` as an alternative; switching is a one-line change in `animal.tscn`.

### 4.2 Movement
- Scene: `scenes/player/animal.tscn` — `Animal` (CharacterBody3D) with `%MovementComponent`,
  `%PlayerInput` and `%StateMachine` (Idle, Locomotion, Jump, Fall). Forward is `-Z`.
- Physics layers (named in `project.godot`): **1 `world`** (static geometry, terrain),
  **2 `player`**, **3 `interactable`** (interaction targets, Phase 7), **4 `fauna`** (Phase 8;
  collides with `world` only). The player collides
  with `world`; camera collision only checks `world`.
- `CharacterBody3D` with capsule collider oriented horizontally (or two-sphere approximation).
- Camera-relative input; smooth acceleration and turning (quadrupeds turn in arcs, not in place).
- Gaits: walk / trot / run (Shift) driven by speed thresholds.
- **Ground alignment** (`GroundAligner`): four rays under the paws (front/back × left/right,
  species `paw_half_length`/`paw_half_width`) → pitch from front vs back, roll from left vs
  right, clamped to `max_tilt_degrees` (Husky 25°) and exponentially smoothed. Only the model
  pivot (`%Model`) tilts; the CharacterBody3D and its capsule stay upright. Level in the air or
  when `level` is set (swimming).
- States (`StateMachine` component): Idle, Locomotion, Jump, Fall, Swim, Interact (Phase 7),
  Rest.
- **Swimming:** `GameState.water_level` (published by `WorldStreamer`); water depth over the
  paws = water level − body height. `Swim` starts above `swim_enter_depth` and ends below
  `swim_exit_depth` with the paws on the bottom (hysteresis). While swimming, buoyancy pulls
  the body to `float_depth` under the surface instead of gravity, speed × `swim_speed_factor`,
  jumps are dropped and the model stays level. A species with `swim_enter_depth` 0 walks along
  the bottom.
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
- Animation set (`AnimalSpecies.animations`, logical → clip) covers idle, walk, trot, run, jump,
  fall, eat, drink, lie_down, sniff, swim and tired_idle (Phase 6). Husky fallbacks, each
  documented in `animation_fallbacks`: trot → Gallop (slower), fall → Jump_ToIdle, drink → Eating,
  lie_down → Idle_2_HeadLow, swim → slowed Walk, tired_idle → Idle_2_HeadLow looped. A clip
  used both looped and once gets a separate looped copy (`<clip>_loop`).
- Anti-slide: `ClipAnalysis` measures each locomotion clip's authored ground speed from its
  planted paws (Husky: Walk 0.57, Gallop 2.51 m/s); playback scale = speed / that, capped at
  `max_animation_time_scale` (2.5) so legs never cycle frantically (a little slide at full run;
  Husky `walk_speed` is 1.2 m/s so walking matches exactly).
- `AnimationController` (on the Animal) builds its `AnimationTree` in code once `Animal` has
  instanced the species model under `%Model`: a state machine with `locomotion` (BlendSpace1D
  idle/walk/trot/run by speed → TimeScale for anti-slide; the idle point is a Blend2 of rested
  and tired idle driven by `NeedsComponent.tiredness()`), `jump`, `fall`, `swim` and one-shot
  `eat`/`drink`/`lie_down`/`sniff` that return to locomotion at their end. It follows
  `StateMachine.state_changed`; loops are set on copies of the clips in its own library.
- Footsteps: at start-up `ClipAnalysis.contact_times()` finds when each paw touches down in the
  walk and run clips (cached per species model; e.g. the Fox walk is a lateral sequence
  back-right → front-right → back-left → front-left). `AnimationController` runs a clock per
  clip with the tree's delta × scale and emits `footstep(paw)` when the audible clip crosses a
  contact — only in locomotion, on the ground, not swimming, above 0.3 m/s (audio: Phase 9).
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
| `toggle_free_fly` (debug) | F4 |
| `debug_refill_needs` (debug) | F5 |
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
- Data: `NeedDefinition` (`data/needs/{hunger,thirst,temperature,energy}.tres`): value 0…100,
  starts full, lower = needier (for temperature comfort, lower = hotter). `decay_per_minute` is
  the base rate while trotting in neutral conditions. User-chosen "moderate" pacing, full →
  critical at a trot: thirst 8 min, hunger 12 min, energy 15 min, comfort 10 min in a fully
  warm biome. Critical at ≤ 25, recovered only above 35 (`recover_margin`, no flicker).
  Effects when critical: speed × 0.85 (energy × 0.8, and only energy looks tired).
- Modifiers (`NeedModifiers`, `data/needs/need_modifiers.tres`): hunger, thirst and energy change
  at `−decay × multiplier` of the activity (idle / walk / trot / run / swim; missing = 1, negative
  = recovery: energy recovers while idle, 15 min from empty to full). Temperature comfort follows
  the felt warmth instead, `−decay × (biome warmth + activity heat)`: `BiomeDefinition.warmth`
  (hills 1.0, meadow 0.3, forest −0.4, river valley −0.6), running +0.5, idle −0.2; in water
  (wading or swimming) the felt warmth is −1.5, so water always cools off.
- `NeedsModel` (pure): values, `rate_for()`, `tick()`, clamping and critical state with signals
  `value_changed` / `critical_entered` / `critical_exited`. `NeedsComponent` (on the Animal) ticks
  it at 4 Hz with the activity from `MovementComponent`, the warmth of `GameState.current_biome`
  and water depth; it emits `need_changed(id, value)` and relays crossings to
  `EventBus.need_critical` / `need_recovered`. F3 shows the values; F5
  (`debug_refill_needs`) refills them until eating and drinking exist (Phase 7).
- Soft consequences (ADR-003), all eased so nothing snaps: `NeedsComponent` moves
  `MovementComponent.speed_multiplier` (multiplies every target speed) towards the lowest
  `critical_speed_factor` of the critical needs at 0.1/s; `tiredness()` eases to 1 (0.5/s) while a
  `tired_when_critical` need (energy) is critical and drives the tired idle blend (§4.4);
  `NeedsVignette` (`scenes/ui/needs_vignette.tscn`, `shaders/needs_vignette.gdshader`,
  `data/ui/needs_vignette.tres`) warms and darkens the screen edges, half intensity for one
  critical need and full for two or more, fading at 0.25/s.
- HUD (`NeedsHud`, `scenes/ui/needs_hud.tscn`, `data/ui/needs_hud.tres`): bottom left, one
  `NeedMeter` per need, an icon inside a ring that empties with the need (ring colour
  `NeedDefinition.color`). Icons are silhouettes drawn in code by `NeedIcon`: a drop (thirst), an
  apple (hunger), a sun (comfort) and a moon (energy). Kenney's icon packs had no matching set,
  and the user chose code-drawn icons. Meters start hidden, fade in when their need drops below 90 %
  and fade out 2 s after it is full again; a critical meter pulses gently (dims and brightens, no
  red, no sound). The HUD and vignette live in both sandboxes (`main.tscn` is still empty).

## 6. Interaction system

- `Interactable` component (on `Area3D`): `interaction_type` (EAT, DRINK, COOL_OFF, REST,
  SOCIAL), prompt text, duration, need effects, cooldown/regrowth time.
- `Interactor` on the player: shape-casts forward, picks the best target by distance and
  facing angle, shows prompt, runs the interaction (locks movement, plays animation, applies effects).
- Water: chunks with water planes expose DRINK and COOL_OFF (wading/swimming) — implemented
  as the virtual `WaterAccess` provider (below).
- Food sources (berries, grass, fallen fruit) deplete and regrow; state stored per chunk
  as a delta so saves stay small.
- **Implemented (Phase 7):**
  - Physics layer 3 `interactable`. `InteractionDefinition` (`data/interactions/`): type,
    prompt, mode `ONCE` (effects once at the end of `duration`) or `HOLD` (effects per second
    while E is held; stops when those needs are full), `need_effects`, logical animation,
    `food_kind`, `regrowth_minutes`.
  - Providers are colliders on layer 3 implementing `interaction_target(shape_index)` and the
    `is_target_available(key)` / `consume_target(key)` protocol behind `InteractionTarget`;
    `Interactable` (Area3D) is the discrete one.
  - `Interactor` (Node3D on the Animal, `data/interaction/interactor.tres`): a ShapeCast3D
    sphere 0.9 m ahead of the body, probed at 10 Hz and on request; `InteractionScoring`
    (pure) ranks by horizontal distance and facing (≤ 1.8 m, ≤ 80°). `PlayerInput` writes the
    intent (`request_interaction()`, `interact_held`); a request on the ground from Idle or
    Locomotion switches the `StateMachine` to `Interact`.
  - `Interact` state: stops the animal, plays the action through
    `AnimationController.play_action()`, applies the effects via `NeedsComponent.add()`,
    consumes the target and emits `EventBus.interaction_performed(type, id)`. Moving or the
    target going away cancels without effects.
  - `InteractionPrompt` (`scenes/ui/`): "E · Eat berries" at the bottom centre, fading in and
    out with the target and hidden while interacting. F3 shows the current target.
  - **Food:** `berries` (+20 hunger), `apple` (+15 hunger, +5 thirst), `mushroom` (+12),
    `grass` (+10) in `data/interactions/`, 2 s to eat, regrowing after 3 / 5 / 4 / 2 game
    hours. `AnimalSpecies.diet` lists the kinds a species eats (fox and husky: berries,
    fruit, mushroom — no grass; the `Interactor` ignores the rest).
    - Sources are vegetation: `VegetationType.food` (tan mushrooms, large grass) and
      **drops** (`VegetationDrop`), props derived per parent instance on the worker: 4–6
      berry clusters on each **berry bush** (a round bush built in code, `ProceduralMeshes`,
      because the Nature Kit bushes are spiky plants) and 0–3 **apples** on the ground under
      each oak. Drops are seeded per (seed, chunk, type, parent index), LOD 0 only, never under
      water; their meshes (low-poly sphere clusters, plain material) are built by
      `VegetationLibrary`.
    - Each LOD 0 chunk gives every edible instance in the player's diet
      (`WorldStreamer.edible_kinds()`) a sphere in its `FoodArea` (shape owners, no nodes —
      see `docs/notes/terrain-streaming-perf.md`); the chunk is the provider. Eating hides the
      instance (zero scale) and disables its sphere until `GameState.game_minutes` passes its
      regrowth time (checked once a second only while something is depleted).
    - **Per-chunk deltas:** depletion lives in one `ChunkDeltaStore` owned by the
      `WorldStreamer` (`deltas()`) and shared by every chunk: absolute chunk coord → resource
      id → instance index → regrow minute. Only changes are stored. A chunk that loads again
      re-hides what is still depleted and drops what regrew meanwhile; LOD changes keep the
      state; an instance counts as depleted until `regrow()` shows it, so it is never edible
      while invisible. `to_dict()` / `from_dict()` (versioned, JSON-friendly rows) are ready for
      saves (Phase 10, §9).
  - **Water:** `WaterAccess` (on the Animal) is a virtual provider (no shapes) registered with
    the `Interactor` (`add_virtual_provider()`), asked on every probe. DRINK (`drink.tres`,
    HOLD +12.5 thirst/s, empty → full in 8 s) when the ground 0.8 m ahead of the nose lies
    ≥ 5 cm under `GameState.water_level` (one reused downward ray on the `world` layer) and
    the paws are at most 0.6 m above the surface, or while wading; COOL_OFF (`cool_off.tres`,
    HOLD +20 comfort/s) only while wading (paws 5 cm … `swim_enter_depth` deep). Wading, it
    offers whichever of thirst and comfort is lower; each target stays available while its own
    condition holds, so a drink is never cut short. No water targets while swimming; water
    never runs out.
  - **Rest:** holding R on the ground (from Idle or Locomotion, not swimming) — or choosing a
    REST target such as a den with E — switches to the `Rest` state (lying, tired-idle loop):
    energy recovers at `data/interaction/rest.tres` × place (open 1.67/s, **shade** ×2, **den**
    ×3; on top of the idle recovery) and `GameState.clock_scale` is ×10 (reset on leaving, even
    if freed). It gets up on release or move input. `Rester` decides the place: DEN when the
    `Interactor`'s target is a REST target, SHADE when `WorldStreamer.is_shaded()` (group
    `world_streamer`) finds a tree within `VegetationType.shade_radius` × scale (trees only;
    O(trees in the chunk)), else OPEN. Dens are `den_log` props (Kenney `log_large`, rare in
    every biome) whose `interaction` is `den.tres`; vegetation `food` became `interaction`, so
    chunk targets also carry non-food interactions (dens never deplete, need no diet).
  - **Sniff (Q):** `Sniffer` (on the Animal, `data/interaction/sniff.tres`) plays the sniff
    animation when nearly still and, with one sphere query on the interactable layer (same
    provider protocol), lights up the nearest 24 available foods in the diet within 25 m with
    pooled billboard sparkles (`shaders/sniff_marker.gdshader`: unshaded, additive, pulsing;
    growing with distance beyond 8 m so far ones stay legible), plus one blue sparkle at the
    nearest water (16 directions × 6 rings of downward rays). Sparkles last 4 s, fading over the
    last 1.2 s; 2 s cooldown. Sparkles are floating-origin shiftable.

## 7. Fauna AI

- `FaunaDirector` spawns animals per loaded chunk from the biome's fauna table, caps the
  global count and despawns with the chunk.
- `FaunaAgent`: lightweight FSM (Wander, Graze, Flee, Approach, Follow, Rest), steering
  on terrain (seek, avoid, separation) instead of navmesh baking per chunk.
- Perception: distance + angle checks at 5–10 Hz with staggered updates.
- Temperament per species: shy (flees), curious (approaches), friendly (can follow player
  after a SOCIAL interaction). Social interactions: greet/sniff, play, follow.
- Distant agents degrade to cheaper update rates (AI LOD).
- **Implemented (Phase 8):**
  - `FaunaAgent` (`scenes/fauna/fauna_agent.tscn`): a CharacterBody3D on layer 4 with the
    player's components — `MovementComponent` (`camera_relative` off: `move_input` is a world
    XZ direction), `AnimationController`, `GroundAligner`, `StateMachine` — and the species
    model spawned by the shared `Animal.spawn_species_model()`. Behaviour states
    (`FaunaState`) write intent and run the same `apply_*` / `move` ticks as the player
    states. Each agent has its own seeded RNG (`decision_seed`) and a `home`; it is
    floating-origin shiftable (home shifts with `EventBus.origin_shifted`).
  - **Behaviours** (states named as `FaunaDecision` constants): Wander (random points within
    `radius` of home, 2–6 s pauses, `wander_steps` per bout), Graze (stand, eat animation),
    Rest (lying pose via the controller's `Rest` mapping), Flee (sprint away from the player),
    Approach (walk to `approach_stop_distance`, watch `watch_time`), Follow (keep
    `follow_distance`, trot to catch up, for `duration`; started by `FaunaBrain.start_follow`).
    Each reports `is_done()` when its bout ends.
  - **`FaunaBrain`** perceives the player (group `player`: distance, closing speed, direction)
    at 5 Hz, staggered per agent, and asks the pure **`FaunaDecision.decide()`**: an unfinished
    Follow first; then fleeing (inside `flee_radius` when the player closes faster than
    `flee_trigger_speed`, or inside `startle_radius`; kept until `safe_distance`); an
    unfinished Approach; a new Approach by `approach_chance` inside `approach_radius`; the
    current bout while not done; else wander / graze / rest by `idle_weights`. Tunables:
    `FaunaProfile` (`data/fauna/`).
  - **Steering on terrain** (no navmesh): `FaunaSteering.clear_direction()` tries the desired
    direction, then ±30°…±135°, against `FaunaAgent.is_clear()` — an obstacle feeler (0.4 m
    high, 1.2 m) that rejects surfaces steeper than the species' walk limit, and a ground probe
    1.5 m ahead rejecting drops, water and steep ground. The choice is kept for 0.1 s. The
    brain adds a separation push from agents within 2 m. A wander target that cannot be
    reached is dropped.
  - **Species and temperaments** (data): `FaunaSpecies` (`data/fauna/`: id, name, the
    `AnimalSpecies`, temperament, profile, herd size, wander radius, follow time) sets the
    agent's species, brain profile and wander radius (`FaunaAgent.fauna`). Temperament
    profiles in `data/fauna/temperaments/`: **shy** (flees from a fast approach within 14 m or
    anything within 1 m — walking up slowly is fine — until 30 m), **curious** (walks over to look from 5 m; flees only if
    rushed at very close), **friendly** (comes to 2.5 m, never flees), **calm** (grazes most,
    flees only if nearly run over). Traits: all can be greeted; curious and friendly play;
    friendly ones follow after playing.
  - **Species** (Quaternius Ultimate Animated Animal Pack via the Poly Pizza mirror, CC0, same
    rig and clips as the fox; `assets/animals/<id>/` with LICENSE.md): **deer** and **stag**
    (shy), **shiba_inu** (friendly), **alpaca** (curious), **horse** and **donkey** (calm).
    `data/species/<id>.tres` holds the model (scales 0.30–0.48, measured against the fox), clip
    ground speeds measured with `ClipAnalysis` at that scale (walk speed ≈ walk clip, so hooves
    do not slide), gaits, and a collision capsule (`AnimalSpecies.body_radius` /
    `body_length`, fitted by `FaunaAgent`); none swims. `data/fauna/<id>.tres` adds
    temperament, herd size and wander radius. Hoofed clips differ in name (`Idle_Headlow`,
    `Jump_toIdle`).
  - **Spawning** (`FaunaDirector` in the world scene, `data/fauna/director.tres`): when a chunk
    becomes full detail (LOD 0, `WorldStreamer.chunks_changed`), the pure `FaunaPlan.roll()`
    decides — seeded per (world seed, chunk) — whether it hosts a herd (biome `fauna_chance`,
    12–15 %), of which species (`BiomeDefinition.fauna` weights) and where (within 12 m of the
    chunk centre). Spawns are queued (1 per frame) and placed by a downward ray on dry ground
    ≤ 25° and ≥ 25 m from the player. **Cap: 10 animals.** An animal leaves when its chunk
    stops being full detail (its collision goes) or beyond 120 m; the same chunk brings the
    same herd back. `warm_up()` instances each species once at load, so herds appear in ≈ 1 ms.
  - **AI LOD** (4 Hz checks): ≤ 40 m full (brain 5 Hz, ground alignment every 4th tick); ≤ 90 m
    brain 2 Hz, behaviour every 3rd tick (`FaunaAgent.tick_stride`), no alignment; beyond,
    frozen (`PROCESS_MODE_DISABLED`). Fauna skip footstep analysis and share one looped clip
    library per species.
  - **Social** (SOCIAL interactions, no need effects — user decision): every agent carries an
    `Interactable` (`%Social`, layer 3) whose definition names the species ("Greet the deer").
    The provider protocol gained an optional `begin_target(key)` (`InteractionTarget.begin()`,
    called by the Interact state), so the animal stops and sniffs back (`Social` state) while
    the fox greets it (`greet.tres`, 2 s, sniff). Afterwards curious and friendly animals offer
    **"Play with the …"** (`play.tres`, 1.5 s): they gallop in circles around the fox (`Play`, 5 s)
    and friendly ones then **follow** for `follow_seconds` (75 s). Calm and shy ones just accept
    the greeting; greeting again waits 20 s; nobody can be greeted while fleeing, following or
    playing. A moment with the player (Social, Play, Follow) is never cut short by
    `FaunaDecision`. Shy animals flee from a fast approach but let a calm one close (startle
    1 m). `EventBus.animal_greeted` / `animal_played(species_id)` for audio (Phase 9) and a
    future discoveries journal.
  - **Cost** (WSL, 10 animals at full rate, timed directly): AI ≈ 0.65 ms/frame (behaviour +
    `move_and_slide` 0.48, alignment 0.13, brain 0.05) — under the 1.5 ms budget. The engine's
    per-body/per-skeleton work adds ≈ 1–1.5 ms of physics time on top (noisy under WSL).

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
