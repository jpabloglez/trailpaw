## Tests for the terrain shader material and the absolute-origin global shader uniform.
extends GdUnitTestSuite

const MATERIAL_PATH: String = "res://data/world/terrain_material.tres"
const SHADER_PATH: String = "res://shaders/terrain.gdshader"


func after_test() -> void:
	FloatingOrigin.reset()
	GameState.chunk_size = 0.0


func test_material_uses_the_terrain_shader_with_explicit_tunables() -> void:
	var mat := load(MATERIAL_PATH) as ShaderMaterial
	assert_object(mat).is_not_null()
	assert_str(mat.shader.resource_path).is_equal(SHADER_PATH)
	for param: String in [
		"macro_scale",
		"macro_contrast",
		"detail_scale",
		"detail_strength",
		"rock_color",
		"rock_start_degrees",
		"rock_full_degrees",
		"roughness_value",
	]:
		var message := "%s must be set in the material, not left to shader defaults" % param
		var is_set: bool = mat.get_shader_parameter(param) != null
		assert_bool(is_set).override_failure_message(message).is_true()
	assert_object(mat.get_shader_parameter("pattern_noise")).is_instanceof(NoiseTexture2D)


func test_rock_band_is_ordered_and_below_the_slope_limit() -> void:
	var mat := load(MATERIAL_PATH) as ShaderMaterial
	var start: float = mat.get_shader_parameter("rock_start_degrees")
	var full: float = mat.get_shader_parameter("rock_full_degrees")
	var limit := (load("res://data/species/placeholder.tres") as AnimalSpecies).max_slope_degrees
	assert_float(start).is_less(full)
	assert_float(full).is_less_equal(limit)  # unwalkable slopes read as rock


func test_pattern_texture_is_seamless() -> void:
	var tex := (
		(load(MATERIAL_PATH) as ShaderMaterial).get_shader_parameter("pattern_noise")
		as NoiseTexture2D
	)
	assert_bool(tex.seamless).is_true()


func test_shader_reads_palette_b_from_standard_attributes() -> void:
	var code := (load(SHADER_PATH) as Shader).code
	assert_str(code).contains("global uniform vec3 world_origin_offset")
	assert_str(code).contains("UV2.x, UV2.y, COLOR.a")
	assert_str(code).not_contains("CUSTOM0")


func test_origin_uniform_is_declared_in_project_settings() -> void:
	var entry: Dictionary = ProjectSettings.get_setting("shader_globals/world_origin_offset")
	assert_str(entry["type"]).is_equal("vec3")


func test_rebase_updates_the_origin_uniform() -> void:
	FloatingOrigin.configure(64.0, 0.0)
	var target: Node3D = auto_free(Node3D.new())
	target.position = Vector3(300.0, 0.0, -200.0)
	add_child(target)
	FloatingOrigin.track(target)
	FloatingOrigin.rebase_now()
	assert_vector(FloatingOrigin.shader_origin()).is_equal(GameState.origin_offset())
	assert_vector(FloatingOrigin.shader_origin()).is_not_equal(Vector3.ZERO)
	_assert_rendering_server_matches()
	FloatingOrigin.reset()
	assert_vector(FloatingOrigin.shader_origin()).is_equal(Vector3.ZERO)
	_assert_rendering_server_matches()


## The headless dummy renderer does not store global parameters; check them when real.
func _assert_rendering_server_matches() -> void:
	var value: Variant = RenderingServer.global_shader_parameter_get(
		FloatingOrigin.SHADER_ORIGIN_PARAM
	)
	if value != null:
		assert_vector(value as Vector3).is_equal(FloatingOrigin.shader_origin())
