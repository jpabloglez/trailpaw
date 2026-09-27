# CLAUDE.md — Project guide for Claude Code

> Codename: **Trailpaw** — a cozy open-world nature game where the player controls an
> endearing quadruped animal (dog, capybara, etc.). The landscape changes as the player
> travels further from the starting point. Core loops: foraging, drinking, cooling off,
> resting and interacting with other animals.

Read `docs/ARCHITECTURE.md` before touching any system and `ROADMAP.md` to know which
phase is active. Only implement tasks belonging to the current phase unless told otherwise.

---

## 1. Tech stack (all open source)

| Area | Choice | Notes |
|---|---|---|
| Engine | Godot 4.x stable (MIT) | Exact version pinned in `.godot-version`. Never upgrade without an explicit task. |
| Renderer | Forward+ (Vulkan) | Must hold 60 FPS @1080p "Medium" preset on a GTX 1050. Compatibility renderer is the fallback. |
| Gameplay language | GDScript, **fully statically typed** | C++ via GDExtension only for profiled hotspots (Phase 11+). |
| Tests | gdUnit4 | Unit + scene tests under `tests/`. |
| Lint / format | gdtoolkit (`gdlint`, `gdformat`) | Installed with pip; config in `gdlintrc`. |
| Tooling scripts | Python 3.11+ | Asset/QA helpers in `tools/`. NumPy-style docstrings. |
| 3D content | Blender | Export `.glb` only. |
| Placeholder assets | Quaternius, Kenney, Poly Haven (CC0) | Record every asset in `assets/CREDITS.md`. |
| VCS | Git + Git LFS | LFS for `.glb .png .wav .ogg .blend .exr`. |
| CI | GitHub Actions + headless Godot | Lint, tests, export check. |

## 2. Commands

```bash
# Import resources (run after adding assets or on a fresh clone)
godot --headless --path . --import

# Run the game / a specific scene
godot --path .
godot --path . res://scenes/debug/terrain_sandbox.tscn

# Tests (verify flags against the installed gdUnit4 version)
./addons/gdUnit4/runtest.sh -a res://tests

# Lint and format check
gdlint scripts/ tests/
gdformat --check scripts/ tests/

# Python tooling
python -m pytest tools/tests
```

**Definition of done for any task:** import succeeds with no errors, `gdlint` and
`gdformat --check` pass, all tests pass, and new logic has tests.

## 3. Repository layout

```
.
├── CLAUDE.md / ROADMAP.md / README.md
├── .godot-version               # pinned engine version
├── project.godot
├── addons/                      # third-party plugins (gdUnit4, ...) — do not edit
├── assets/                      # imported art/audio (LFS) + CREDITS.md
│   ├── animals/  environment/  audio/  ui/
├── data/                        # .tres Resources: species, biomes, needs, items
├── scenes/
│   ├── main/                    # main.tscn, world.tscn
│   ├── player/  fauna/  world/  ui/
│   └── debug/                   # sandboxes for isolated testing
├── scripts/
│   ├── autoload/                # EventBus, GameState, Settings, SaveSystem
│   ├── components/              # reusable node components
│   ├── player/  fauna/  world/  needs/  interaction/  ui/
│   └── util/
├── shaders/
├── tests/                       # mirrors scripts/ structure
├── tools/                       # Python helpers + tools/tests
└── docs/                        # ARCHITECTURE.md, ADRs, notes
```

## 4. Coding conventions

- Language: English for identifiers, comments, docs and commit messages.
- GDScript style follows the official Godot style guide:
  - `snake_case` for files, functions, variables; `PascalCase` for `class_name` and nodes;
    `CONSTANT_CASE` for constants.
  - Every script declares `class_name` unless it is a one-off scene script.
  - Static typing everywhere: `var speed: float = 4.0`, `func f(x: int) -> Vector3:`.
  - Document public classes, functions and exported properties with `##` doc comments.
  - Script member order: signals → enums → constants → `@export` → public vars →
    private vars (`_prefix`) → `@onready` → built-in callbacks → public methods → private methods.
- Python in `tools/`: type hints, NumPy-style docstrings, `ruff` clean.
- Prefer **composition**: small components (child nodes) over deep inheritance.
- Tunable values live in `.tres` Resources under `data/`, never as magic numbers.
- Systems communicate via signals or `EventBus`; no `get_node("../../..")` chains.
- Use `@onready var x: Node = %UniqueName` for scene-internal references.
- Deterministic generation: all procedural code takes an explicit seed / `RandomNumberGenerator`.

## 5. Rules for Claude Code

1. Work in small, reviewable steps: one ROADMAP task → one branch → one PR-sized diff.
2. Start non-trivial tasks in plan mode; list the files you will create or change.
3. Write or update tests **before** or alongside implementation.
4. Never edit: `.godot/`, `*.import`, `addons/` (third-party), files in `assets/` binaries.
5. `.tscn`/`.tres` files may be edited as text but keep diffs minimal and valid; prefer
   building complex node trees in code or asking the user to do it in the editor.
   After editing a scene, run the headless import to validate it.
6. Do not add dependencies or plugins without an ADR in `docs/adr/`.
7. Do not change the public API of an autoload without updating its callers and tests.
8. Performance-sensitive code (chunk generation, vegetation, AI ticks) must state its
   budget in a comment and avoid per-frame allocations.
9. When something cannot be verified headlessly (visuals, feel), say so explicitly and
   list what the user should check in the editor.
10. Update `ROADMAP.md` checkboxes and `docs/ARCHITECTURE.md` when a task changes them.

## 6. Commit convention

Conventional Commits: `feat(world): stream terrain chunks on worker threads`,
`fix(player): clamp slope alignment`, `test(needs): cover thirst decay`.
