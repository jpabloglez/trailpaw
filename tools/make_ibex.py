"""Build the ibex model (``assets/animals/ibex/ibex.glb``) from the CC0 Quaternius alpaca.

The ibex keeps the alpaca's rig and animation clips (so the fauna code drives it like the
alpaca), with its own shape and colours:

* a shorter neck and a slimmer, stockier body (vertices moved in the rig's rest space),
* two thick horns sweeping back in an arc, skinned to the ``Head`` bone,
* grey-brown coat, a pale belly and dark legs.

Run inside a Python environment with ``bpy`` (Blender as a module; not a project dependency,
see ADR-008)::

    python tools/make_ibex.py [path/to/alpaca.glb] [path/to/ibex.glb]

The geometry helpers are plain Python (tested in ``tools/tests``); only :func:`main` needs bpy.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/animals/alpaca/alpaca.glb"
TARGET = ROOT / "assets/animals/ibex/ibex.glb"

#: Rig space of the Quaternius animals: up is -Y, forward is -Z (metres x 100 in the file).
UP = (0.0, -1.0, 0.0)
#: Height above the hooves (in rig units) where the neck starts, and how much of the neck's
#: height above it is kept.
NECK_BASE = 0.026
NECK_KEEP = 0.45
#: The neck is the part forward of this (rig Z).
NECK_FRONT = -0.006
#: Body width kept (slimmer than the woolly alpaca).
WIDTH_KEEP = 0.82
#: New base colours (linear RGBA) for the alpaca's materials, and the horns'.
COLOURS = {
    "Main": (0.16, 0.12, 0.085, 1.0),
    "Main_Light": (0.42, 0.36, 0.27, 1.0),
    "Main_Dark": (0.05, 0.04, 0.035, 1.0),
}
HORN_COLOUR = (0.05, 0.042, 0.032, 1.0)


def reshape(x: float, y: float, z: float) -> tuple[float, float, float]:
    """Return a rest-space vertex of the alpaca moved to the ibex's shape.

    Parameters
    ----------
    x, y, z
        Vertex position in the rig's rest space (up is -Y, forward is -Z).

    Returns
    -------
    tuple of float
        The moved position: narrower everywhere, and the neck and head lowered towards the
        shoulders.
    """
    height = -y
    x *= WIDTH_KEEP
    if z < NECK_FRONT and height > NECK_BASE:
        # Blend in over the first few units behind the neck so the back stays smooth.
        blend = min(1.0, (NECK_FRONT - z) / 0.006)
        kept = NECK_BASE + (height - NECK_BASE) * NECK_KEEP
        height = height + (kept - height) * blend
    return (x, -height, z)


def horn_path(
    base: tuple[float, float, float], radius: float, sweep_degrees: float, steps: int
) -> list[tuple[float, float, float]]:
    """Return points along a horn: an arc rising and sweeping back from ``base``.

    Parameters
    ----------
    base
        Where the horn grows from (rig space).
    radius
        Radius of the arc (rig units).
    sweep_degrees
        How far the arc turns, from pointing up to pointing back and down.
    steps
        Number of segments.

    Returns
    -------
    list of tuple of float
        ``steps + 1`` points from the base to the tip.
    """
    points = []
    for i in range(steps + 1):
        angle = math.radians(sweep_degrees) * i / steps
        up = radius * math.sin(angle)
        back = radius * (1.0 - math.cos(angle))
        points.append((base[0], base[1] - up, base[2] + back))
    return points


def tube(
    path: list[tuple[float, float, float]], thick: float, thin: float, sides: int
) -> tuple[list[tuple[float, float, float]], list[tuple[int, ...]]]:
    """Return the vertices and faces of a tapering tube along ``path``, closed at the tip.

    Parameters
    ----------
    path
        Centre line, base first.
    thick, thin
        Radius at the base and at the tip.
    sides
        Sides of each ring.

    Returns
    -------
    tuple
        ``(vertices, faces)``: quads between rings and a fan of triangles at the tip.
    """
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    rings = len(path)
    for r, centre in enumerate(path):
        nxt = path[min(r + 1, rings - 1)]
        prv = path[max(r - 1, 0)]
        tangent = _normalise(tuple(n - p for n, p in zip(nxt, prv, strict=True)))
        side = (1.0, 0.0, 0.0)
        normal = _normalise(_cross(tangent, side))
        size = thick + (thin - thick) * r / (rings - 1)
        for s in range(sides):
            a = math.tau * s / sides
            offset = tuple(
                size * (math.cos(a) * side[k] + math.sin(a) * normal[k]) for k in range(3)
            )
            vertices.append(tuple(centre[k] + offset[k] for k in range(3)))
    for r in range(rings - 1):
        for s in range(sides):
            a = r * sides + s
            b = r * sides + (s + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    tip = len(vertices)
    vertices.append(path[-1])
    last = (rings - 1) * sides
    for s in range(sides):
        faces.append((last + s, last + (s + 1) % sides, tip))
    return vertices, faces


def _cross(a: tuple[float, ...], b: tuple[float, ...]) -> tuple[float, float, float]:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _normalise(v: tuple[float, ...]) -> tuple[float, float, float]:
    length = math.sqrt(sum(c * c for c in v)) or 1.0
    return (v[0] / length, v[1] / length, v[2] / length)


def main(source: Path = SOURCE, target: Path = TARGET) -> None:
    """Build the ibex from ``source`` and export it to ``target`` (needs bpy)."""
    import bpy  # noqa: PLC0415 (Blender only exists inside its own Python)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    for stray in [o for o in bpy.data.objects if o.type == "MESH" and o.parent is None]:
        bpy.data.objects.remove(stray)  # a helper sphere left in the source file
    body = next(o for o in bpy.data.objects if o.type == "MESH")
    body.name = "Ibex"
    for vertex in body.data.vertices:
        vertex.co = reshape(*vertex.co)
    for material in body.data.materials:
        if material.name in COLOURS:
            shader = material.node_tree.nodes["Principled BSDF"]
            shader.inputs["Base Color"].default_value = COLOURS[material.name]
    horn_material = bpy.data.materials.new("Horn")
    horn_material.use_nodes = True
    bsdf = horn_material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = HORN_COLOUR
    bsdf.inputs["Roughness"].default_value = 0.7
    top = max(-v.co.y for v in body.data.vertices if v.co.z < -0.012)  # the top of the head
    front = min(v.co.z for v in body.data.vertices if -v.co.y > top - 0.002)
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for sign in (-1.0, 1.0):  # both horns in one mesh, joined once
        base = (sign * 0.0013, -(top - 0.0008), front + 0.0035)
        ring, quads = tube(horn_path(base, 0.0047, 165.0, 12), 0.0014, 0.0003, 7)
        faces += [tuple(index + len(vertices) for index in face) for face in quads]
        vertices += ring
    mesh = bpy.data.meshes.new("Horns")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(horn_material)
    horns = bpy.data.objects.new("Horns", mesh)
    bpy.context.collection.objects.link(horns)
    group = horns.vertex_groups.new(name="Head")  # skinned rigidly to the head
    group.add(list(range(len(vertices))), 1.0, "REPLACE")
    horns.parent = body.parent
    horns.matrix_world = body.matrix_world
    bpy.ops.object.select_all(action="DESELECT")
    horns.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    target.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", export_animations=True)


if __name__ == "__main__":
    main(*(Path(arg) for arg in sys.argv[1:3]))
