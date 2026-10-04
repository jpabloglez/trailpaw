class_name CritterPlan
extends RefCounted
## Pure, deterministic placement of small animals: which of a [CritterKind] a full-detail chunk
## hosts, seeded per (world seed, chunk, kind) so the same chunk always brings the same ones.

## Seed salt for critter rolls.
const SALT: int = 0xC217


## Absolute X/Z positions of the [param kind] critters of chunk [param coord] in biome
## [param biome_id] (empty when the chunk hosts none).
static func roll(
	coord: Vector2i, chunk_size: float, biome_id: StringName, kind: CritterKind, world_seed: int
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
	var margin := kind.group_spread
	var centre := (
		Vector2(coord) * chunk_size
		+ Vector2(
			rng.randf_range(margin, chunk_size - margin),
			rng.randf_range(margin, chunk_size - margin)
		)
	)
	for i in count:
		var angle := rng.randf() * TAU
		var distance := sqrt(rng.randf()) * kind.group_spread
		out.append(centre + Vector2(cos(angle), sin(angle)) * distance)
	return out
