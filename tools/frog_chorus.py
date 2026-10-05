"""Build a seamless frog-chorus loop out of a few single croaks.

Usage::

    python -m tools.frog_chorus OUTPUT.wav CROAK.wav [CROAK.wav ...] [--seconds N]
        [--calls-per-second R] [--seed S] [--rate HZ] [--peak P]

Scatters ``seconds * calls_per_second`` croaks over the loop at random times, each one picked
from the inputs at random, pitched by 0.85-1.2x (frogs of different sizes), and placed at a
random distance: farther calls are quieter and duller (a one-pole low-pass). A call that runs
past the end wraps round to the beginning, so the loop has no seam. Calls come in bouts (a
frog calls two to four times in a row), as real choruses do. Deterministic for a given seed.
Standard library only.
"""

from __future__ import annotations

import argparse
import random
import sys
from collections.abc import Sequence
from pathlib import Path

from tools.ambience_loop import normalise, read_mono, resample, write_mono16


def pitched(samples: Sequence[float], factor: float) -> list[float]:
    """Play ``samples`` ``factor`` times faster (higher and shorter), linearly interpolated.

    Parameters
    ----------
    samples : Sequence[float]
        Input samples.
    factor : float
        Speed factor (> 0); 1 leaves the input unchanged.

    Returns
    -------
    list[float]
        ``len(samples) / factor`` samples.
    """
    if factor <= 0.0:
        raise ValueError("factor must be > 0")
    length = int(len(samples) / factor)
    out: list[float] = []
    for i in range(length):
        position = i * factor
        j = int(position)
        frac = position - j
        nxt = samples[j + 1] if j + 1 < len(samples) else 0.0
        out.append(samples[j] * (1.0 - frac) + nxt * frac)
    return out


def low_pass(samples: Sequence[float], amount: float) -> list[float]:
    """One-pole low-pass: ``amount`` 0 leaves the input as is, near 1 muffles it strongly.

    Parameters
    ----------
    samples : Sequence[float]
        Input samples.
    amount : float
        Smoothing in [0, 1).

    Returns
    -------
    list[float]
        Filtered samples.
    """
    out: list[float] = []
    state = 0.0
    for s in samples:
        state = state * amount + s * (1.0 - amount)
        out.append(state)
    return out


def chorus(
    croaks: Sequence[Sequence[float]],
    length: int,
    calls: int,
    rate: int,
    rng: random.Random,
) -> list[float]:
    """Mix ``calls`` croaks into a loop of ``length`` samples (wrapping at the end).

    Parameters
    ----------
    croaks : Sequence[Sequence[float]]
        Single calls to pick from (at ``rate``).
    length : int
        Loop length in samples.
    calls : int
        How many croaks to place (in bouts of 2-4).
    rate : int
        Sample rate (Hz), for the gaps within a bout.
    rng : random.Random
        Source of every random choice.

    Returns
    -------
    list[float]
        The loop (not normalised).
    """
    if not croaks:
        raise ValueError("at least one croak is needed")
    loop = [0.0] * length
    placed = 0
    while placed < calls:
        croak = croaks[rng.randrange(len(croaks))]
        distance = rng.random()  # 0 near ... 1 far
        voice = low_pass(pitched(croak, rng.uniform(0.85, 1.2)), 0.2 + 0.65 * distance)
        gain = 1.0 - 0.8 * distance
        start = rng.randrange(length)
        for _ in range(min(rng.randint(2, 4), calls - placed)):
            for i, s in enumerate(voice):
                loop[(start + i) % length] += s * gain
            start += len(voice) + int(rng.uniform(0.15, 0.6) * rate)
            placed += 1
    return loop


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
    parser.add_argument("croaks", type=Path, nargs="+")
    parser.add_argument("--seconds", type=float, default=20.0)
    parser.add_argument("--calls-per-second", type=float, default=2.5)
    parser.add_argument("--seed", type=int, default=14)
    parser.add_argument("--rate", type=int, default=22050)
    parser.add_argument("--peak", type=float, default=0.7)
    args = parser.parse_args(argv)
    croaks: list[list[float]] = []
    for path in args.croaks:
        samples, rate = read_mono(path, 0.0, 60.0)
        croaks.append(resample(samples, rate, args.rate))
    length = int(args.seconds * args.rate)
    calls = int(args.seconds * args.calls_per_second)
    loop = chorus(croaks, length, calls, args.rate, random.Random(args.seed))
    write_mono16(args.output, normalise(loop, args.peak), args.rate)
    print(f"{args.output}: {args.seconds:.1f} s, {calls} calls, mono @ {args.rate} Hz")
    return 0


if __name__ == "__main__":
    sys.exit(main())
