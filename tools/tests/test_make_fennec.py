"""Tests for tools.make_fennec (the plain-Python geometry; building the model needs bpy)."""

from __future__ import annotations

import math

from tools.make_fennec import (
    EAR_GROWTH,
    EAR_WEIGHT_FULL,
    EAR_WEIGHT_START,
    EAR_WIDENING,
    WIDTH_KEEP,
    ear_share,
    grow_ear,
    slim,
)


def test_ears_grow_outwards_from_their_base() -> None:
    """The base stays put; a tip moves EAR_GROWTH times as far, wider sideways."""
    base = (0.0017, -0.0223, -0.0199)
    assert grow_ear(base, base) == base
    tip = (0.0039, -0.0253, -0.0213)
    grown = grow_ear(tip, base)
    before = math.dist(tip, base)
    after = math.dist(grown, base)
    assert after > before * EAR_GROWTH * 0.99
    assert math.isclose(grown[1] - base[1], (tip[1] - base[1]) * EAR_GROWTH)
    assert math.isclose(grown[0] - base[0], (tip[0] - base[0]) * EAR_GROWTH * EAR_WIDENING)


def test_the_body_is_slimmer_but_as_long_and_tall() -> None:
    """Only the sideways axis shrinks."""
    assert slim((0.004, -0.02, 0.01)) == (0.004 * WIDTH_KEEP, -0.02, 0.01)


def test_the_ear_growth_blends_in_with_the_weight() -> None:
    """No growth for barely-ear vertices, full growth for ear ones, smooth and rising between."""
    assert ear_share(0.0) == 0.0
    assert ear_share(EAR_WEIGHT_START) == 0.0
    assert ear_share(EAR_WEIGHT_FULL) == 1.0
    assert ear_share(1.0) == 1.0
    shares = [ear_share(EAR_WEIGHT_START + i * 0.05) for i in range(15)]
    assert all(b >= a for a, b in zip(shares, shares[1:], strict=False))
