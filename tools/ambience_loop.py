"""Cut a long field recording into a small, seamless ambience loop.

Usage::

    python -m tools.ambience_loop INPUT.wav OUTPUT.wav [--start S] [--seconds N]
        [--rate HZ] [--fade S] [--peak P]

Reads 16- or 24-bit PCM WAV (any channel count), takes ``seconds`` + ``fade`` from ``start``,
mixes it to mono, resamples it linearly to ``rate`` and folds the last ``fade`` seconds into
the beginning with an equal-power crossfade, so the loop has no click at its seam. The
result is normalised to ``peak`` and written as 16-bit mono PCM. Standard library only.
"""

from __future__ import annotations

import argparse
import math
import struct
import sys
import wave
from collections.abc import Sequence
from pathlib import Path


def read_mono(path: Path, start: float, seconds: float) -> tuple[list[float], int]:
    """Read a span of a PCM WAV file as mono samples in [-1, 1].

    Parameters
    ----------
    path : Path
        WAV file (16- or 24-bit PCM).
    start : float
        Start of the span (s).
    seconds : float
        Length of the span (s); clipped to the end of the file.

    Returns
    -------
    tuple[list[float], int]
        The samples and the file's sample rate.
    """
    with wave.open(str(path), "rb") as source:
        channels = source.getnchannels()
        width = source.getsampwidth()
        rate = source.getframerate()
        if width not in (2, 3):
            raise ValueError(f"{path}: only 16- and 24-bit PCM are supported, got {width * 8}")
        source.setpos(min(int(start * rate), source.getnframes()))
        raw = source.readframes(int(seconds * rate))
    frame = channels * width
    scale = float(1 << (width * 8 - 1))
    samples: list[float] = []
    for offset in range(0, len(raw) - frame + 1, frame):
        total = 0
        for c in range(channels):
            at = offset + c * width
            if width == 2:
                total += struct.unpack_from("<h", raw, at)[0]
            else:
                value = raw[at] | (raw[at + 1] << 8) | (raw[at + 2] << 16)
                total += value - (1 << 24) if value & 0x800000 else value
        samples.append(total / channels / scale)
    return samples, rate


def resample(samples: Sequence[float], source_rate: int, target_rate: int) -> list[float]:
    """Resample by linear interpolation.

    Parameters
    ----------
    samples : Sequence[float]
        Input samples.
    source_rate : int
        Input sample rate (Hz).
    target_rate : int
        Output sample rate (Hz).

    Returns
    -------
    list[float]
        Resampled samples (``len(samples) * target_rate / source_rate`` of them).
    """
    if source_rate == target_rate or len(samples) < 2:
        return list(samples)
    count = int(len(samples) * target_rate / source_rate)
    step = source_rate / target_rate
    out: list[float] = []
    for i in range(count):
        x = i * step
        j = min(int(x), len(samples) - 2)
        t = x - j
        out.append(samples[j] * (1.0 - t) + samples[j + 1] * t)
    return out


def make_loop(samples: Sequence[float], fade: int) -> list[float]:
    """Fold the last ``fade`` samples into the first ones with an equal-power crossfade.

    Parameters
    ----------
    samples : Sequence[float]
        Input of ``length + fade`` samples.
    fade : int
        Crossfade length in samples (> 0, < half the input).

    Returns
    -------
    list[float]
        ``len(samples) - fade`` samples whose end flows into their beginning.
    """
    if fade <= 0 or fade * 2 >= len(samples):
        raise ValueError("fade must be > 0 and shorter than half the input")
    length = len(samples) - fade
    loop = list(samples[:length])
    for i in range(fade):
        t = (i + 0.5) / fade
        fade_in = math.sin(t * math.pi / 2.0)
        fade_out = math.cos(t * math.pi / 2.0)
        loop[i] = samples[i] * fade_in + samples[length + i] * fade_out
    return loop


def normalise(samples: Sequence[float], peak: float) -> list[float]:
    """Scale so the loudest sample reaches ``peak``.

    Parameters
    ----------
    samples : Sequence[float]
        Input samples.
    peak : float
        Target peak in (0, 1].

    Returns
    -------
    list[float]
        Scaled samples (unchanged when silent).
    """
    loudest = max((abs(s) for s in samples), default=0.0)
    if loudest <= 0.0:
        return list(samples)
    gain = peak / loudest
    return [s * gain for s in samples]


def write_mono16(path: Path, samples: Sequence[float], rate: int) -> None:
    """Write samples as 16-bit mono PCM WAV.

    Parameters
    ----------
    path : Path
        Output file.
    samples : Sequence[float]
        Samples in [-1, 1] (clipped).
    rate : int
        Sample rate (Hz).
    """
    data = bytearray()
    for s in samples:
        data += struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767))
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(bytes(data))


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
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--start", type=float, default=0.0)
    parser.add_argument("--seconds", type=float, default=45.0)
    parser.add_argument("--rate", type=int, default=22050)
    parser.add_argument("--fade", type=float, default=2.0)
    parser.add_argument("--peak", type=float, default=0.7)
    args = parser.parse_args(argv)
    samples, rate = read_mono(args.input, args.start, args.seconds + args.fade)
    samples = resample(samples, rate, args.rate)
    loop = make_loop(samples, int(args.fade * args.rate))
    write_mono16(args.output, normalise(loop, args.peak), args.rate)
    print(f"{args.output}: {len(loop) / args.rate:.1f} s mono @ {args.rate} Hz")
    return 0


if __name__ == "__main__":
    sys.exit(main())
