## Tests for [BiomeTracker]: initial announcement, crossings and hysteresis.
extends GdUnitTestSuite

const SETTINGS_PATH: String = "res://data/world/terrain_settings.tres"
const SEED: int = 12345

var _settings: TerrainSettings
var _tracker: BiomeTracker
var _target: Node3D
var _events: Array[StringName] = []
var _listener: Callable


func before_test() -> void:
	_settings = load(SETTINGS_PATH)
	GameState.world_seed = SEED
	GameState.current_biome = &""
	_target = auto_free(Node3D.new())
	add_child(_target)
	_tracker = auto_free(BiomeTracker.new())
	_tracker.terrain = _settings
	_tracker.target = _target
	_tracker.set_process(false)  # ticks are driven by sample_now()
	add_child(_tracker)
	_events = []
	_listener = func(id: StringName, _name: String) -> void: _events.append(id)
	EventBus.biome_entered.connect(_listener)


func after_test() -> void:
	EventBus.biome_entered.disconnect(_listener)
	GameState.current_biome = &""
	GameState.world_seed = 0


## First point along +X (step 1 m) whose weight for [param id] reaches [param weight].
func _x_where(id: StringName, weight: float, from: float) -> float:
	var resolver := BiomeResolver.new(_settings.biomes, SEED)
	var x := from
	while resolver.weights_at(x, 0.0).get(id, 0.0) < weight:
		x += 1.0
	return x


func test_announces_the_starting_biome_once() -> void:
	assert_str(String(_tracker.sample_now())).is_equal("meadow")
	_tracker.sample_now()
	assert_array(_events).contains_exactly([&"meadow"])
	assert_str(String(GameState.current_biome)).is_equal("meadow")


func test_crossing_into_the_next_band_announces_it() -> void:
	_tracker.sample_now()
	_target.position.x = _x_where(&"forest", 1.0, 500.0) + 50.0
	_tracker.sample_now()
	assert_array(_events).contains_exactly([&"meadow", &"forest"])
	assert_str(String(GameState.current_biome)).is_equal("forest")


func test_wandering_along_a_boundary_does_not_flicker() -> void:
	_tracker.sample_now()
	# Points where forest weighs just over 0.5 but below the 0.6 threshold, and back.
	var over_half := _x_where(&"forest", 0.52, 500.0)
	var under_half := over_half - 6.0
	for i in 20:
		_target.position.x = over_half if i % 2 == 0 else under_half
		_tracker.sample_now()
	assert_array(_events).contains_exactly([&"meadow"])


func test_hysteresis_threshold_is_above_half() -> void:
	assert_float(BiomeTracker.ENTER_WEIGHT).is_greater(0.5)


func test_display_name_is_sent_with_the_event() -> void:
	var names: Array[String] = []
	var capture := func(_id: StringName, display_name: String) -> void: names.append(display_name)
	EventBus.biome_entered.connect(capture)
	_tracker.sample_now()
	EventBus.biome_entered.disconnect(capture)
	assert_array(names).contains_exactly(["Meadow"])


func test_debug_line_shows_current_biome_and_weights() -> void:
	_tracker.sample_now()
	assert_str(_tracker.get_debug_lines()[0]).contains("biome meadow")
	assert_str(_tracker.get_debug_lines()[0]).contains("meadow 1.00")
