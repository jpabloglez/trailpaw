# Trailpaw

[![CI](https://github.com/jpabloglez/trailpaw/actions/workflows/ci.yml/badge.svg)](https://github.com/jpabloglez/trailpaw/actions/workflows/ci.yml)

A cozy open-world nature game where you roam as a small animal through a landscape that
changes the farther you wander. Forage, drink, cool off, rest and meet other animals.
Made with Godot 4.

> **Status:** vertical slice (v0.12.0, Phase 12). See [ROADMAP.md](ROADMAP.md).

## Play

**Download:** the latest build for Windows or Linux is on the
[Releases](https://github.com/jpabloglez/trailpaw/releases) page. It is a single zip with one
executable inside; unzip it and run `Trailpaw.exe` (Windows) or `Trailpaw.x86_64` (Linux; make
it executable first). Every push to `main` also produces `trailpaw-windows` and `trailpaw-linux`
builds under [Actions](https://github.com/jpabloglez/trailpaw/actions/workflows/ci.yml); you
need to be logged in to GitHub to download them.

Windows may warn that the app is from an unknown publisher (it is not code-signed). Choose
*More info → Run anyway*.

**System:** a GPU with Vulkan support is recommended (older GPUs fall back to OpenGL). The target is 60 FPS at 1080p "Medium" on a GTX 1050.
Lower *Quality* or *Render scale* in Settings if it stutters.

**You are a small fox.** Wander a landscape that changes the farther you go: meadow, forest,
river valley, hills. Keep an eye on thirst, hunger, warmth and energy. Sniff out food and
water, rest in the shade, meet the other animals. Nothing can kill you, but neglect slows you
down. The game saves as you go: quit anywhere and *Continue* puts you back where you were.

| Action | Keys |
|---|---|
| Move | W A S D |
| Run | Shift (hold, or toggle in Settings) |
| Jump | Space |
| Look around | Click to capture the mouse, then move it |
| Zoom | Mouse wheel |
| Eat · drink · greet · play | E (hold to drink) |
| Sniff for food and water | Q |
| Rest | R (hold, or toggle in Settings) |
| Map | M |
| Pause · menu | Esc |

Every key can be changed in *Settings → Controls*. *Settings → Interface* has text size and
the onboarding hints.

## Build from source

### Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Godot | **4.7.1-stable** (standard, not .NET) | Pinned in [`.godot-version`](.godot-version). Do not upgrade without an explicit task. |
| Git + Git LFS | Git ≥ 2.34, git-lfs ≥ 3 | Binary assets (`.glb .png .wav .ogg .blend .exr`) live in LFS. |
| Python | 3.11+ | Only for dev tooling (lint, format, tests). |

#### Installing Godot (Linux / WSL2)

```bash
V=$(cat .godot-version)                      # 4.7.1-stable
B=https://github.com/godotengine/godot/releases/download/$V
curl -LO $B/Godot_v${V}_linux.x86_64.zip -LO $B/SHA512-SUMS.txt
grep " Godot_v${V}_linux.x86_64.zip$" SHA512-SUMS.txt | sha512sum -c -
mkdir -p ~/.local/opt/godot/$V && unzip Godot_v${V}_linux.x86_64.zip -d ~/.local/opt/godot/$V
ln -sf ~/.local/opt/godot/$V/Godot_v${V}_linux.x86_64 ~/.local/bin/godot
godot --version                              # 4.7.1.stable.official.a13da4feb
```

On Windows or macOS, download the same version from
<https://godotengine.org/download/archive/>.

#### `GODOT_BIN`

The gdUnit4 runner (`addons/gdUnit4/runtest.sh`) finds Godot through the `GODOT_BIN`
environment variable, and it has to point at the **real binary**, not a symlink wrapper:

```bash
export GODOT_BIN="$(readlink -f "$(command -v godot)")"
# reference machine (WSL2): /home/<user>/.local/opt/godot/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64
```

### Setup

```bash
git clone git@github.com:jpabloglez/trailpaw.git && cd trailpaw
git lfs install && git lfs pull

python -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m tools.godot_version      # checks Godot matches .godot-version

godot --headless --path . --import           # first import; must finish with no errors
```

Opening the project in the editor: `godot --editor --path .` (or import `project.godot`
from the Godot project manager). Run the game with F5 (the main menu, `scenes/main/main.tscn`).

### Exporting builds

Install the export templates of the pinned version (Godot editor: *Editor → Manage Export
Templates*, or unpack the official `.tpz` into `~/.local/share/godot/export_templates/4.7.1.stable/`),
then:

```bash
mkdir -p export/windows export/linux
godot --headless --path . --export-release "Windows Desktop" export/windows/Trailpaw.exe
godot --headless --path . --export-release "Linux" export/linux/Trailpaw.x86_64
```

The presets (`export_presets.cfg`) embed the game data in the executable and leave tests and
tooling out. Pushing a `v*` tag runs [`release.yml`](.github/workflows/release.yml), which
builds both and publishes them as a GitHub Release.

## Development

```bash
# The game (main menu)
godot --path .

# Movement sandbox (Phase 1): WASD move, Shift run, Space jump,
# click to capture the mouse and orbit, wheel to zoom, Esc to release, F3 debug overlay
godot --path . res://scenes/debug/movement_sandbox.tscn

# Terrain sandbox (Phase 2): streamed terrain around the animal; F4 free-fly camera
# (WASD + mouse, Shift boost, wheel = speed), F3 overlay + chunk borders
godot --path . res://scenes/debug/terrain_sandbox.tscn
# 10 km streaming probe (report + exit code; see docs/notes/terrain-streaming-perf.md)
godot --headless --path . res://scenes/debug/terrain_sandbox.tscn -- --auto-travel=10000
# Frame-time probe on the real game (needs a GPU; see docs/notes/perf/README.md)
godot --path . res://scenes/debug/perf_probe.tscn
.venv/bin/python -m tools.perf_report <the CSV it prints>

# Lint and format (GDScript)
.venv/bin/gdlint scripts/ tests/
.venv/bin/gdformat --check scripts/ tests/

# Lint, format and tests (Python tooling)
.venv/bin/ruff check tools/ && .venv/bin/ruff format --check tools/
.venv/bin/python -m pytest tools/tests

# GDScript tests (gdUnit4); reports go to reports/
GODOT_BIN="$(readlink -f "$(command -v godot)")" \
  ./addons/gdUnit4/runtest.sh --headless --ignoreHeadlessMode -a res://tests
```

With [Claude Code](https://claude.com/claude-code), `/check` runs all of the above, and
`/phase-status` summarises ROADMAP progress.

## Continuous integration

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push and pull request to
`main`:
1. **Lint:** gdlint, gdformat, ruff, pytest.
2. **Headless import:** checks the Godot version against the pin and fails on any import
   error.
3. **gdUnit4 tests**, plus **Export builds** in parallel: Windows and Linux, a headless smoke
   test of the Linux build, and both uploaded as artifacts.

Godot and its export templates are downloaded from the official release, checked against
their SHA512 and cached.

## Project docs

- [CLAUDE.md](CLAUDE.md): tech stack, repository layout, coding conventions, rules for
  contributors
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): technical architecture
- [docs/adr/](docs/adr/): architecture decision records
- [ROADMAP.md](ROADMAP.md): phases, tasks and exit criteria
- [docs/notes/](docs/notes/): measurements and investigations (performance)
- [docs/playtests/](docs/playtests/): how playtests are run and their notes
- [assets/CREDITS.md](assets/CREDITS.md): third-party asset credits

## Credits

Trailpaw is made with [Godot Engine](https://godotengine.org) (MIT). All third-party assets are
CC0 (public domain), with thanks to:
- **Kenney** ([kenney.nl](https://kenney.nl)): Nature Kit (trees, plants, rocks, flowers),
  Impact Sounds (footsteps) and Interface Sounds.
- **Quaternius**: Ultimate Animated Animal Pack (fox, deer, stag, Shiba Inu, alpaca, horse,
  donkey, husky), via the [Poly Pizza](https://poly.pizza) mirror.
- **OpenGameArt.org** authors Thimras, isaiah658, Wolfgang_, Kresiek The Furry (ambience),
  rubberduck (water splashes) and StarNinjas (donkey bray).

Every file, its author and source is listed in [assets/CREDITS.md](assets/CREDITS.md) (audio
notes in [assets/audio/LICENSE.md](assets/audio/LICENSE.md)).

## Licence

The project's source code and original content are released under the [MIT Licence](LICENSE).
Third-party components keep their own licences:
- Godot Engine (MIT), embedded in the exported builds
- gdUnit4 (MIT, development only, not in the builds): `addons/gdUnit4/LICENSE`
- assets: CC0, see [`assets/CREDITS.md`](assets/CREDITS.md)
