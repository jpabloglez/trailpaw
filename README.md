# Trailpaw

[![CI](https://github.com/jpabloglez/trailpaw/actions/workflows/ci.yml/badge.svg)](https://github.com/jpabloglez/trailpaw/actions/workflows/ci.yml)

A cozy open-world nature game where you roam as a small animal through a landscape that
changes the farther you wander. Forage, drink, cool off, rest and meet other animals.
Made with Godot 4.

> **Status:** Phase 0 (project setup and tooling). See [ROADMAP.md](ROADMAP.md).

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Godot | **4.7.1-stable** (standard, not .NET) | Pinned in [`.godot-version`](.godot-version). Do not upgrade without an explicit task. |
| Git + Git LFS | Git ≥ 2.34, git-lfs ≥ 3 | Binary assets (`.glb .png .wav .ogg .blend .exr`) live in LFS. |
| Python | 3.11+ | Only for dev tooling (lint, format, tests). |

### Installing Godot (Linux / WSL2)

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

### `GODOT_BIN`

The gdUnit4 runner (`addons/gdUnit4/runtest.sh`) finds Godot through the `GODOT_BIN`
environment variable, and it has to point at the **real binary**, not a symlink wrapper:

```bash
export GODOT_BIN="$(readlink -f "$(command -v godot)")"
# reference machine (WSL2): /home/<user>/.local/opt/godot/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64
```

## Setup

```bash
git clone git@github.com:jpabloglez/trailpaw.git && cd trailpaw
git lfs install && git lfs pull

python -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m tools.godot_version      # checks Godot matches .godot-version

godot --headless --path . --import           # first import; must finish with no errors
```

Opening the project in the editor: `godot --editor --path .` (or import `project.godot`
from the Godot project manager).

## Everyday commands

```bash
# Play the movement sandbox (Phase 1): WASD move, Shift run, Space jump,
# click to capture the mouse and orbit, wheel to zoom, Esc to release, F3 debug overlay
godot --path . res://scenes/debug/movement_sandbox.tscn

# Terrain sandbox (Phase 2): streamed terrain around the animal; F4 free-fly camera
# (WASD + mouse, Shift boost, wheel = speed), F3 overlay + chunk borders
godot --path . res://scenes/debug/terrain_sandbox.tscn
# 10 km streaming probe (report + exit code; see docs/notes/terrain-streaming-perf.md)
godot --headless --path . res://scenes/debug/terrain_sandbox.tscn -- --auto-travel=10000

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

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push and pull
request to `main`, in three steps: **lint** (gdlint, gdformat, ruff, pytest) →
**headless import** (checks the Godot version against the pin, fails on any import error)
→ **gdUnit4 tests** (the report is uploaded as an artifact). Godot is downloaded from the
official release, checked against its SHA512 and cached.

## Project docs

- [CLAUDE.md](CLAUDE.md): tech stack, repository layout, coding conventions, rules for
  contributors
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): technical architecture
- [docs/adr/](docs/adr/): architecture decision records
- [ROADMAP.md](ROADMAP.md): phases, tasks and exit criteria
- [assets/CREDITS.md](assets/CREDITS.md): third-party asset credits

## Licence

The project's source code and original content are released under the [MIT Licence](LICENSE).
Third-party components keep their own licences:
- gdUnit4 (MIT): `addons/gdUnit4/LICENSE`
- assets: see [`assets/CREDITS.md`](assets/CREDITS.md)
