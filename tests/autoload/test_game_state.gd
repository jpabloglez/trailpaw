## Smoke test: the [code]GameState[/code] autoload is registered and uses its script.
extends GdUnitTestSuite

const SCRIPT_PATH: String = "res://scripts/autoload/game_state.gd"


func test_autoload_is_registered() -> void:
	var node: Node = get_tree().root.get_node_or_null("GameState")
	assert_object(node).is_not_null()
	assert_str(node.get_script().resource_path).is_equal(SCRIPT_PATH)


func test_world_seed_is_an_int_field() -> void:
	var state: Node = get_tree().root.get_node("GameState")
	assert_int(typeof(state.get("world_seed"))).is_equal(TYPE_INT)


func test_clock_starts_at_the_configured_time_and_advances_at_its_pace() -> void:
	var clock: ClockSettings = load("res://data/world/clock.tres")
	var saved_minutes: float = GameState.game_minutes
	var saved_scale: float = GameState.clock_scale
	GameState.game_minutes = clock.start_minutes
	GameState.clock_scale = 1.0
	GameState.advance_clock(10.0)
	assert_float(GameState.game_minutes).is_equal_approx(
		clock.start_minutes + 10.0 * clock.minutes_per_second, 1e-4
	)
	GameState.clock_scale = clock.rest_scale
	GameState.advance_clock(1.0)
	assert_float(GameState.game_minutes).is_equal_approx(
		clock.start_minutes + (10.0 + clock.rest_scale) * clock.minutes_per_second, 1e-4
	)
	GameState.game_minutes = saved_minutes
	GameState.clock_scale = saved_scale


func test_time_of_day_wraps_at_midnight() -> void:
	var saved: float = GameState.game_minutes
	GameState.game_minutes = 1440.0 * 2 + 90.0
	assert_float(GameState.time_of_day()).is_equal_approx(90.0, 1e-4)
	GameState.game_minutes = saved


func test_the_clock_runs_with_the_game() -> void:
	var before: float = GameState.game_minutes
	await get_tree().create_timer(0.3).timeout
	assert_float(GameState.game_minutes).is_greater(before)
