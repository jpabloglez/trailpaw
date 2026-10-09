## Tests for the map: what the renderer draws (fog, land, water, scale), and the map screen in
## the game flow (M opens and pauses, drawing on a worker, zoom, Esc closes, from the pause
## menu, the player arrow, remappable).
extends GdUnitTestSuite

const MAIN_SCENE: String = "res://scenes/main/main.tscn"
const TEST_DIR: String = "user://test_map_saves"
const MAX_FRAMES: int = 1500
const SETTINGS: MapSettings = preload("res://data/ui/map.tres")
const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const EXPLORATION: ExplorationSettings = preload("res://data/world/exploration.tres")
const SPAWN := Vector2(32.0, 32.0)
## The spawn meadow's nearest lake with seed 12345 (see test_water_scent.gd), a little inside.
const LAKE := Vector2(250.0, -720.0)

var _saved_dir: String
var _flow: GameFlow


func before_test() -> void:
	_saved_dir = SaveSystem.save_dir
	SaveSystem.save_dir = TEST_DIR
	SaveSystem.erase()


func after_test() -> void:
	get_tree().paused = false
	if _flow != null and is_instance_valid(_flow):
		_flow.free()
	SaveSystem.erase()
	SaveSystem.save_dir = _saved_dir
	FloatingOrigin.reset()
	get_tree().auto_accept_quit = true


# --- renderer -----------------------------------------------------------------------------


func _renderer(span: float) -> MapRenderer:
	var explored := ExploredMap.new(EXPLORATION)
	explored.reveal(Vector3(SPAWN.x, 0, SPAWN.y), EXPLORATION.reveal_radius)
	explored.reveal(Vector3(LAKE.x, 0, LAKE.y), EXPLORATION.reveal_radius)
	return MapRenderer.new(
		HeightSampler.new(TERRAIN, 12345),
		explored.cells_snapshot(),
		explored.cell_size,
		SPAWN,
		span,
		TERRAIN.sea_level,
		SETTINGS
	)


func _color_at(renderer: MapRenderer, image: Image, x: float, z: float) -> Color:
	var p := renderer.pixel_of(x, z)
	return image.get_pixel(int(p.x), int(p.y))


func test_draws_fog_land_and_water() -> void:
	var renderer := _renderer(2000.0)
	var image := renderer.render()
	assert_int(image.get_width()).is_equal(SETTINGS.image_size)
	var sampler := HeightSampler.new(TERRAIN, 12345)
	assert_float(sampler.height_at(LAKE.x, LAKE.y)).is_less(TERRAIN.sea_level - 0.5)
	var lake := _color_at(renderer, image, LAKE.x, LAKE.y)
	assert_float(lake.b).is_greater(lake.r + 0.15)  # water is blue
	var meadow := _color_at(renderer, image, SPAWN.x, SPAWN.y)
	assert_float(meadow.g).is_greater(meadow.b)  # land is not
	assert_bool(meadow.is_equal_approx(SETTINGS.fog_color)).is_false()
	var unexplored := _color_at(renderer, image, SPAWN.x + 600.0, SPAWN.y + 600.0)
	assert_int(unexplored.to_rgba32()).is_equal(Color(SETTINGS.fog_color, 1.0).to_rgba32())


func test_the_span_sets_the_scale() -> void:
	var near := _renderer(1000.0)
	var far := _renderer(2000.0)
	var centre := Vector2.ONE * SETTINGS.image_size * 0.5
	assert_vector(near.pixel_of(SPAWN.x, SPAWN.y)).is_equal(centre)
	var east := SPAWN.x + 250.0
	var near_offset := near.pixel_of(east, SPAWN.y).x - centre.x
	var far_offset := far.pixel_of(east, SPAWN.y).x - centre.x
	assert_float(near_offset).is_equal_approx(SETTINGS.image_size * 0.25, 0.01)
	assert_float(far_offset).is_equal_approx(near_offset * 0.5, 0.01)
	# North (−Z) is up.
	assert_float(near.pixel_of(SPAWN.x, SPAWN.y - 100.0).y).is_less(centre.y)


# --- the screen in the game ---------------------------------------------------------------


func _until(condition: Callable) -> bool:
	for i in MAX_FRAMES:
		await get_tree().process_frame
		if condition.call():
			return true
	return false


func _playing() -> GameFlow:
	_flow = load(MAIN_SCENE).instantiate() as GameFlow
	_flow.suppress_quit = true
	add_child(_flow)
	_flow.start_new_game(12345)
	var landed := await _until(
		func() -> bool: return _flow.world() != null and not _flow.world().spawner.is_parked()
	)
	assert_bool(landed).is_true()
	_flow.world().animal.get_node("%PlayerInput").set_physics_process(false)
	_flow.world().exploration.reveal_now()
	return _flow


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame


func test_m_opens_the_map_paused_and_draws_it_on_a_worker() -> void:
	var flow := await _playing()
	var map := flow.map_screen()
	await _press(&"map")
	assert_bool(map.visible).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_bool(map.is_rendering() or map.image() != null).is_true()
	map.finish_render_now()
	assert_bool(map.is_rendering()).is_false()
	assert_int(map.image().get_width()).is_equal(SETTINGS.image_size)
	assert_str(map.status_text()).contains("1000 m")
	# The player is at the centre, and around them it is explored, not fog.
	var at := GameState.absolute_position(flow.world().animal.global_position)
	var centre := map.pixel_of(at.x, at.z)
	assert_vector(centre).is_equal_approx(Vector2.ONE * SETTINGS.image_size * 0.5, Vector2.ONE)
	var here := map.image().get_pixel(int(centre.x), int(centre.y))
	assert_bool(here.is_equal_approx(SETTINGS.fog_color)).is_false()
	var corner := map.image().get_pixel(0, 0)
	assert_int(corner.to_rgba32()).is_equal(Color(SETTINGS.fog_color, 1.0).to_rgba32())
	await _press(&"map")
	assert_bool(map.visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_esc_closes_the_map_without_opening_the_pause_menu() -> void:
	var flow := await _playing()
	await _press(&"map")
	await _press(&"pause")
	assert_bool(flow.map_screen().visible).is_false()
	assert_bool(flow.pause_menu().visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_the_wheel_zooms_out_and_in() -> void:
	var flow := await _playing()
	var map := flow.map_screen()
	await _press(&"map")
	map.finish_render_now()
	await _press(&"camera_zoom_out")
	assert_float(map.span()).is_equal(SETTINGS.spans[1])
	map.finish_render_now()
	assert_str(map.status_text()).contains("%d m" % roundi(SETTINGS.spans[1]))
	await _press(&"camera_zoom_out")
	await _press(&"camera_zoom_out")  # already the farthest
	assert_float(map.span()).is_equal(SETTINGS.spans[SETTINGS.spans.size() - 1])
	await _press(&"camera_zoom_in")
	assert_float(map.span()).is_equal(SETTINGS.spans[SETTINGS.spans.size() - 2])


func test_opens_from_the_pause_menu() -> void:
	var flow := await _playing()
	flow.pause_menu().open()
	flow.pause_menu().button("Map").pressed.emit()
	assert_bool(flow.pause_menu().visible).is_false()
	assert_bool(flow.map_screen().visible).is_true()
	assert_bool(get_tree().paused).is_true()


func test_the_arrow_points_where_the_animal_faces() -> void:
	var flow := await _playing()
	var map := flow.map_screen()
	flow.world().animal.rotation.y = 0.0
	assert_vector(map.player_direction()).is_equal_approx(Vector2(0, -1), Vector2.ONE * 1e-5)
	flow.world().animal.rotation.y = PI / 2.0  # facing −X: west, left on the map
	assert_vector(map.player_direction()).is_equal_approx(Vector2(-1, 0), Vector2.ONE * 1e-5)


func test_no_map_in_the_main_menu() -> void:
	_flow = load(MAIN_SCENE).instantiate() as GameFlow
	_flow.suppress_quit = true
	add_child(_flow)
	await _press(&"map")
	assert_bool(_flow.map_screen().visible).is_false()


func test_the_map_key_is_remappable() -> void:
	assert_bool(Settings.REMAPPABLE.has(&"map")).is_true()
	assert_str(Settings.binding_text(&"map")).is_equal("M")
	assert_bool(SettingsMenu.ACTION_NAMES.has(&"map")).is_true()


func test_explored_hamlets_show_on_the_map() -> void:
	var flow := await _playing()
	var map := flow.map_screen()
	var at := GameState.absolute_position(flow.world().animal.global_position)
	var hamlets := flow.world().hamlets.hamlets_near(at, 700.0)
	assert_int(hamlets.size()).is_greater(0)  # the meadow near the start has one
	var centre := hamlets[0].centre
	map.open()
	assert_bool(map.hamlet_marks().has(centre)).is_false()  # not seen yet: not on the map
	flow.world().exploration.explored.reveal(centre, EXPLORATION.reveal_radius)
	assert_bool(map.hamlet_marks().has(centre)).is_true()
	map.close()
