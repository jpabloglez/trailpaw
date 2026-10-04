class_name CritterPlan
extends RefCounted
## Pure, deterministic placement of small animals: which of a [CritterKind] a full-detail chunk
## hosts, seeded per (world seed, chunk, kind) so the same chunk always brings the same ones.

## Seed salt for critter rolls.
const SALT: int = 0xC217

## Tries for a group centre where [param accept] (absolute X/Z → bool) holds, e.g. on water.
const CENTRE_TRIES: int = 12


## Absolute X/Z positions of the [param kind] critters of chunk [param coord] in biome
## [param biome_id] (empty when the chunk hosts none). With [param accept], the group's centre
## is the first of [constant CENTRE_TRIES] deterministic candidates it accepts (none: empty).
static func roll(
	coord: Vector2i,
	chunk_size: float,
	biome_id: StringName,
	kind: CritterKind,
	world_seed: int,
	accept: Callable = Callable()
) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not kind.biome_counts.has(biome_id) or kind.chance <= 0.0:
		return out
	var rng := RandomNumberGenerator.new()
	var chunk_seed := HeightSampler.layer_seed(world_seed, coord.x * 73856093 ^ coord.y * 19349663)
	rng.seed = HeightSampler.layer_seed(chunk_seed, SALT ^ hash(kind.id))
	if rng.randf() >= kind.chance:
		return out
	var counts: Vector2i = kind.biome_counts[biome_id]
	var count := rng.randi_range(counts.x, counts.y)
	var margin := minf(kind.group_spread, chunk_size * 0.4)
	var centre := Vector2.INF
	for attempt in CENTRE_TRIES:
		var candidate := (
			Vector2(coord) * chunk_size
			+ Vector2(
				rng.randf_range(margin, chunk_size - margin),
				rng.randf_range(margin, chunk_size - margin)
			)
		)
		if not accept.is_valid() or accept.call(candidate):
			centre = candidate
			break
	if centre == Vector2.INF:
		return out
	for i in count:
		var angle := rng.randf() * TAU
		var distance := sqrt(rng.randf()) * kind.group_spread
		out.append(centre + Vector2(cos(angle), sin(angle)) * distance)
	return out
