## Tests for the fennec (Phase 18): built from the fox's rig (tools/make_fennec.py) with big
## ears, a shy desert animal of dusk and night, and the journal knows it.
extends GdUnitTestSuite

const FENNEC: FaunaSpecies = preload("res://data/fauna/fennec.tres")
const FOX: AnimalSpecies = preload("res://data/species/fox.tres")
const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const JOURNAL: JournalSettings = preload("res://data/journal/journal.tres")


func test_the_fennec_is_a_smaller_fox_with_the_same_clips() -> void:
	assert_array(Array(FENNEC.animal.get_validation_errors())).is_empty()
	assert_float(FENNEC.animal.model_scale).is_less(FOX.model_scale)
	var model: Node3D = auto_free(FENNEC.animal.model_scene.instantiate())
	var players := model.find_children("*", "AnimationPlayer", true, false)
	var clips := (players[0] as AnimationPlayer).get_animation_list()
	for logical: StringName in FOX.animations:
		assert_bool(clips.has(FENNEC.animal.animations[logical])).is_true()


func test_it_lives_in_the_desert_shy_and_out_at_dusk_and_night() -> void:
	var homes: Array[StringName] = []
	for biome in TERRAIN.biomes.biomes:
		for entry in biome.fauna:
			if entry.species == FENNEC:
				homes.append(biome.id)
	assert_array(homes).is_equal([&"desert"] as Array[StringName])
	assert_int(FENNEC.temperament).is_equal(FaunaSpecies.Temperament.SHY)
	assert_bool(FENNEC.is_out(12.0)).is_false()
	assert_bool(FENNEC.is_out(19.0)).is_true()
	assert_bool(FENNEC.is_out(2.0)).is_true()  # past midnight
	var entry := JOURNAL.entry(&"fennec")
	assert_array(entry.biome_ids(TERRAIN.biomes)).is_equal([&"desert"] as Array[StringName])
