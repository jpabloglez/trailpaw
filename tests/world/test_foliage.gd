## Tests for foliage materials (wind sway, recolouring) and vegetation fade settings.
extends GdUnitTestSuite

const SETTINGS_PATH: String = "res://data/world/terrain_settings.tres"
const PALETTE_PATH: String = "res://data/vegetation_palettes/natural.tres"
const WIND_PATH: String = "res://data/world/wind.tres"
const CHUNK_SCENE: String = "res://scenes/world/terrain_chunk.tscn"
const SEED: int = 12345

var _settings: TerrainSettings


func before() -> void:
	_settings = load(SETTINGS_PATH)


func _surface_material(library: VegetationLibrary, id: StringName, surface: int) -> ShaderMaterial:
	return library.mesh_for(id).surface_get_material(surface) as ShaderMaterial


func _original_material(id: StringName, surface: int) -> BaseMaterial3D:
	var type := load("res://data/vegetation/%s.tres" % id) as VegetationType
	var root := type.scene.instantiate()
	var mesh := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var mat := mesh.surface_get_material(surface) as BaseMaterial3D
	root.free()
	return mat


func test_every_surface_uses_the_foliage_shader() -> void:
	var library := VegetationLibrary.new(_settings.biomes)
	for id: StringName in library.ids():
		var mesh := library.mesh_for(id)
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as ShaderMaterial
			assert_object(mat).is_not_null()
			assert_object(mat.shader).is_same(VegetationLibrary.FOLIAGE_SHADER)


func test_without_palette_the_imported_colour_is_kept() -> void:
	var library := VegetationLibrary.new(_settings.biomes)
	var original := _original_material(&"tree_oak", 0)
	var mat := _surface_material(library, &"tree_oak", 0)
	assert_object(mat.get_shader_parameter("albedo")).is_equal(original.albedo_color)


func test_palette_recolours_by_material_name() -> void:
	var palette := load(PALETTE_PATH) as VegetationPalette
	var library := VegetationLibrary.new(_settings.biomes, palette)
	var original := _original_material(&"tree_oak", 0)
	var mat := _surface_material(library, &"tree_oak", 0)
	assert_object(mat.get_shader_parameter("albedo")).is_equal(
		palette.colors[original.resource_name]
	)


func test_natural_palette_makes_leaves_green_not_teal() -> void:
	var palette := load(PALETTE_PATH) as VegetationPalette
	for name: String in ["grass", "leafsGreen", "leafsDark"]:
		var c: Color = palette.colors[name]
		assert_float(c.g).override_failure_message(name).is_greater(c.b + 0.05)
		assert_float(c.g).is_greater(c.r)


func test_sway_and_model_height_come_from_the_type() -> void:
	var library := VegetationLibrary.new(_settings.biomes)
	var grass := _surface_material(library, &"grass", 0)
	var rock := _surface_material(library, &"rock_largeA", 0)
	assert_float(grass.get_shader_parameter("sway")).is_equal(library.sway_for(&"grass"))
	assert_float(grass.get_shader_parameter("sway")).is_greater(0.0)
	assert_float(rock.get_shader_parameter("sway")).is_equal(0.0)
	assert_float(grass.get_shader_parameter("model_height")).is_greater(0.0)


func test_imported_meshes_are_not_modified() -> void:
	VegetationLibrary.new(_settings.biomes, load(PALETTE_PATH))
	assert_object(_original_material(&"tree_oak", 0)).is_instanceof(BaseMaterial3D)


func test_wind_uniform_is_declared_and_packed() -> void:
	var entry: Dictionary = ProjectSettings.get_setting("shader_globals/wind")
	assert_str(entry["type"]).is_equal("vec4")
	var wind := load(WIND_PATH) as WindSettings
	var packed := wind.as_uniform()
	assert_float(Vector2(packed.x, packed.y).length()).is_equal_approx(1.0, 1e-5)
	assert_float(packed.z).is_greater(0.0)
	var code := (VegetationLibrary.FOLIAGE_SHADER as Shader).code
	assert_str(code).contains("global uniform vec4 wind")
	assert_str(code).contains("world_origin_offset")


func test_vegetation_fades_out_at_its_range() -> void:
	var library := VegetationLibrary.new(_settings.biomes)
	var chunk: TerrainChunk = auto_free(load(CHUNK_SCENE).instantiate())
	add_child(chunk)
	var data := ChunkGenerator.generate_with(
		Vector2i(3, 3),
		0,
		_settings,
		HeightSampler.new(_settings, SEED),
		VegetationScatterer.new(_settings.biomes),
		SEED
	)
	chunk.apply(data, load("res://data/world/terrain_material.tres"), library)
	var node := chunk.vegetation_node(&"grass")
	assert_int(node.visibility_range_fade_mode).is_equal(
		GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	)
	assert_float(node.visibility_range_end_margin).is_equal_approx(
		library.visibility_range(&"grass") * TerrainChunk.FADE_MARGIN, 1e-4
	)


func test_sandbox_uses_wind_and_natural_palette() -> void:
	var sandbox: Node = auto_free(load("res://scenes/debug/terrain_sandbox.tscn").instantiate())
	var streamer := sandbox.get_node("WorldStreamer") as WorldStreamer
	assert_str(streamer.wind.resource_path).is_equal(WIND_PATH)
	assert_str(streamer.vegetation_palette.resource_path).is_equal(PALETTE_PATH)
