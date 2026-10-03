"""Tests for tools.perf_report."""

from __future__ import annotations

import json
import math
from pathlib import Path

import pytest

from tools import perf_report

HEADER = {"gpu": "Test GPU", "preset": "medium", "resolution": [1920, 1080], "seed": 12345}
COLUMNS = (
    "frame,t_s,frame_ms,render_cpu_ms,render_gpu_ms,draw_calls,primitives,chunks_built,"
    "build_ms,fauna,biome"
)


def _csv(frames: list[tuple[float, str]]) -> str:
    rows = [f"# {json.dumps(HEADER)}", COLUMNS]
    for i, (ms, biome) in enumerate(frames):
        rows.append(f"{i},{i * 0.016:.3f},{ms},1.0,2.0,150,250000,0,0.000,3,{biome}")
    return "\n".join(rows) + "\n"


def test_percentile_interpolates_between_ranks() -> None:
    """Percentiles interpolate linearly; edge cases are exact."""
    values = [float(v) for v in range(1, 101)]  # 1..100
    assert perf_report.percentile(values, 0.5) == pytest.approx(50.5)
    assert perf_report.percentile(values, 0.95) == pytest.approx(95.05)
    assert perf_report.percentile(values, 0.0) == 1.0
    assert perf_report.percentile(values, 1.0) == 100.0
    assert perf_report.percentile([7.0], 0.95) == 7.0
    assert math.isnan(perf_report.percentile([], 0.5))


def test_parse_reads_the_header_and_rows() -> None:
    """The JSON header and the rows are read."""
    run = perf_report.parse(_csv([(10.0, "meadow"), (12.0, "forest")]))
    assert run.header["gpu"] == "Test GPU"
    assert run.column("frame_ms") == [10.0, 12.0]
    assert run.rows[1]["biome"] == "forest"


@pytest.mark.parametrize("text", ["", "frame_ms\n1\n", "# {}\nframe,t_s\n0,0\n"])
def test_parse_rejects_files_without_header_or_frame_times(text: str) -> None:
    """Files without the header or frame_ms are refused."""
    with pytest.raises(ValueError):
        perf_report.parse(text)


def test_stats_count_frames_over_budget_and_hitches() -> None:
    """Frames over budget and over 33 ms are counted."""
    s = perf_report.stats([10.0] * 90 + [20.0] * 8 + [40.0] * 2)
    assert s.frames == 100
    assert s.over_budget == 10
    assert s.hitches == 2
    assert s.worst == 40.0
    assert s.p50 == pytest.approx(10.0)


def test_per_biome_in_visiting_order() -> None:
    """Statistics are grouped per biome in visiting order."""
    run = perf_report.parse(_csv([(10.0, "meadow")] * 3 + [(30.0, "forest")] * 2))
    groups = perf_report.by_biome(run)
    assert list(groups) == ["meadow", "forest"]
    assert groups["forest"].p50 == pytest.approx(30.0)
    assert groups["meadow"].frames == 3


def test_report_passes_only_within_the_p95_budget() -> None:
    """PASS needs p95 within the budget; the report names GPU and biomes."""
    fast = perf_report.parse(_csv([(12.0, "meadow")] * 100))
    text, passed = perf_report.report(fast)
    assert passed
    assert "**Result: PASS**" in text
    assert "Test GPU" in text
    slow = perf_report.parse(_csv([(12.0, "meadow")] * 90 + [(25.0, "forest")] * 10))
    text, passed = perf_report.report(slow)
    assert not passed
    assert "**Result: FAIL**" in text
    assert "| forest |" in text


def test_main_exit_status(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    """The command line returns 0 on PASS, 1 on FAIL and 2 on a bad file."""
    good = tmp_path / "good.csv"
    good.write_text(_csv([(10.0, "meadow")] * 20), encoding="utf-8")
    out = tmp_path / "report.md"
    assert perf_report.main([str(good), "--out", str(out)]) == 0
    assert "PASS" in out.read_text(encoding="utf-8")
    assert perf_report.main([str(good), "--budget", "5"]) == 1
    bad = tmp_path / "bad.csv"
    bad.write_text("nonsense", encoding="utf-8")
    assert perf_report.main([str(bad)]) == 2
    assert "perf_report" in capsys.readouterr().err
