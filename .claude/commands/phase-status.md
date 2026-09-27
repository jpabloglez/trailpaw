---
description: Summarise ROADMAP.md progress and the next task of the active phase
allowed-tools: Read, Bash(git log:*), Bash(git status:*)
---

Read `ROADMAP.md`, then report:

1. **Active phase:** the lowest-numbered phase that still has unticked `- [ ]` items.
   Show its title and its exit criteria.
2. **Progress table:** one row per phase with ticked/total checkboxes, a percentage and
   a status (✅ done, 🚧 active, ⏳ not started). Treat items marked "Optional" as done
   when ticked, but leave them out of the totals when they aren't.
3. **Remaining in the active phase:** the unticked items, verbatim.
4. **Next task:** the first unticked item of the active phase, plus a one-line
   suggestion of which files it will touch, based on `docs/ARCHITECTURE.md`.
5. **Recent activity:** `git log --oneline -5`, and whether the working tree is clean.

This command is read-only. Do not change any files. Keep the report under about 40
lines.
$ARGUMENTS
