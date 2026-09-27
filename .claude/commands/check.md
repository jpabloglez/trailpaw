---
description: Run the full local quality gate (lint, format, import, tests) and report pass/fail
allowed-tools: Bash(.venv/bin/*), Bash(godot:*), Bash(./addons/gdUnit4/runtest.sh:*), Bash(readlink:*), Bash(command -v:*)
---

Run the project's Definition-of-Done checks (CLAUDE.md §2) from the repository root and
report the results. Do not modify any files, and do not try to fix failures unless the
user asks.

Run each command below, even if an earlier one fails. Use the project venv (`.venv/bin/`).
If `.venv` is missing, say so and give the setup command from README.md instead of
running the checks.

1. `.venv/bin/gdlint scripts/ tests/`
2. `.venv/bin/gdformat --check scripts/ tests/`
3. `.venv/bin/ruff check tools/`
4. `.venv/bin/ruff format --check tools/`
5. `.venv/bin/python -m pytest tools/tests -q`
6. `.venv/bin/python -m tools.godot_version`
7. `godot --headless --path . --import`: this fails if any output line starts with
   `ERROR:`, `SCRIPT ERROR:` or `USER ERROR:`
8. `GODOT_BIN=$(readlink -f "$(command -v godot)") ./addons/gdUnit4/runtest.sh --headless --ignoreHeadlessMode -a res://tests`
   (exit 0 = pass, 100 = failures, 101 = warnings)

Finish with a table showing each check with ✅/❌ and a one-line detail (e.g. test
counts). Under the table, quote the relevant error output for every failed check.
$ARGUMENTS
