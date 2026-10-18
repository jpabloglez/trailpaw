## A slope-limited walk on a grid, shared by the terrain tests (mountains, desert): can an animal
## that climbs at most a given slope cross a band of the world?
extends RefCounted

## Grid step of the search (m).
const STEP: float = 8.0


## Breadth-first search over a strip at [param angle], from effective distance [param from] to
## [param to], ±200 m to the side, with steps no higher than [param rise] (m per [constant STEP]).
## With a [param water] level, ground under it counts as the water's flat surface (swimming).
static func crosses(
	sampler: HeightSampler, angle: float, from: float, to: float, rise: float, water: float = -INF
) -> bool:
	var along := Vector2.from_angle(angle)
	var side := along.orthogonal()
	var rows := int((to - from) / STEP) + 1
	var cols := int(400.0 / STEP) + 1
	var heights := PackedFloat32Array()
	heights.resize(rows * cols)
	for r in rows:
		for c in cols:
			var p := along * (from + r * STEP) + side * ((c - cols / 2) * STEP)
			heights[r * cols + c] = maxf(sampler.height_at(p.x, p.y), water)
	var seen := PackedByteArray()
	seen.resize(rows * cols)
	var queue := PackedInt32Array()
	for c in cols:
		queue.append(c)
		seen[c] = 1
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var r := cell / cols
		var c := cell % cols
		if r == rows - 1:
			return true
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nr := r + step.x
			var nc := c + step.y
			if nr < 0 or nr >= rows or nc < 0 or nc >= cols:
				continue
			var next := nr * cols + nc
			if seen[next] == 0 and absf(heights[next] - heights[cell]) <= rise:
				seen[next] = 1
				queue.append(next)
	return false
