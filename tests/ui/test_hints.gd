## Tests for the onboarding hints ([HintDirector], [HintProgress]): one short hint at a time, with
## the player's keys, shown when useful, gone once done, remembered across games, and off when
## the player turns them off.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const SETTINGS: HintSettings = preload("res://data/ui/hints.tres")
const TEST_PATH: String = "user://test_hint_settings.cfg"

var _saved_path: String
var _saved_enabled: bool
var _saved_done: Array[StringName]


func before_test() -> void:
	_saved_path = Settings.config_path
	_saved_enabled = Settings.hints.enabled
	_saved_done = Settings.hints.done()
	Settings.config_path = TEST_PATH
	Settings.hints.reset()
	Settings.hints.enabled = true


func after_test() -> void:
	Settings.hints.reset()
	for id in _saved_done:
		Settings.hints.mark(id)
	Settings.hints.enabled = _saved_enabled
	Settings.set_sprint_toggle(false)
	Settings.config_path = _saved_path
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _director() -> HintDirector:
	var floor_body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	floor_body.position = Vector3(0, -0.5, 0)
	floor_body.add_child(shape)
	add_child(floor_body)
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	var hints: HintDirector = auto_free(HintDirector.new())
	hints.settings = SETTINGS
	hints.body = animal
	hints.movement = animal.movement
	hints.needs = animal.get_node("%NeedsComponent") as NeedsComponent
	hints.sniffer = animal.get_node("%Sniffer") as Sniffer
	hints.state_machine = animal.state_machine
	add_child(hints)
	return hints


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func test_the_first_hint_teaches_moving_with_the_players_keys() -> void:
	var hints := _director()
	assert_str(String(hints.current())).is_empty()  # not straight away
	await _wait(SETTINGS.first_delay + 0.4)
	assert_str(String(hints.current())).is_equal("move")
	assert_str(hints.text_for(&"move")).is_equal("WASD to explore")
	await _wait(0.4)
	assert_float(hints.opacity()).is_greater(0.5)


func test_walking_completes_moving_and_running_comes_next() -> void:
	var hints := _director()
	await _wait(SETTINGS.first_delay + 0.4)
	hints.body.global_position += Vector3(SETTINGS.move_distance + 1.0, 0, 0)
	await _wait(0.4)
	assert_bool(Settings.hints.is_done(&"move")).is_true()
	assert_str(String(hints.current())).is_equal("run")
	assert_str(hints.text_for(&"run")).is_equal("Hold Shift to run")
	Settings.set_sprint_toggle(true)
	assert_str(hints.text_for(&"run")).is_equal("Press Shift to run")


func test_sniffing_is_suggested_when_thirsty_and_learnt_by_sniffing() -> void:
	var hints := _director()
	for id: StringName in [&"move", &"run"]:
		Settings.hints.mark(id)
	await _wait(SETTINGS.first_delay + 0.4)
	assert_str(String(hints.current())).is_empty()  # not thirsty yet
	hints.needs.set_value(&"thirst", SETTINGS.sniff_below - 10.0)
	await _wait(0.4)
	assert_str(String(hints.current())).is_equal("sniff")
	assert_str(hints.text_for(&"sniff")).contains("Q to sniff")
	hints.sniffer.sniffed.emit(0)
	assert_bool(Settings.hints.is_done(&"sniff")).is_true()


func test_scented_water_leads_to_the_trail_then_the_map() -> void:
	var hints := _director()
	for id: StringName in [&"move", &"run", &"sniff"]:
		Settings.hints.mark(id)
	hints.needs.set_value(&"thirst", 40.0)
	await _wait(SETTINGS.first_delay + 0.2)
	hints.sniffer.water_scented.emit(Vector3(250, -6, -700))
	await _wait(0.4)
	assert_str(String(hints.current())).is_equal("water")
	EventBus.interaction_performed.emit(InteractionDefinition.Type.DRINK, &"drink")
	await _wait(0.4)
	assert_str(String(hints.current())).is_equal("map")  # water was scented: show the map
	EventBus.map_opened.emit()
	assert_bool(Settings.hints.is_done(&"map")).is_true()


func test_resting_is_suggested_when_tired_and_learnt_by_resting() -> void:
	var hints := _director()
	for id: StringName in HintDirector.ORDER:
		if id != &"rest":
			Settings.hints.mark(id)
	hints.needs.set_value(&"energy", SETTINGS.rest_below - 10.0)
	await _wait(SETTINGS.first_delay + 0.4)
	assert_str(String(hints.current())).is_equal("rest")
	hints.state_machine.state_changed.emit(&"Idle", &"Rest")
	assert_bool(Settings.hints.is_done(&"rest")).is_true()


func test_learnt_hints_are_remembered_across_games() -> void:
	var hints := _director()
	await _wait(SETTINGS.first_delay + 0.4)
	hints.body.global_position += Vector3(SETTINGS.move_distance + 1.0, 0, 0)
	await _wait(0.4)  # learnt → saved
	Settings.hints.reset()
	Settings.load_settings()
	assert_bool(Settings.hints.is_done(&"move")).is_true()


func test_no_hints_when_turned_off() -> void:
	Settings.hints.enabled = false
	var hints := _director()
	await _wait(SETTINGS.first_delay + 0.6)
	assert_str(String(hints.current())).is_empty()
	assert_float(hints.opacity()).is_equal(0.0)


func test_every_hint_has_a_short_text() -> void:
	for id in HintDirector.ORDER:
		var text: String = SETTINGS.texts.get(id, "")
		assert_str(text).override_failure_message(String(id)).is_not_empty()
		assert_int(text.length()).override_failure_message(String(id)).is_less(60)


func test_the_journal_is_suggested_once_an_animal_is_met() -> void:
	var hints := _director()
	for id: StringName in HintDirector.ORDER:
		if id != &"journal":
			Settings.hints.mark(id)
	await _wait(SETTINGS.first_delay + 0.4)
	assert_str(String(hints.current())).is_equal("")  # nothing met yet: nothing to see there
	EventBus.animal_discovered.emit(&"rabbit")
	await _wait(0.4)
	assert_str(String(hints.current())).is_equal("journal")
	assert_str(hints.text_for(&"journal")).is_equal("J to open your journal")
	EventBus.journal_opened.emit()
	assert_bool(Settings.hints.is_done(&"journal")).is_true()


func test_hamlet_food_is_hinted_once_seen_and_learnt_by_eating_it() -> void:
	var hints := _director()
	for id: StringName in HintDirector.ORDER:
		if id != &"hamlet_food":
			Settings.hints.mark(id)
	await _wait(SETTINGS.first_delay + 0.4)
	assert_str(String(hints.current())).is_equal("")
	EventBus.hamlet_food_seen.emit()
	await _wait(0.4)
	assert_str(String(hints.current())).is_equal("hamlet_food")
	assert_str(hints.text_for(&"hamlet_food")).contains("if nobody is looking")
	EventBus.interaction_performed.emit(InteractionDefinition.Type.EAT, &"berries")
	assert_bool(Settings.hints.is_done(&"hamlet_food")).is_false()  # berries don't count
	EventBus.interaction_performed.emit(InteractionDefinition.Type.EAT, &"eggs")
	assert_bool(Settings.hints.is_done(&"hamlet_food")).is_true()
