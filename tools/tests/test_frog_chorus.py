"""Tests for tools.frog_chorus."""

from __future__ import annotations

import math
import random
import wave
from pathlib import Path

import pytest

from tools.ambience_loop import write_mono16
from tools.frog_chorus import chorus, low_pass, main, pitched


def _croak(length: int = 400) -> list[float]:
    return [math.sin(i * 0.3) * math.sin(math.pi * i / length) for i in range(length)]


def test_pitched_up_is_shorter_and_one_is_unchanged() -> None:
    """Speeding up shortens a call; factor 1 is the identity."""
    croak = _croak()
    assert len(pitched(croak, 2.0)) == 200
    assert pitched(croak, 1.0) == pytest.approx(croak)
    with pytest.raises(ValueError):
        pitched(croak, 0.0)


def test_low_pass_keeps_steady_signals_and_damps_fast_ones() -> None:
    """The filter passes DC and damps the highest frequency."""
    assert low_pass([1.0] * 200, 0.8)[-1] == pytest.approx(1.0, abs=1e-6)
    alternating = [(-1.0) ** i for i in range(200)]
    assert max(abs(s) for s in low_pass(alternating, 0.8)[100:]) < 0.2


def test_chorus_is_deterministic_and_wraps_into_the_beginning() -> None:
    """Same seed, same loop; calls past the end wrap to the start."""
    croaks = [_croak(), _croak(300)]
    first = chorus(croaks, 2000, 12, 1000, random.Random(3))
    assert first == chorus(croaks, 2000, 12, 1000, random.Random(3))
    assert len(first) == 2000
    assert first != chorus(croaks, 2000, 12, 1000, random.Random(4))
    # With many calls in a short loop some must wrap round and sound at the very start.
    assert any(abs(s) > 1e-3 for s in first[:50])


def test_chorus_needs_croaks() -> None:
    """Without croaks there is nothing to mix."""
    with pytest.raises(ValueError):
        chorus([], 100, 1, 1000, random.Random(1))


def test_main_writes_a_loop_of_the_requested_length(tmp_path: Path) -> None:
    """The CLI writes a mono loop of exactly the requested length."""
    croak = tmp_path / "croak.wav"
    write_mono16(croak, _croak(800), 8000)
    out = tmp_path / "chorus.wav"
    assert main([str(out), str(croak), "--seconds", "3", "--rate", "8000"]) == 0
    with wave.open(str(out), "rb") as result:
        assert result.getnframes() == 24000
        assert result.getframerate() == 8000
        assert result.getnchannels() == 1
