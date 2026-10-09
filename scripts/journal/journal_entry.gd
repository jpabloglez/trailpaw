class_name JournalEntry
extends Resource
## One animal of the journal: who it is, the line of text on its card and where its data lives
## ([member animal]), from which the biomes it lives in are read and the sightings matched.
## Values live in [code]data/journal/entries/[/code].

## Which system the animal lives in (and so what [member animal] is).
enum Source {
	FAUNA,  ## a [FaunaSpecies] ([FaunaDirector]'s agents)
	CRITTER,  ## a [CritterKind] ([CritterSystem])
	BIRD,  ## the [BirdSettings] of the songbird flocks ([BirdFlocks])
	FLITTER,  ## a [FlitterKind] ([Flitters])
	FIREFLY,  ## the [SmallLifeSettings] of the fireflies ([Fireflies])
}

## Stable identifier (saves, events).
@export var id: StringName = &""
## Name on the card.
@export var display_name: String = ""
## A short, cozy line about it.
@export_multiline var blurb: String = ""
## Which system it lives in.
@export var source: Source = Source.FAUNA
## Its data in that system (the same resource the system uses).
@export var animal: Resource
## Seen closer than this (m, from the player) and on screen counts as an encounter.
@export_range(1.0, 30.0, 0.5, "suffix:m") var sight_radius: float = 5.0
## Seconds it must stay in sight; 0 uses [member JournalSettings.sight_seconds] (fish, out of
## the water only for a moment, need less).
@export_range(0.0, 10.0, 0.05, "suffix:s") var sight_seconds: float = 0.0


## Ids of the biomes it lives in, in the table's order.
func biome_ids(table: BiomeTable) -> Array[StringName]:
	var out: Array[StringName] = []
	for biome in table.biomes:
		if _lives_in(biome):
			out.append(biome.id)
	return out


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"" or display_name.is_empty() or blurb.is_empty():
		errors.append("id, display_name and blurb must be set")
	var expected: Dictionary = {
		Source.FAUNA: "FaunaSpecies",
		Source.CRITTER: "CritterKind",
		Source.BIRD: "BirdSettings",
		Source.FLITTER: "FlitterKind",
		Source.FIREFLY: "SmallLifeSettings",
	}
	var script: Script = animal.get_script() if animal != null else null
	if script == null or script.get_global_name() != expected[source]:
		errors.append("%s: animal must be a %s" % [id, expected[source]])
	return errors


func _lives_in(biome: BiomeDefinition) -> bool:
	match source:
		Source.FAUNA:
			return biome.fauna.any(func(e: FaunaEntry) -> bool: return e.species == animal)
		Source.CRITTER:
			return (animal as CritterKind).biome_counts.has(biome.id)
		Source.BIRD:
			return (animal as BirdSettings).biome_chance.get(biome.id, 0.0) > 0.0
		Source.FLITTER:
			return (animal as FlitterKind).biomes.has(biome.id)
	return (animal as SmallLifeSettings).firefly_biomes.has(biome.id)
