"""Summarise a perf probe run (``scenes/debug/perf_probe.tscn``) as a Markdown report.

Usage::

    python -m tools.perf_report RUN.csv [--budget MS] [--out REPORT.md]

The CSV starts with one ``# {json}`` header line (GPU, renderer, preset, ...), then a column
header and one row per frame. The report gives frame-time percentiles (p50/p95/p99/max)
overall and per biome, how many frames missed 60 and 30 FPS, the worst frames with what the
game was doing then, and PASS/FAIL against ``p95 <= budget`` (16.6 ms by default, the
Phase 11 exit criterion). Exit status: 0 on PASS, 1 on FAIL, 2 on a bad file. Standard
library only.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import math
import sys
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path

#: Frame-time budget for 60 FPS (ms).
BUDGET_MS = 16.6
#: Frame time of 30 FPS (ms).
HITCH_MS = 33.3
#: Worst frames listed in the report.
WORST = 5


@dataclass
class Run:
    """A parsed probe run.

    Attributes
    ----------
    header : dict
        Machine and run settings from the ``# {json}`` line.
    rows : list[dict[str, str]]
        One mapping per frame, keyed by column name.
    """

    header: dict
    rows: list[dict[str, str]] = field(default_factory=list)

    def column(self, name: str) -> list[float]:
        """Return a numeric column.

        Parameters
        ----------
        name : str
            Column name.

        Returns
        -------
        list[float]
            The values, in frame order.
        """
        return [float(row[name]) for row in self.rows]


def parse(text: str) -> Run:
    """Parse the text of a probe CSV.

    Parameters
    ----------
    text : str
        File contents.

    Returns
    -------
    Run
        Header and rows.

    Raises
    ------
    ValueError
        If the header line or the ``frame_ms`` column is missing.
    """
    lines = text.splitlines()
    if not lines or not lines[0].startswith("# "):
        raise ValueError("missing '# {json}' header line")
    header = json.loads(lines[0][2:])
    reader = csv.DictReader(io.StringIO("\n".join(lines[1:])))
    if reader.fieldnames is None or "frame_ms" not in reader.fieldnames:
        raise ValueError("missing frame_ms column")
    return Run(header=header, rows=list(reader))


def percentile(values: Sequence[float], q: float) -> float:
    """Return the ``q`` percentile by linear interpolation between closest ranks.

    Parameters
    ----------
    values : Sequence[float]
        Samples (any order).
    q : float
        Fraction in [0, 1] (0.95 for p95).

    Returns
    -------
    float
        The percentile, or ``nan`` for no samples.
    """
    if not values:
        return math.nan
    ordered = sorted(values)
    position = q * (len(ordered) - 1)
    low = math.floor(position)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


@dataclass
class Stats:
    """Frame-time statistics of a set of frames (ms).

    Attributes
    ----------
    frames : int
        Number of frames.
    p50, p95, p99, worst : float
        Percentiles and maximum.
    over_budget : int
        Frames slower than the budget.
    hitches : int
        Frames slower than 30 FPS.
    """

    frames: int
    p50: float
    p95: float
    p99: float
    worst: float
    over_budget: int
    hitches: int


def stats(frame_ms: Sequence[float], budget_ms: float = BUDGET_MS) -> Stats:
    """Compute the statistics of ``frame_ms``.

    Parameters
    ----------
    frame_ms : Sequence[float]
        Frame times (ms).
    budget_ms : float
        Budget used for ``over_budget``.

    Returns
    -------
    Stats
        The statistics.
    """
    return Stats(
        frames=len(frame_ms),
        p50=percentile(frame_ms, 0.50),
        p95=percentile(frame_ms, 0.95),
        p99=percentile(frame_ms, 0.99),
        worst=max(frame_ms, default=math.nan),
        over_budget=sum(1 for ms in frame_ms if ms > budget_ms),
        hitches=sum(1 for ms in frame_ms if ms > HITCH_MS),
    )


def by_biome(run: Run, budget_ms: float = BUDGET_MS) -> dict[str, Stats]:
    """Compute frame-time statistics per biome, in the order the biomes were first visited.

    Parameters
    ----------
    run : Run
        The run.
    budget_ms : float
        Budget used for ``over_budget``.

    Returns
    -------
    dict[str, Stats]
        Biome id to statistics.
    """
    groups: dict[str, list[float]] = {}
    for row in run.rows:
        groups.setdefault(row.get("biome", "") or "?", []).append(float(row["frame_ms"]))
    return {biome: stats(values, budget_ms) for biome, values in groups.items()}


def report(run: Run, budget_ms: float = BUDGET_MS) -> tuple[str, bool]:
    """Render the Markdown report.

    Parameters
    ----------
    run : Run
        The run.
    budget_ms : float
        p95 budget (ms).

    Returns
    -------
    tuple[str, bool]
        The Markdown text and whether the run passed (``p95 <= budget_ms``).
    """
    overall = stats(run.column("frame_ms"), budget_ms)
    passed = overall.frames > 0 and overall.p95 <= budget_ms
    h = run.header
    resolution = h.get("resolution", ["?", "?"])
    lines = [
        f"# Perf probe — {h.get('date', '?')}",
        "",
        f"- GPU: {h.get('gpu', '?')} ({h.get('driver', '?')})",
        f"- Renderer: {h.get('renderer', '?')} · {h.get('os', '?')} · Godot {h.get('godot', '?')}",
        (
            f"- Preset: {h.get('preset', '?')} · {resolution[0]:.0f}×{resolution[1]:.0f}"
            f" × {h.get('render_scale', 1.0)} · V-Sync {h.get('vsync', '?')}"
        )
        if isinstance(resolution[0], (int, float))
        else f"- Preset: {h.get('preset', '?')}",
        f"- Path: {h.get('distance_m', '?')} m at {h.get('speed_mps', '?')} m/s, "
        f"seed {h.get('seed', '?')}",
        "",
        f"**Result: {'PASS' if passed else 'FAIL'}** — p95 {overall.p95:.2f} ms "
        f"(budget {budget_ms:.1f} ms)",
        "",
        "| Where | Frames | p50 | p95 | p99 | Max | > budget | > 33 ms |",
        "|---|---|---|---|---|---|---|---|",
        _table_row("**All**", overall),
    ]
    lines += [_table_row(biome, s) for biome, s in by_biome(run, budget_ms).items()]
    worst = sorted(run.rows, key=lambda row: float(row["frame_ms"]), reverse=True)[:WORST]
    lines += [
        "",
        "Worst frames:",
        "",
        "| Frame | ms | Biome | Chunks built | Build ms | Draw calls |",
    ]
    lines.append("|---|---|---|---|---|---|")
    for row in worst:
        lines.append(
            f"| {row['frame']} | {float(row['frame_ms']):.2f} | {row.get('biome', '?')} "
            f"| {row.get('chunks_built', '?')} | {row.get('build_ms', '?')} "
            f"| {row.get('draw_calls', '?')} |"
        )
    return "\n".join(lines) + "\n", passed


def _table_row(name: str, s: Stats) -> str:
    return (
        f"| {name} | {s.frames} | {s.p50:.2f} | {s.p95:.2f} | {s.p99:.2f} | {s.worst:.2f} "
        f"| {s.over_budget} | {s.hitches} |"
    )


def main(argv: Sequence[str] | None = None) -> int:
    """Run the command line.

    Parameters
    ----------
    argv : Sequence[str] or None
        Arguments (``sys.argv[1:]`` when None).

    Returns
    -------
    int
        0 on PASS, 1 on FAIL, 2 when the file cannot be read.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("csv", type=Path)
    parser.add_argument("--budget", type=float, default=BUDGET_MS, help="p95 budget (ms)")
    parser.add_argument("--out", type=Path, help="also write the report here")
    args = parser.parse_args(argv)
    try:
        run = parse(args.csv.read_text(encoding="utf-8"))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"perf_report: {args.csv}: {error}", file=sys.stderr)
        return 2
    text, passed = report(run, args.budget)
    print(text, end="")
    if args.out is not None:
        args.out.write_text(text, encoding="utf-8")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
