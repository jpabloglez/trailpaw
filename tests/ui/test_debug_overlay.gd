## Tests for the F3 [DebugOverlay].
extends GdUnitTestSuite

const OVERLAY_SCENE: String = "res://scenes/ui/debug_overlay.tscn"
const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"

var _overlay: DebugOverlay


func before_test() -> void:
	_overlay = auto_free(load(OVERLAY_SCENE).instantiate())
	add_child(_overlay)


func _toggle_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"toggle_debug_overlay"
	event.pressed = true
	return event


func test_hidden_by_default() -> void:
	assert_bool(_overlay.visible).is_false()


func test_toggle_action_shows_and_hides() -> void:
	_overlay._unhandled_input(_toggle_event())
	assert_bool(_overlay.visible).is_true()
	_overlay._unhandled_input(_toggle_event())
	assert_bool(_overlay.visible).is_false()


func test_format_with_player_info() -> void:
	var info := {
		"speed": 4.0,
		"gait": "TROT",
		"state": &"Locomotion",
		"position": Vector3(1.26, 0.0, -3.54),
		"grounded": true,
	}
	var text := DebugOverlay.format_info(59.6, info)
	assert_str(text).contains("FPS 60")
	assert_str(text).contains("speed 4.00 m/s  (TROT)")
	assert_str(text).contains("state Locomotion")
	assert_str(text).not_contains("(air)")
	assert_str(text).contains("pos 1.3, 0.0, -3.5")


func test_format_marks_airborne() -> void:
	var text := DebugOverlay.format_info(60.0, {"state": &"Fall", "grounded": false})
	assert_str(text).contains("state Fall  (air)")


func test_without_player_shows_fps_only() -> void:
	_overlay.toggle()
	assert_str(_overlay.text()).starts_with("FPS ")
	assert_str(_overlay.text()).contains("no player")


func test_reads_player_through_group() -> void:
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	add_child(animal)
	_overlay.toggle()
	assert_str(_overlay.text()).contains("state ")
	assert_str(_overlay.text()).not_contains("no player")
