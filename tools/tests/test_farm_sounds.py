"""Tests for tools.farm_sounds."""

from __future__ import annotations

import random
import wave
from pathlib import Path

from tools.farm_sounds import claps, cluck, grunt, main, moo, rooster

RATE = 8000


def _peak(samples: list[float]) -> float:
    return max(abs(s) for s in samples)


def test_each_sound_has_its_length_and_is_not_silent() -> None:
    """Every sound lasts about as designed and has something in it."""
    rng = random.Random(1)
    assert 0.05 < len(cluck(rng, RATE)) / RATE < 0.6
    assert 1.1 < len(rooster(RATE, rng)) / RATE < 1.5
    assert abs(len(moo(RATE)) / RATE - 1.4) < 0.01
    assert 0.4 < len(grunt(RATE, rng)) / RATE < 0.9
    assert 0.4 < len(claps(RATE, rng)) / RATE < 0.6
    for samples in (cluck(rng, RATE), rooster(RATE, rng), moo(RATE), grunt(RATE, rng)):
        assert _peak(samples) > 0.05


def test_the_rooster_ends_on_a_long_falling_note() -> None:
    """The last syllable takes most of the crow."""
    samples = rooster(RATE, random.Random(2))
    tail = samples[int(len(samples) * 0.45) :]
    assert _peak(tail) > 0.5 * _peak(samples)


def test_claps_are_two_sharp_bursts() -> None:
    """Two loud moments, quiet in between."""
    samples = claps(RATE, random.Random(3))
    window = RATE // 50
    loud = [_peak(samples[i : i + window]) for i in range(0, len(samples) - window, window)]
    top = max(loud)
    onsets = sum(
        1 for a, b in zip(loud, loud[1:], strict=False) if a < top * 0.2 and b >= top * 0.5
    )
    assert onsets + (1 if loud[0] >= top * 0.5 else 0) == 2


def test_sounds_are_deterministic() -> None:
    """The same seed gives the same sound."""
    assert rooster(RATE, random.Random(5)) == rooster(RATE, random.Random(5))
    assert cluck(random.Random(5), RATE) == cluck(random.Random(5), RATE)


def test_main_writes_every_file(tmp_path: Path) -> None:
    """The CLI writes the five mono files, the hens' loop exactly 20 s long."""
    assert main([str(tmp_path), "--rate", str(RATE)]) == 0
    for name in ("hens_loop.wav", "rooster.wav", "moo.wav", "grunt.wav", "claps.wav"):
        with wave.open(str(tmp_path / name), "rb") as sound:
            assert sound.getnchannels() == 1
            assert sound.getframerate() == RATE
    with wave.open(str(tmp_path / "hens_loop.wav"), "rb") as loop:
        assert loop.getnframes() == 20 * RATE
