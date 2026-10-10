"""Tests for tools.make_ibex (the plain-Python geometry; building the model needs bpy)."""

from __future__ import annotations

import math

from tools.make_ibex import NECK_BASE, NECK_FRONT, WIDTH_KEEP, horn_path, reshape, tube


def test_reshape_narrows_the_body_and_lowers_the_neck() -> None:
    """Every vertex gets narrower; only the neck and head (high, in front) come down."""
    back = reshape(0.004, -0.03, 0.01)  # high on the back, behind the neck
    assert back == (0.004 * WIDTH_KEEP, -0.03, 0.01)
    head = reshape(0.0, -0.05, -0.02)  # the head, high in front
    assert -head[1] < 0.05
    assert -head[1] > NECK_BASE
    low = reshape(0.0, -0.01, -0.02)  # the chest, below the neck base
    assert low[1] == -0.01


def test_reshape_blends_in_behind_the_neck() -> None:
    """Just behind the neck the change fades in: no step in the back line."""
    edge = reshape(0.0, -0.05, NECK_FRONT - 1e-6)
    inside = reshape(0.0, -0.05, NECK_FRONT - 0.01)
    assert abs(edge[1] + 0.05) < 1e-3  # barely moved at the edge
    assert -inside[1] < -edge[1]  # fully lowered further forward


def test_horn_path_rises_then_sweeps_back() -> None:
    """The arc starts at the base, goes up, and ends behind it."""
    base = (0.001, -0.05, -0.02)
    path = horn_path(base, 0.005, 165.0, 12)
    assert len(path) == 13
    assert path[0] == base
    highest = min(p[1] for p in path)
    assert highest < base[1] - 0.004  # up is -Y
    assert path[-1][2] > base[2] + 0.009  # far back (+Z)
    for a, b in zip(path, path[1:], strict=False):
        step = math.dist(a, b)
        assert math.isclose(step, 2 * 0.005 * math.sin(math.radians(165.0 / 12) / 2), rel_tol=1e-6)


def test_tube_is_closed_and_tapers() -> None:
    """Rings of ``sides`` vertices, quads between them and a pointed tip."""
    path = horn_path((0.0, 0.0, 0.0), 0.005, 90.0, 4)
    vertices, faces = tube(path, 0.001, 0.0002, 6)
    assert len(vertices) == 5 * 6 + 1
    assert len(faces) == 4 * 6 + 6
    assert all(len(face) == 4 for face in faces[:24])
    assert all(len(face) == 3 and face[2] == len(vertices) - 1 for face in faces[24:])
    for face in faces:
        assert all(0 <= index < len(vertices) for index in face)

    def ring_radius(r: int) -> float:
        centre = path[r]
        return max(math.dist(centre, vertices[r * 6 + s]) for s in range(6))

    assert math.isclose(ring_radius(0), 0.001, rel_tol=1e-6)
    assert math.isclose(ring_radius(4), 0.0002, rel_tol=1e-6)
