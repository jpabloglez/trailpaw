"""Tests for tools.need_cue_sounds."""

from __future__ import annotations

import random
import wave
from pathlib import Path

from tools.need_cue_sounds import PANT_LOOP_SECONDS, PANTS_PER_SECOND, growl, main, pant_loop

RATE = 8000


def _peak(samples: list[float]) -> float:
    return max(abs(s) for s in samples)


def test_the_pant_loop_has_its_length_and_seamless_ends() -> None:
    """The loop lasts as designed and starts and ends almost silent (no click when looping)."""
    samples = pant_loop(random.Random(1), RATE)
    assert len(samples) == int(PANT_LOOP_SECONDS * RATE)
    assert _peak(samples) > 0.1
    edge = RATE // 200
    assert _peak(samples[:edge]) < 0.1 * _peak(samples)
    assert _peak(samples[-edge:]) < 0.1 * _peak(samples)


def test_pants_come_in_regular_bursts() -> None:
    """Each pant period holds a loud exhale; the loop has one per period."""
    samples = pant_loop(random.Random(2), RATE)
    period = RATE // PANTS_PER_SECOND
    loud = 0
    for start in range(0, len(samples) - period + 1, period):
        if _peak(samples[start : start + period]) > 0.3 * _peak(samples):
            loud += 1
    assert loud == int(PANT_LOOP_SECONDS * PANTS_PER_SECOND)


def test_the_growl_is_low_soft_edged_and_not_silent() -> None:
    """About 1.2 s, fades in and out, and mostly low frequencies (few zero crossings)."""
    samples = growl(random.Random(3), RATE)
    assert abs(len(samples) / RATE - 1.2) < 0.01
    assert _peak(samples) > 0.05
    assert _peak(samples[: RATE // 100]) < 0.2 * _peak(samples)
    crossings = sum(1 for a, b in zip(samples, samples[1:], strict=False) if a * b < 0.0)
    assert crossings / (len(samples) / RATE) < 400  # well under 200 Hz on average


def test_main_writes_both_wavs(tmp_path: Path) -> None:
    """The command writes playable mono 16-bit files."""
    assert main([str(tmp_path), "--rate", str(RATE)]) == 0
    for name in ("pant_loop.wav", "growl.wav"):
        with wave.open(str(tmp_path / name), "rb") as wav:
            assert wav.getnchannels() == 1
            assert wav.getsampwidth() == 2
            assert wav.getframerate() == RATE
            assert wav.getnframes() > RATE // 2


def test_the_same_seed_gives_the_same_sounds() -> None:
    """Deterministic for a seed."""
    assert pant_loop(random.Random(5), RATE) == pant_loop(random.Random(5), RATE)
    assert growl(random.Random(5), RATE) == growl(random.Random(5), RATE)
