# Frame-time measurements (Phase 11)

The Phase 11 exit criterion is **p95 frame time ≤ 16.6 ms on Medium on the target PC**
(GTX 1050, native Windows, Forward+). WSL2 is not representative: it renders through Mesa's
GL-on-D3D12 layer with the Compatibility renderer.

## Running the probe on Windows

**With the release build (preferred: it is what players run).** Unzip the `trailpaw-windows`
artifact (or a Release) and, from PowerShell in that folder:

```powershell
.\Trailpaw.exe -- --perf-probe
```

**Or with the editor's Godot** and the project folder:

```powershell
$godot = "C:\Users\juanp\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
& $godot --path C:\Users\juanp\Juegos\trailpaw res://scenes/debug/perf_probe.tscn
```

The window opens, waits for the first area to load, flies on its own for about 4 minutes and
closes. Options after `--`: `--distance=3600` (m), `--speed=15` (m/s),
`--preset=low|medium|high`, `--out=user://perf/name.csv`. Leave the PC otherwise idle while it
runs. (Release builds cannot open a scene given on the command line, hence the game's own
`--perf-probe` flag, handled by `GameFlow`.)

The CSV is written to `%APPDATA%\Godot\app_userdata\Trailpaw\perf\` (seen from WSL as
`/mnt/c/Users/juanp/AppData/Roaming/Godot/app_userdata/Trailpaw/perf/`).

## Making the report

```bash
.venv/bin/python -m tools.perf_report /mnt/c/Users/juanp/AppData/Roaming/Godot/app_userdata/Trailpaw/perf/<run>.csv \
  --out docs/notes/perf/<name>.md
```

Exit status 0 = PASS, 1 = FAIL. One report per milestone: `baseline.md` (start of Phase 11),
`phase11.md` (close).
