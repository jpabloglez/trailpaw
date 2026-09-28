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
