# ADR-011: Original music, licensed apart

- **Status:** Accepted
- **Date:** 2026-11-11

## Context
Phase 20 brings music. The user composes it in SuperCollider, in a private project outside
this repository (`~/code/music/supper-collider/trailpaw/`). There, each biome's theme is a data
description rendered offline in four moments of the day (day, dawn, dusk, night) and mastered
to −19 LUFS (night −22.5) as OGG.

The repository is public, the code is MIT, and every third-party asset so far is CC0. The music
is the user's own work, and they want to keep all rights to it.

The user chose (2026-11-11):
- the OGGs **in the repository**, with their own licence
- the user composes the themes; the game integrates them
- the title screen plays the meadow theme
- no music in the rain

## Decision
- **Licence:** the mastered OGGs live in `assets/audio/music/` (Git LFS, like every OGG) with
  `LICENSE.md`: © the author, all rights reserved, playable as part of Trailpaw only.
  `assets/CREDITS.md` points to it. The SuperCollider sources stay out of the repository.
- **Integration:** a `MusicDirector`, driven by data (`MusicSettings`, `MusicTheme`), plays in
  **spells**: a whole theme, then minutes of silence, as cosy games do.
  - It picks the theme by biome and moment, and fades on a change.
  - It is silent in the rain, while resting, and in biomes without a theme.
  - A setting chooses how often: often, sometimes or never.
  - Details are in ARCHITECTURE (Audio).
- **Growth:** a new theme is its OGGs and one `MusicTheme` line, with no code change.

## Consequences
- The music can be heard and downloaded from the public repository, but it is not licensed
  for reuse. Anyone forking the project must replace it or ask.
- The repository grows by ≈ 16 MB per biome (four moments), through LFS.
- Biomes without a theme are silent musically until theirs arrives. That is deliberate: no
  placeholder music.
