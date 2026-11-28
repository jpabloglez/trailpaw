"""Synthesise the fox's need cues (ADR-012): panting and a hungry tummy rumble.

Usage::

    python -m tools.need_cue_sounds OUTPUT_DIR [--seed S] [--rate HZ]

Writes, as 16-bit mono PCM WAV:

- ``pant_loop.wav``: a 2 s seamless loop of quick, breathy pants (in and out, ~3 per second;
  band-limited noise under short envelopes, the "in" softer and higher than the "out");
- ``growl.wav``: a soft, low tummy rumble (~1.2 s of gurgling noise wobbling in pitch).

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
from tools.frog_chorus import low_pass

#: Pants per second in the loop.
PANTS_PER_SECOND = 3
#: Length of the pant loop (s); a whole number of pants so it loops seamlessly.
PANT_LOOP_SECONDS = 2.0


def _breath(rng: random.Random, n: int, smooth: float, gain: float) -> list[float]:
    """Make one breath: noise, low-passed then high-passed, under a soft hump.

    Parameters
    ----------
    rng : random.Random
        Noise source.
    n : int
        Samples.
    smooth : float
        Low-pass amount in [0, 1) (higher = darker).
    gain : float
        Peak amplitude.

    Returns
    -------
    list[float]
        The samples.
    """
    noise = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    dark = low_pass(noise, smooth)
    bright = [s - d for s, d in zip(noise, low_pass(noise, 0.97), strict=True)]
    mixed = [0.7 * d + 0.3 * b for d, b in zip(dark, bright, strict=True)]
    return [s * gain * math.sin(math.pi * i / n) ** 1.5 for i, s in enumerate(mixed)]


def pant_loop(rng: random.Random, rate: int) -> list[float]:
    """Make the seamless panting loop.

    Parameters
    ----------
    rng : random.Random
        Noise and timing jitter.
    rate : int
        Sample rate (Hz).

    Returns
    -------
    list[float]
        ``PANT_LOOP_SECONDS`` of samples; every breath ends before the loop does.
    """
    total = int(PANT_LOOP_SECONDS * rate)
    out = [0.0] * total
    period = rate // PANTS_PER_SECOND
    for start in range(0, total - period + 1, period):
        jitter = rng.randint(0, period // 20)
        out_len = int(period * 0.42)
        in_len = int(period * 0.3)
        exhale = _breath(rng, out_len, 0.55, rng.uniform(0.85, 1.0))
        inhale = _breath(rng, in_len, 0.35, rng.uniform(0.45, 0.55))
        at = start + jitter
        for i, s in enumerate(exhale):
            out[at + i] += s
        at += out_len + period // 12
        for i, s in enumerate(inhale):
            if at + i < total:
                out[at + i] += s
    return out


def growl(rng: random.Random, rate: int) -> list[float]:
    """Make the hungry tummy rumble: a wobbling low tone with gurgles.

    Parameters
    ----------
    rng : random.Random
        Noise and wobble.
    rate : int
        Sample rate (Hz).

    Returns
    -------
    list[float]
        About 1.2 s of samples.
    """
    n = int(1.2 * rate)
    phase = 0.0
    wobble_rate = rng.uniform(5.0, 7.0)
    rumble = low_pass([rng.uniform(-1.0, 1.0) for _ in range(n)], 0.995)
    out: list[float] = []
    for i in range(n):
        t = i / rate
        freq = (
            70.0
            + 25.0 * math.sin(2.0 * math.pi * 0.9 * t)
            + 8.0 * math.sin(2.0 * math.pi * wobble_rate * t)
        )
        phase += 2.0 * math.pi * freq / rate
        tone = math.sin(phase) + 0.4 * math.sin(2.0 * phase) + 0.15 * math.sin(3.0 * phase)
        gurgle = 0.5 + 0.5 * math.sin(2.0 * math.pi * wobble_rate * 1.7 * t) ** 2
        envelope = math.sin(math.pi * i / n) ** 0.8
        out.append((tone * gurgle + 40.0 * rumble[i]) * envelope)
    return low_pass(out, 0.6)


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
    parser.add_argument("--seed", type=int, default=12)
    parser.add_argument("--rate", type=int, default=22050)
    args = parser.parse_args(argv)
    rng = random.Random(args.seed)
    rate = args.rate
    args.output.mkdir(parents=True, exist_ok=True)
    sounds = {"pant_loop.wav": pant_loop(rng, rate), "growl.wav": growl(rng, rate)}
    for name, samples in sounds.items():
        write_mono16(args.output / name, normalise(samples, 0.6), rate)
        print(f"{args.output / name}: {len(samples) / rate:.2f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
