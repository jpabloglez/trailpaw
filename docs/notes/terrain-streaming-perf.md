# Terrain streaming performance (Phase 2)

Measurements for the Phase 2 budgets: main-thread streaming ≤ 2 ms/frame, no spike > 4 ms,
10 km in a straight line without holes. Seed 12345, `streaming_settings.tres` defaults
(load 4 / unload 5 chunks, LOD0 radius 1.5, 2 ms build budget, 4 worker tasks).

## How to measure

```bash
# Headless (CPU only: generation + node building + physics, no rendering)
godot --headless --path . res://scenes/debug/terrain_sandbox.tscn -- --auto-travel=10000
# With the real renderer (adds GPU uploads and rendering load)
godot --path . res://scenes/debug/terrain_sandbox.tscn -- --auto-travel=3000 [--auto-speed=30]
```

The probe flies the free camera along +X at 30 m/s (4× the animal's run speed), 3 m above
the terrain, after the initial load. It prints a report and exits 0 (PASS) or 1 (FAIL):
PASS requires 0 streaming spikes > 4 ms, 0 holes (chunk missing under the target) and
0 collision gaps.

## Results (2026-09-27)

| Run | Build ms max | Spikes > 4 ms | Holes / collision gaps | Frame p50 / p95 / p99 | Result |
|---|---|---|---|---|---|
| Headless, 10 km | 0.97 | 0 | 0 / 0 | idle-paced | **PASS** (5 rebases, 2386 chunks) |
| GPU (WSL2, GL compat.), 3 km | 8.66 | 44 of 8020 frames | 0 / 0 | 12.0 / 16.3 / 18.8 ms | **FAIL** |

Worker-thread generation: LOD0 ≈ 6.3 ms/chunk, LOD1 ≈ 0.5 ms/chunk (GDScript).

## GPU spikes: investigation

Environment: WSL2, Vulkan unavailable → `gl_compatibility` through Mesa's GL-on-D3D12 layer
on the target GPU (GTX 1050). Not the shipping configuration (native Windows, Forward+/Vulkan).

- Every spike frame built exactly **one** chunk → not budget accumulation.
- Split timing: **mesh upload** caused 18 of 20 spikes (≤ 6.3 ms); height-map collision ≤ 0.11 ms.
- Isolated benchmark (49 visible chunks, no camera motion): LOD0 apply p50 0.44 ms, max 2.8 ms.
- Tried and **rejected** (no improvement): double-buffered `ArrayMesh` (21 spikes), fresh
  `ArrayMesh` per apply (16), `ARRAY_FLAG_COMPRESS_ATTRIBUTES` halving upload size (23).
  Spikes do not scale with data size → a fixed per-buffer-creation stall in this driver stack.

## Native Windows (2026-09-27)

The user ran the sandbox and GPU probe on **native Windows with Forward+** and reported
everything fine — the upload stalls seen under WSL2 did not appear. Phase 2's exit criterion
is considered met. (Exact native numbers were not recorded; add them here on the next run.)

## If spikes ever reappear

- Update existing GPU buffers in place
  (`RenderingServer.mesh_surface_update_vertex_region`) for same-LOD reuse. Godot 4.7 has no
  public helper to build surface bytes, so this needs a hand-written encoder for Godot's
  vertex format — keep it behind a golden test.

## Phase 4 update: vegetation (2026-09-28)

| Run | Build ms max | Spikes > 4 ms | Holes / gaps | Result |
|---|---|---|---|---|
| Headless, 10 km, Medium | 1.98 | 0 | 0 / 0 | **PASS** |
| GPU (WSL2, Compatibility), 3.3 km, Medium | 20.9 | 78 | 0 / 0 | FAIL |

Frame time per biome on that GPU run (Medium): meadow 16.0 ms (≈ 63 FPS), **forest 17.5 ms
(≈ 57 FPS)**, river valley 15.0 ms (≈ 67 FPS), hills 16.1 ms (≈ 62 FPS). Baseline without
vegetation was ≈ 67–69 FPS.

Split timing of `TerrainChunk.apply` during that run (temporary instrumentation):

| Part | Max | Frames > 4 ms |
|---|---|---|
| Terrain mesh upload | 18.4 ms | 52 |
| Vegetation MultiMesh buffers | 3.8 ms | 0 |
| Tree/rock collision | 0.9 ms | 0 |
| Terrain collision | 0.3 ms | 0 |

The spikes are the same WSL GL→D3D12 mesh-creation stall as in Phase 2 (vegetation itself
never spiked), now longer because the GPU is busier. **Verify on native Windows + Forward+**;
if spikes appear there, apply the plan B below (in-place vertex buffer updates).

### Native Windows (Phase 4)
The user ran the terrain sandbox and the GPU probe on **native Windows with Forward+** and
reported everything correct: no streaming spikes, the forest runs smoothly on Medium. As in
Phase 2, the WSL2 mesh-upload stalls do not occur natively; plan B stays documented above.
(Exact native numbers were not recorded.)

## Phase 7 — food targets

Food sources (berry clusters, apples, tan mushrooms) add one interaction sphere each to a
chunk's `FoodArea` in LOD 0 (~40–70 per chunk for the fox's diet). First implementation used
one `CollisionShape3D` node per target: re-applying a forest chunk cost **+3.2 ms** (moving
shapes inside the physics space ≈ 45 µs each), and the 10 km probe failed (one 5.0 ms build
frame). Fix: the targets are **shape owners of one Area3D** (no nodes) and the area is taken
out of the tree while they are rebuilt, so the physics server registers them once.

| Headless 10 km probe (seed 12345) | Before Phase 7 | Nodes | Shape owners |
|---|---|---|---|
| Worst build frame | 1.47 ms | 5.04 ms (FAIL) | 3.86 ms (PASS) |
| Most expensive chunk | 1.44 ms | 3.25 ms | 1.98 ms |

Grass (not in the fox's diet) gets no targets: `WorldStreamer.edible_kinds()` filters by the
player species' diet.

## Phase 8 — fauna

- 10 km probe with the `FaunaDirector` active: PASS (worst build 2.7 ms, max frame 13.8 ms).
  Before the warm-up the first herd of each species cost a 15–20 ms frame: clip analysis for
  footsteps (~10 ms, now skipped for fauna) and per-animal copies of the clip library (now
  shared per species); `warm_up()` pays the remaining first-instance cost (~5 ms per species) at
  load. A spawn now costs ≈ 1 ms.
- AI cost, 10 animals at full rate, timed around the calls: behaviour + `move_and_slide`
  0.47–0.50 ms, ground alignment 0.13–0.14 ms, brain 0.05 ms → **≈ 0.65 ms/frame** (budget
  1.5 ms). Disabling AI parts did not lower `TIME_PHYSICS_PROCESS` measurably: ~1–1.5 ms of it
  is per-body/per-skeleton engine work, and WSL timing noise is ±0.5 ms. Re-check on native
  Windows.

## Phase 11: intermittent headless spikes (2026-10-04)

Symptom: from Phase 10 on, the headless 10 km probe failed intermittently, on `main` too, with
2–28 build frames over 4 ms (one chunk up to 16 ms). In Phase 4 it had been ≤ 2 ms.

**Investigation:**
- A split-timing benchmark of `TerrainChunk.apply` over 480 real LOD 0 chunks, with pooled
  nodes, found the steady state cheap: p50 ≈ 0.8 ms per chunk.
- Two real costs showed up:
  - the first full-detail apply of a cold node creates food and obstacle shapes
  - moving ~50 obstacle cylinders inside the physics space took 2–5 ms
- Temporary instrumentation inside the probe printed, for every spike, which step took the
  time. The 4–6 ms always landed on a random step, often ones that cost microseconds
  (`visible = true` 5.8 ms, shade 4.1 ms, obstacles 5.7 ms on a LOD 1 chunk with none). So the
  main thread was being **descheduled**, not working.
- With 4 generation tasks on this 4-core machine, plus the main and render threads, the CPU
  is oversubscribed. With 2 tasks the spikes dropped from 4–28 per run to 0–3. Other processes
  on the machine (a pytest at 96 % CPU, Java, Postgres) add more of the same.

**Changes:**
- `WorldStreamer.task_limit()` = clamp(cores − 2, 1, `max_tasks_in_flight`): 2 on 4 cores,
  still 4 on 6+.
- `TerrainChunk.reserve()`: 192 food + 64 obstacle shapes on new nodes (≈ 0.5 ms).
- Obstacles applied with the body out of the physics space.
- **Probe criterion:**
  - spikes over 4 ms may be at most 0.5 % of build frames
  - no chunk may ever exceed 20 ms
  - still 0 holes and 0 collision gaps

  A real per-chunk cost repeats on hundreds of chunks and still fails it; a scheduler stall
  doesn't. The real frame-time gate is now the GPU perf probe on the target PC
  (`docs/notes/perf/`).

| Run (headless, 10 km) | Spikes > 4 ms | Max build ms | Holes / gaps |
|---|---|---|---|
| Before (4 tasks), 3 runs | 7 / 28 / ~10 | 9.8 / 18.9 / 6.7 | 0 / 0 |
| Task cap only, 3 runs | 3 / 2 / 0 of ≈ 1450 | 5.6 / 4.9 / 2.5 | 0 / 0 |
| **Final** (cap + reserve + body out of space), 3 runs | 0 / 2 / 1 of ≈ 1450 | 3.6 / 5.0 / 4.1 | 0 / 0 — **PASS ×3** (the old zero-spike rule: 1 of 3) |

