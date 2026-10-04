# Playtests

Phase 12 exit: **a stranger can download, play 30 minutes and want to keep going.** A playtest
checks exactly that, with 3–5 people who have never seen the game.

## Before the session

- Use a **release build** (the [Releases](https://github.com/jpabloglez/trailpaw/releases) page,
  or the `trailpaw-windows` / `trailpaw-linux` artifact of the latest `main` run). Write its
  version, shown at the bottom right of the main menu (e.g. `v0.12.0`), in the notes.
- Start from a clean state, so the onboarding hints show: delete
  `%APPDATA%\Godot\app_userdata\Trailpaw\` (Windows) or `~/.local/share/godot/app_userdata/Trailpaw/`
  (Linux), or use *Settings → Interface → Teach me again* and a *New game*.
- Have sound on: the ambience and footsteps are part of the experience.

## During the session (≈ 35 minutes)

1. **Say only this:** "It's a calm exploration game where you are a fox. Play as you like for
   half an hour; think aloud if you can. I won't help unless you're completely stuck."
2. **First 5 minutes — don't help.** Note what they try, where they hesitate, whether the hints
   appear and are understood (move, run, sniff, follow the sparkles, eat, map, rest).
3. **Minutes 5–30 — observe.** Note moments of delight, confusion and boredom, with the time.
   If they are stuck for more than 2 minutes, give the smallest possible nudge and note it.
4. **At 30 minutes**, ask: "Would you like to keep playing?" and let them, if they want to:
   *wanting to continue* is the result that matters.

## After the session

Copy [`TEMPLATE.md`](TEMPLATE.md) to `YYYY-MM-DD-<initials>.md` in this folder and fill it in
within the hour. Don't record names or anything personal beyond initials. Collect the findings
of all sessions in a short summary (`YYYY-MM-summary.md`) with what to change, most important
first.
