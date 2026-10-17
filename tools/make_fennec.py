"""Build the fennec model (``assets/animals/fennec/fennec.glb``) from the CC0 Quaternius fox.

The fennec keeps the fox's rig and animation clips (the fauna code drives it like the fox), with
its own look:

* much bigger ears: the vertices skinned to the ear bones, scaled up from each ear's base,
* a slimmer body,
* a pale sand coat, a cream chest and soft tan legs.

Run inside a Python environment with ``bpy`` (Blender as a module; not a project dependency,
see ADR-008)::

    python tools/make_fennec.py [path/to/fox.glb] [path/to/fennec.glb]

The geometry helpers are plain Python (tested in ``tools/tests``); only :func:`main` needs bpy.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/animals/fox/fox.glb"
TARGET = ROOT / "assets/animals/fennec/fennec.glb"

#: How much bigger the ears grow from their base, and how much wider they open.
EAR_GROWTH = 1.9
EAR_WIDENING = 1.25
#: Body width kept (slimmer than the fox).
WIDTH_KEEP = 0.88
#: Ear-bone weight from which a vertex starts following the growth, and at which it follows it
#: fully (smooth in between, so the ear's base blends into the head).
EAR_WEIGHT_START = 0.15
EAR_WEIGHT_FULL = 0.85
#: New base colours (linear RGBA) for the fox's materials.
COLOURS = {
    "Main": (0.62, 0.45, 0.26, 1.0),
    "Main_Light": (0.76, 0.72, 0.62, 1.0),
    "Grey": (0.42, 0.33, 0.22, 1.0),
}


def grow_ear(
    point: tuple[float, float, float], base: tuple[float, float, float]
) -> tuple[float, float, float]:
    """Return an ear vertex moved outwards from its ear's base.

    Parameters
    ----------
    point
        The vertex, in the rig's rest space.
    base
        Where the ear meets the head (the first ear bone's head).

    Returns
    -------
    tuple of float
        The vertex scaled by :data:`EAR_GROWTH` from ``base``, with its sideways offset widened
        by :data:`EAR_WIDENING` too.
    """
    dx, dy, dz = (p - b for p, b in zip(point, base, strict=True))
    return (
        base[0] + dx * EAR_GROWTH * EAR_WIDENING,
        base[1] + dy * EAR_GROWTH,
        base[2] + dz * EAR_GROWTH,
    )


def ear_share(weight: float) -> float:
    """Return how much an ear vertex follows the growth, from its weight on the ear bones.

    Parameters
    ----------
    weight
        The vertex's summed weight on its ear's bones (0…1).

    Returns
    -------
    float
        0 below :data:`EAR_WEIGHT_START`, 1 above :data:`EAR_WEIGHT_FULL`, smooth in between.
    """
    span = EAR_WEIGHT_FULL - EAR_WEIGHT_START
    t = min(1.0, max(0.0, (weight - EAR_WEIGHT_START) / span))
    return t * t * (3.0 - 2.0 * t)


def slim(point: tuple[float, float, float]) -> tuple[float, float, float]:
    """Return a body vertex made narrower (the rig's X is sideways)."""
    return (point[0] * WIDTH_KEEP, point[1], point[2])


def main(source: Path = SOURCE, target: Path = TARGET) -> None:
    """Build the fennec from ``source`` and export it to ``target`` (needs bpy)."""
    import bpy  # noqa: PLC0415 (Blender only exists inside its own Python)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    for stray in [o for o in bpy.data.objects if o.type == "MESH" and o.parent is None]:
        bpy.data.objects.remove(stray)  # a helper sphere left in the source file
    body = next(o for o in bpy.data.objects if o.type == "MESH")
    body.name = "Fennec"
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    ears = {}
    for side in ("L", "R"):
        groups = {body.vertex_groups[f"Ear{i}.{side}"].index for i in range(1, 5)}
        ears[side] = (tuple(rig.data.bones[f"Ear1.{side}"].head_local), groups)
    for vertex in body.data.vertices:
        point = tuple(vertex.co)
        moved = slim(point)
        for base, groups in ears.values():
            share = ear_share(sum(g.weight for g in vertex.groups if g.group in groups))
            if share > 0.0:
                grown = grow_ear(point, base)
                moved = tuple(m + (g - m) * share for m, g in zip(moved, grown, strict=True))
                break
        vertex.co = moved
    for material in body.data.materials:
        if material.name in COLOURS:
            shader = material.node_tree.nodes["Principled BSDF"]
            shader.inputs["Base Color"].default_value = COLOURS[material.name]
    target.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", export_animations=True)


if __name__ == "__main__":
    main(*(Path(arg) for arg in sys.argv[1:3]))
