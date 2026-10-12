## Tests for the zebra (Phase 18): the Quaternius Farm Animal Pack model as a wild, calm herd
## animal of the savanna only, and the journal knows it.
extends GdUnitTestSuite

const ZEBRA: FaunaSpecies = preload("res://data/fauna/zebra.tres")
const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const JOURNAL: JournalSettings = preload("res://data/journal/journal.tres")


func test_zebras_roam_the_savanna_in_calm_herds() -> void:
	assert_array(Array(ZEBRA.animal.get_validation_errors())).is_empty()
	var homes: Array[StringName] = []
	for biome in TERRAIN.biomes.biomes:
		for entry in biome.fauna:
			if entry.species == ZEBRA:
				homes.append(biome.id)
	assert_array(homes).is_equal([&"savanna"] as Array[StringName])
	assert_int(ZEBRA.temperament).is_equal(FaunaSpecies.Temperament.CALM)
	assert_int(ZEBRA.herd_size.x).is_greater_equal(4)
	var entry := JOURNAL.entry(&"zebra")
	assert_object(entry).is_not_null()
	assert_array(entry.biome_ids(TERRAIN.biomes)).is_equal([&"savanna"] as Array[StringName])


func test_the_model_has_its_walk_and_run() -> void:
	var model: Node3D = auto_free(ZEBRA.animal.model_scene.instantiate())
	var players := model.find_children("*", "AnimationPlayer", true, false)
	var clips := (players[0] as AnimationPlayer).get_animation_list()
	for logical: StringName in [&"idle", &"walk", &"run"]:
		assert_bool(clips.has(ZEBRA.animal.animations[logical])).is_true()
