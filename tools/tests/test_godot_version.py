"""Tests for :mod:`tools.godot_version`."""

from __future__ import annotations

import stat
from pathlib import Path

import pytest

from tools.godot_version import main, parse_godot_version, read_pinned_version


@pytest.mark.parametrize(
    ("output", "expected"),
    [
        ("4.7.1.stable.official.a13da4feb", "4.7.1-stable"),
        ("4.7.stable.official.abcdef123", "4.7-stable"),
        ("4.8.beta2.official.0123abcd", "4.8-beta2"),
        ("  4.7.1.stable.custom_build\n", "4.7.1-stable"),
    ],
)
def test_parse_godot_version(output: str, expected: str) -> None:
    """Known ``--version`` formats are normalised to the pin format."""
    assert parse_godot_version(output) == expected


def test_parse_godot_version_rejects_garbage() -> None:
    """Unrecognised output raises ``ValueError``."""
    with pytest.raises(ValueError, match="unrecognised"):
        parse_godot_version("command not found")


def test_read_pinned_version_strips_whitespace(tmp_path: Path) -> None:
    """The pin file may end with a newline."""
    pin = tmp_path / ".godot-version"
    pin.write_text("4.7.1-stable\n", encoding="utf-8")
    assert read_pinned_version(pin) == "4.7.1-stable"


def test_repository_pin_is_well_formed() -> None:
    """The committed ``.godot-version`` round-trips through the parser."""
    pinned = read_pinned_version(Path(__file__).resolve().parents[2] / ".godot-version")
    number, status = pinned.split("-")
    assert parse_godot_version(f"{number}.{status}.official.0") == pinned


def _fake_godot(tmp_path: Path, output: str) -> Path:
    """Create an executable that prints ``output`` like ``godot --version``."""
    script = tmp_path / "godot"
    script.write_text(f"#!/bin/sh\necho '{output}'\n", encoding="utf-8")
    script.chmod(script.stat().st_mode | stat.S_IEXEC)
    return script


@pytest.mark.parametrize(
    ("output", "exit_code"),
    [("4.7.1.stable.official.x", 0), ("4.7.2.stable.official.x", 1), ("oops", 2)],
)
def test_main_exit_codes(tmp_path: Path, output: str, exit_code: int) -> None:
    """``main`` returns 0 on match, 1 on mismatch and 2 on unparsable output."""
    pin = tmp_path / ".godot-version"
    pin.write_text("4.7.1-stable\n", encoding="utf-8")
    godot = _fake_godot(tmp_path, output)
    assert main(["--godot", str(godot), "--pin", str(pin)]) == exit_code


def test_main_missing_binary(tmp_path: Path) -> None:
    """A missing binary is reported as exit code 2."""
    pin = tmp_path / ".godot-version"
    pin.write_text("4.7.1-stable\n", encoding="utf-8")
    assert main(["--godot", str(tmp_path / "nope"), "--pin", str(pin)]) == 2
