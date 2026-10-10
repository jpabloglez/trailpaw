"""Synthesise the hamlets' sounds that no CC0 recording covered (Phase 16).

Usage::

    python -m tools.farm_sounds OUTPUT_DIR [--seed S] [--rate HZ]

Writes, as 16-bit mono PCM WAV:

- ``hens_loop.wav``: a 20 s seamless loop of hens clucking about a yard (single clucks are
  short pitch-dropping "bok" pulses, mixed in bouts by ``tools.frog_chorus.chorus``);
- ``rooster.wav``: a stylised "cock-a-doodle-doo" (four gliding, raspy syllables);
- ``moo.wav``: a low, slowly opening "mooo" (a sawtooth-rich voice under a sweeping filter);
- ``grunt.wav``: a pig's three short, low grunts;
- ``claps.wav``: two sharp hand claps (a villager shooing the fox).

Deterministic for a given seed. Standard library only.
"""

from __future__ import annotations

import argparse
import math
import random
import sys
from collections.abc import Sequence
from pathlib import Path

from tools.ambience_loop import normalise, write_mono16
from tools.frog_chorus import chorus, low_pass


def _voice(freqs: Sequence[float], rate: int, harmonics: int = 6) -> list[float]:
    """Make a buzzy voice following the per-sample frequencies ``freqs`` (Hz).

    Parameters
    ----------
    freqs : Sequence[float]
        Frequency of every sample.
    rate : int
        Sample rate (Hz).
    harmonics : int
        Harmonics added (amplitude 1/k), for a sawtooth-like tone.

    Returns
    -------
    list[float]
        The samples (roughly in [-2, 2]).
    """
    out: list[float] = []
    phase = 0.0
    for f in freqs:
        phase += 2.0 * math.pi * f / rate
        out.append(sum(math.sin(phase * k) / k for k in range(1, harmonics + 1)))
    return out


def _envelope(n: int, attack: float, release: float) -> list[float]:
    """Make an envelope: linear attack, hold, linear release over ``n`` samples (fractions)."""
    a = max(1, int(n * attack))
    r = max(1, int(n * release))
    return [min(1.0, i / a, (n - i) / r) for i in range(n)]


def cluck(rng: random.Random, rate: int) -> list[float]:
    """Make one hen's cluck: 1-3 quick "bok" pulses, each dropping in pitch.

    Parameters
    ----------
    rng : random.Random
        Source of the variation.
    rate : int
        Sample rate (Hz).

    Returns
    -------
    list[float]
        The cluck (not normalised).
    """
    out: list[float] = []
    for _ in range(rng.randint(1, 3)):
        n = int(rate * rng.uniform(0.05, 0.08))
        top = rng.uniform(650.0, 900.0)
        freqs = [top * (1.0 - 0.45 * i / n) for i in range(n)]
        env = [math.exp(-6.0 * i / n) * min(1.0, i / (0.004 * rate)) for i in range(n)]
        tone = _voice(freqs, rate, 4)
        noise = [rng.uniform(-0.3, 0.3) for _ in range(n)]
        out += [(t + z) * e * 0.5 for t, z, e in zip(tone, noise, env, strict=True)]
        out += [0.0] * int(rate * rng.uniform(0.05, 0.11))
    return low_pass(out, 0.35)


def rooster(rate: int, rng: random.Random) -> list[float]:
    """Make a stylised rooster's crow: syllables gliding up, then a long falling "doo"."""
    syllables = [
        (0.14, 520.0, 760.0),
        (0.1, 760.0, 700.0),
        (0.18, 820.0, 980.0),
        (0.75, 980.0, 620.0),
    ]
    out: list[float] = []
    for seconds, start, end in syllables:
        n = int(rate * seconds)
        freqs = [
            (start + (end - start) * i / n) * (1.0 + 0.02 * math.sin(i / rate * 2 * math.pi * 7.0))
            for i in range(n)
        ]
        tone = _voice(freqs, rate, 8)
        env = _envelope(n, 0.1, 0.35)
        rasp = [rng.uniform(-0.35, 0.35) for _ in range(n)]
        out += [(t * 0.6 + z * abs(t)) * e for t, z, e in zip(tone, rasp, env, strict=True)]
        out += [0.0] * int(rate * 0.025)
    return low_pass(out, 0.25)


def moo(rate: int) -> list[float]:
    """Make a cow's moo: a low voice whose filter opens and closes ("mmm-ooo-uh"), 1.4 s."""
    n = int(rate * 1.4)
    freqs = [110.0 + 30.0 * math.sin(math.pi * i / n) - 15.0 * i / n for i in range(n)]
    tone = _voice(freqs, rate, 12)
    env = _envelope(n, 0.15, 0.3)
    out: list[float] = []
    state = 0.0
    for i, (t, e) in enumerate(zip(tone, env, strict=True)):
        opening = math.sin(math.pi * i / n)  # the mouth opens, then closes
        amount = 0.97 - 0.12 * opening
        state = state * amount + t * (1.0 - amount)
        out.append(state * e)
    return out


def grunt(rate: int, rng: random.Random) -> list[float]:
    """Make a pig's three short, low, noisy grunts."""
    out: list[float] = []
    for _ in range(3):
        n = int(rate * rng.uniform(0.09, 0.14))
        base = rng.uniform(85.0, 110.0)
        tone = _voice([base * (1.0 - 0.2 * i / n) for i in range(n)], rate, 10)
        env = _envelope(n, 0.15, 0.6)
        noise = [rng.uniform(-0.8, 0.8) for _ in range(n)]
        out += low_pass([(t * 0.7 + z) * e for t, z, e in zip(tone, noise, env, strict=True)], 0.6)
        out += [0.0] * int(rate * rng.uniform(0.06, 0.12))
    return out


def claps(rate: int, rng: random.Random) -> list[float]:
    """Make two sharp hand claps, a quarter of a second apart."""
    out: list[float] = []
    for _ in range(2):
        n = int(rate * 0.09)
        burst = [rng.uniform(-1.0, 1.0) * math.exp(-60.0 * i / rate) for i in range(n)]
        smooth = low_pass(burst, 0.45)
        out += [
            b - s for b, s in zip(burst, smooth, strict=True)
        ]  # keep the crack, lose the rumble
        out += [0.0] * int(rate * 0.16)
    return out


def main(argv: Sequence[str] | None = None) -> int:
    """Command-line entry point.

    Parameters
    ----------
    argv : Sequence[str] or None
        Arguments (defaults to ``sys.argv[1:]``).

    Returns
    -------
    int
        Exit code (0 on success).
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("output", type=Path)
    parser.add_argument("--seed", type=int, default=16)
    parser.add_argument("--rate", type=int, default=22050)
    args = parser.parse_args(argv)
    rng = random.Random(args.seed)
    rate = args.rate
    args.output.mkdir(parents=True, exist_ok=True)
    clucks = [cluck(rng, rate) for _ in range(6)]
    loop = chorus(clucks, 20 * rate, 34, rate, rng)
    sounds = {
        "hens_loop.wav": loop,
        "rooster.wav": rooster(rate, rng),
        "moo.wav": moo(rate),
        "grunt.wav": grunt(rate, rng),
        "claps.wav": claps(rate, rng),
    }
    for name, samples in sounds.items():
        write_mono16(args.output / name, normalise(samples, 0.7), rate)
        print(f"{args.output / name}: {len(samples) / rate:.2f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
