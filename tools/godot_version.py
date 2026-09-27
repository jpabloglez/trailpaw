"""Check that the installed Godot binary matches the version pinned in ``.godot-version``.

Usage::

    python -m tools.godot_version [--godot PATH] [--pin FILE]

The Godot binary defaults to ``$GODOT_BIN`` or ``godot`` on ``PATH``. Exit code is 0 when
the versions match, 1 on mismatch and 2 when the binary cannot be run.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path

DEFAULT_PIN_FILE = Path(__file__).resolve().parent.parent / ".godot-version"

_VERSION_RE = re.compile(r"^(?P<number>\d+\.\d+(?:\.\d+)?)\.(?P<status>[a-z]+\d*)\b")


def read_pinned_version(pin_file: Path) -> str:
    """Read the pinned Godot version.

    Parameters
    ----------
    pin_file : Path
        File containing a single version string such as ``4.7.1-stable``.

    Returns
    -------
    str
        The pinned version with surrounding whitespace removed.
    """
    return pin_file.read_text(encoding="utf-8").strip()


def parse_godot_version(output: str) -> str:
    """Convert ``godot --version`` output to the ``.godot-version`` format.

    Parameters
    ----------
    output : str
        Raw output, e.g. ``4.7.1.stable.official.a13da4feb``.

    Returns
    -------
    str
        Normalised version, e.g. ``4.7.1-stable``.

    Raises
    ------
    ValueError
        If the output does not start with a recognisable Godot version.
    """
    match = _VERSION_RE.match(output.strip())
    if match is None:
        raise ValueError(f"unrecognised Godot version output: {output!r}")
    return f"{match['number']}-{match['status']}"


def installed_version(godot: str) -> str:
    """Run ``godot --version`` and return the normalised version.

    Parameters
    ----------
    godot : str
        Path or command name of the Godot binary.

    Returns
    -------
    str
        Normalised version, e.g. ``4.7.1-stable``.
    """
    result = subprocess.run(
        [godot, "--version"], capture_output=True, text=True, check=True, timeout=60
    )
    return parse_godot_version(result.stdout.strip().splitlines()[-1])


def main(argv: Sequence[str] | None = None) -> int:
    """Compare the installed Godot version against the pin.

    Parameters
    ----------
    argv : Sequence[str] or None, optional
        Command-line arguments; defaults to ``sys.argv[1:]``.

    Returns
    -------
    int
        0 on match, 1 on mismatch, 2 if Godot cannot be run.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--pin", type=Path, default=DEFAULT_PIN_FILE)
    args = parser.parse_args(argv)

    pinned = read_pinned_version(args.pin)
    try:
        found = installed_version(args.godot)
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        print(f"error: cannot determine Godot version: {exc}", file=sys.stderr)
        return 2
    if found != pinned:
        print(f"mismatch: pinned {pinned}, installed {found}", file=sys.stderr)
        return 1
    print(f"ok: Godot {found}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
