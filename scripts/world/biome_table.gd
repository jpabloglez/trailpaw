class_name BiomeTable
extends Resource
## Ordered sequence of biome bands radiating out from the spawn point. With [member cycle]
## the sequence repeats forever (meadow → forest → river valley → hills → meadow …), so the
## endless world keeps changing. Lives at [code]data/biomes/biome_table.tres[/code].

## Biomes in band order, starting at the spawn point.
@export var biomes: Array[BiomeDefinition] = []
## Repeat the sequence after the last band; otherwise the last band extends forever.
@export var cycle: bool = false
## Distance over which two neighbouring bands cross-fade.
@export_range(1.0, 2000.0, 1.0, "suffix:m") var blend_width: float = 0.0
## Maximum amount the noise pushes band boundaries in or out, so they look organic.
@export_range(0.0, 2000.0, 1.0, "suffix:m") var boundary_noise_amplitude: float = 0.0
## Frequency of the boundary noise.
@export_range(0.00001, 0.1, 0.00001, "suffix:1/m") var boundary_noise_frequency: float = 0.0
## Absolute XZ position distances are measured from.
@export var spawn: Vector2 = Vector2.ZERO


## Returns human-readable problems with the table; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if biomes.is_empty():
		errors.append("biomes must not be empty")
	var ids := {}
	for i in biomes.size():
		var biome := biomes[i]
		if biome == null:
			errors.append("biomes[%d] is null" % i)
			continue
		for problem: String in biome.get_validation_errors():
			errors.append("biomes[%d] (%s): %s" % [i, biome.id, problem])
		if ids.has(biome.id):
			errors.append("duplicate biome id '%s'" % biome.id)
		ids[biome.id] = true
	if blend_width <= 0.0:
		errors.append("blend_width must be > 0")
	elif not biomes.is_empty() and blend_width > narrowest_band():
		errors.append("blend_width must not exceed the narrowest band (%.0f m)" % narrowest_band())
	if boundary_noise_amplitude < 0.0:
		errors.append("boundary_noise_amplitude must be >= 0")
	if boundary_noise_amplitude > 0.0 and boundary_noise_frequency <= 0.0:
		errors.append("boundary_noise_frequency must be > 0 when the amplitude is > 0")
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()


## Width of the narrowest band (m); 0 for an empty table.
func narrowest_band() -> float:
	var narrowest := INF
	for biome in biomes:
		if biome != null:
			narrowest = minf(narrowest, biome.band_width)
	return narrowest if narrowest != INF else 0.0


## Distance covered by one pass through all bands (m).
func sequence_length() -> float:
	var total := 0.0
	for biome in biomes:
		if biome != null:
			total += biome.band_width
	return total
