# Audio licences

Every sound under `assets/audio/` is **CC0 1.0 Universal** (public domain dedication),
https://creativecommons.org/publicdomain/zero/1.0/ — each file, its author and source page are
listed in `assets/CREDITS.md`.

- Ambience: OpenGameArt.org uploads marked CC0 by their authors (Thimras, isaiah658, Wolfgang_,
  Kresiek The Furry). The *Park ambiences* recordings (48 kHz stereo, 4–9 minutes) were cut to
  40-second mono loops at 22 050 Hz with `python -m tools.ambience_loop` to keep the repository
  small.
- Footsteps: Kenney *Impact Sounds* (grass and concrete steps; licence text in
  `footsteps/Kenney_License.txt`) and rubberduck's *40 CC0 water / splash / slime SFX* for wading.
- Animals: StarNinjas' *Donkey Bray* (OpenGameArt, CC0). Frogs: EZduzziteh's *Ribbit Frog Sounds*
  (OpenGameArt, CC0), three croaks trimmed and normalised (the originals peak at 1–4 % of full
  scale). Their pulsed structure (17–27 pulses per call, 420–590 Hz) is that of real frog calls,
  not a voice imitation. The night chorus (`ambience/frog_chorus.wav`) is built from these single croaks by
  `tools/frog_chorus.py`. The Shiba Inu's "yip" is synthesised in
  code (`SynthSounds.yip()`); deer, stags, horses and alpacas are quiet (no CC0 calls found that
  fit, and they rarely vocalise). A CC0 dog "montage" was discarded: it could not be auditioned
  to rule out human voices.
- Interface: Kenney *Interface Sounds* (`ui/Kenney_License.txt`).

