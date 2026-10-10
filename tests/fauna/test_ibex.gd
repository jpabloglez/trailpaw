## Tests for the ibex (Phase 17): built from the alpaca's rig (tools/make_ibex.py) with horns,
## it lives in the mountains, climbs slopes the fox can't, and the journal knows it.
extends GdUnitTestSuite

const IBEX: FaunaSpecies = preload("res://data/fauna/ibex.tres")
const FOX: AnimalSpecies = preload("res://data/species/fox.tres")
const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const JOURNAL: JournalSettings = preload("res://data/journal/journal.tres")


func test_the_ibex_is_valid_and_has_horns() -> void:
	assert_array(Array(IBEX.animal.get_validation_errors())).is_empty()
	var model: Node3D = auto_free(IBEX.animal.model_scene.instantiate())
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	assert_int(meshes.size()).is_equal(1)
	var mesh := (meshes[0] as MeshInstance3D).mesh
	var names: Array[String] = []
	for surface in mesh.get_surface_count():
		names.append(mesh.surface_get_material(surface).resource_name)
	assert_array(names).contains(["Horn"])
	var players := model.find_children("*", "AnimationPlayer", true, false)
	var clips := (players[0] as AnimationPlayer).get_animation_list()
	for clip: String in ["Idle", "Walk", "Gallop", "Eating"]:
		assert_bool(clips.has(clip)).override_failure_message(clip).is_true()


func test_it_lives_in_the_mountains_and_climbs_where_the_fox_cannot() -> void:
	var homes: Array[StringName] = []
	for biome in TERRAIN.biomes.biomes:
		for entry in biome.fauna:
			if entry.species == IBEX:
				homes.append(biome.id)
	assert_array(homes).is_equal([&"mountains"] as Array[StringName])
	assert_float(IBEX.animal.max_slope_degrees).is_greater(FOX.max_slope_degrees + 10.0)
	assert_int(IBEX.temperament).is_equal(FaunaSpecies.Temperament.SHY)
	var entry := JOURNAL.entry(&"ibex")
	assert_object(entry).is_not_null()
	assert_array(entry.biome_ids(TERRAIN.biomes)).is_equal([&"mountains"] as Array[StringName])
