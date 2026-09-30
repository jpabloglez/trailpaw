class_name FaunaPlan
extends RefCounted
## Pure, deterministic fauna placement: which herd (if any) a chunk hosts. Seeded per
## (world seed, chunk), so the same chunk always brings back the same animals.

## Seed salt for fauna rolls.
const SALT: int = 0xFA07


## Spawns for chunk [param coord] of [param chunk_size] in [param biome]: an array of
## [code][species: FaunaSpecies, absolute xz: Vector2, decision seed: int][/code] (empty when the
## chunk hosts no herd). Positions lie within [param spread] of the chunk centre.
static func roll(
	coord: Vector2i, chunk_size: float, biome: BiomeDefinition, world_seed: int, spread: float
) -> Array:
	var out: Array = []
	if biome == null or biome.fauna.is_empty() or biome.fauna_chance <= 0.0:
		return out
	var rng := RandomNumberGenerator.new()
	var chunk_seed := HeightSampler.layer_seed(world_seed, coord.x * 73856093 ^ coord.y * 19349663)
	rng.seed = HeightSampler.layer_seed(chunk_seed, SALT)
	if rng.randf() >= biome.fauna_chance:
		return out
	var species := _pick(biome.fauna, rng.randf())
	if species == null:
		return out
	var count := rng.randi_range(species.herd_size.x, species.herd_size.y)
	var centre := (Vector2(coord) + Vector2(0.5, 0.5)) * chunk_size
	for i in count:
		var angle := rng.randf() * TAU
		var distance := sqrt(rng.randf()) * spread
		var at := centre + Vector2(cos(angle), sin(angle)) * distance
		out.append([species, at, rng.randi()])
	return out


static func _pick(entries: Array[FaunaEntry], roll_value: float) -> FaunaSpecies:
	var total := 0.0
	for entry in entries:
		total += entry.weight
	var r := roll_value * total
	for entry in entries:
		r -= entry.weight
		if r < 0.0:
			return entry.species
	return entries[entries.size() - 1].species if not entries.is_empty() else null
