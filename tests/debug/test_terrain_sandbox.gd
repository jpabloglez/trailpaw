## Integration tests for the terrain sandbox: safe spawn, F4 switching, gizmo and overlay.
extends GdUnitTestSuite

const SANDBOX_SCENE: String = "res://scenes/debug/terrain_sandbox.tscn"
const MAX_FRAMES: int = 1500

var _sandbox: TerrainSandbox


func before_test() -> void:
	_sandbox = auto_free(load(SANDBOX_SCENE).instantiate())
	add_child(_sandbox)
	_sandbox.animal.get_node("%PlayerInput").set_physics_process(false)


func after_test() -> void:
	FloatingOrigin.reset()


func _until(condition: Callable) -> bool:
	for i in MAX_FRAMES:
		await get_tree().process_frame
		if condition.call():
			return true
	return false


func test_sets_world_seed_and_origin() -> void:
	assert_int(GameState.world_seed).is_equal(_sandbox.world_seed)
	assert_float(GameState.chunk_size).is_equal(_sandbox.streamer.terrain.chunk_size)
	assert_float(FloatingOrigin.rebase_distance).is_equal(
		_sandbox.streamer.streaming.rebase_distance
	)


func test_animal_waits_for_collision_then_lands_on_terrain() -> void:
	assert_bool(_sandbox.is_animal_frozen()).is_true()
	assert_bool(await _until(func() -> bool: return not _sandbox.is_animal_frozen())).is_true()
	assert_bool(await _until(func() -> bool: return _sandbox.animal.is_on_floor())).is_true()
	var absolute: Vector3 = GameState.absolute_position(_sandbox.animal.global_position)
	var ground := HeightSampler.new(_sandbox.streamer.terrain, _sandbox.world_seed).height_at(
		absolute.x, absolute.z
	)
	assert_float(_sandbox.animal.global_position.y).is_equal_approx(ground, 0.3)


func test_free_fly_toggle_switches_focus_and_parks_the_animal() -> void:
	await _until(func() -> bool: return not _sandbox.is_animal_frozen())
	_sandbox.toggle_free_fly()
	assert_bool(_sandbox.free_fly.active).is_true()
	assert_object(_sandbox.streamer.target).is_same(_sandbox.free_fly)
	assert_bool(_sandbox.is_animal_frozen()).is_true()
	assert_bool(_sandbox.camera_rig.camera.current).is_false()
	_sandbox.toggle_free_fly()
	assert_object(_sandbox.streamer.target).is_same(_sandbox.animal)
	assert_bool(_sandbox.camera_rig.camera.current).is_true()
	assert_bool(await _until(func() -> bool: return not _sandbox.is_animal_frozen())).is_true()


func test_gizmo_outlines_every_loaded_chunk_when_overlay_is_shown() -> void:
	await _until(func() -> bool: return _sandbox.streamer.is_idle())
	var gizmo := _sandbox.get_node("ChunkBorderGizmo") as ChunkBorderGizmo
	assert_bool(gizmo.visible).is_false()
	(_sandbox.get_node("DebugOverlay") as DebugOverlay).toggle()
	assert_bool(gizmo.visible).is_true()
	assert_int(gizmo.rebuild()).is_equal(_sandbox.streamer.loaded_coords().size())


func test_overlay_shows_streaming_and_world_lines() -> void:
	await _until(func() -> bool: return _sandbox.streamer.is_idle())
	var overlay := _sandbox.get_node("DebugOverlay") as DebugOverlay
	overlay.toggle()
	assert_str(overlay.text()).contains("chunks ")
	assert_str(overlay.text()).contains("build ")
	assert_str(overlay.text()).contains("origin chunk")
	assert_str(overlay.text()).contains("mode animal")
