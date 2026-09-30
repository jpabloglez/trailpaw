"""Tests for tools.ambience_loop."""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

import pytest

from tools import ambience_loop


def _write_stereo(path: Path, rate: int, seconds: float, width: int = 2) -> None:
    frames = bytearray()
    for i in range(int(rate * seconds)):
        value = math.sin(2.0 * math.pi * 220.0 * i / rate) * 0.5
        for channel in range(2):
            sample = int(value * (1 << (width * 8 - 1)) * (1.0 if channel == 0 else 0.5))
            frames += struct.pack("<i", sample)[:width]
    with wave.open(str(path), "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(width)
        out.setframerate(rate)
        out.writeframes(bytes(frames))


@pytest.mark.parametrize("width", [2, 3])
def test_reads_16_and_24_bit_stereo_as_mono(tmp_path: Path, width: int) -> None:
    """16- and 24-bit stereo files are read and averaged to mono."""
    source = tmp_path / "in.wav"
    _write_stereo(source, 8000, 1.0, width)
    samples, rate = ambience_loop.read_mono(source, 0.0, 0.5)
    assert rate == 8000
    assert len(samples) == 4000
    assert max(abs(s) for s in samples) == pytest.approx(0.375, abs=0.01)  # (0.5 + 0.25) / 2


def test_resample_changes_the_length_by_the_rate_ratio() -> None:
    """Linear resampling scales the length by the rate ratio and keeps the signal."""
    samples = [math.sin(i * 0.01) for i in range(48000)]
    out = ambience_loop.resample(samples, 48000, 22050)
    assert len(out) == 22050
    assert out[1000] == pytest.approx(samples[int(1000 * 48000 / 22050)], abs=0.01)


def test_the_loop_is_seamless_and_shorter_by_the_fade() -> None:
    """The crossfade removes the fade length and joins the end to the start."""
    samples = [math.sin(i * 0.05) + (i / 2000.0) for i in range(2000)]  # drifts: no natural loop
    loop = ambience_loop.make_loop(samples, 200)
    assert len(loop) == 1800
    # Across the seam (end → start) the signal continues from where the source went on.
    assert loop[0] == pytest.approx(samples[1800], abs=0.05)
    assert abs(loop[-1] - loop[0]) < 0.1


def test_make_loop_rejects_bad_fades() -> None:
    """A zero fade or one longer than half the input is rejected."""
    with pytest.raises(ValueError):
        ambience_loop.make_loop([0.0] * 10, 0)
    with pytest.raises(ValueError):
        ambience_loop.make_loop([0.0] * 10, 6)


def test_normalise_reaches_the_peak_and_keeps_silence() -> None:
    """Normalising scales the peak and leaves silence alone."""
    scaled = ambience_loop.normalise([0.1, -0.2, 0.05], 0.7)
    assert max(abs(s) for s in scaled) == pytest.approx(0.7)
    assert ambience_loop.normalise([0.0, 0.0], 0.7) == [0.0, 0.0]


def test_command_line_writes_a_small_mono_loop(tmp_path: Path) -> None:
    """The command line writes a 16-bit mono loop of the requested length and rate."""
    source = tmp_path / "in.wav"
    out = tmp_path / "out.wav"
    _write_stereo(source, 16000, 3.0)
    code = ambience_loop.main(
        [str(source), str(out), "--seconds", "2", "--fade", "0.5", "--rate", "8000"]
    )
    assert code == 0
    with wave.open(str(out), "rb") as result:
        assert result.getnchannels() == 1
        assert result.getsampwidth() == 2
        assert result.getframerate() == 8000
        assert result.getnframes() == 16000
