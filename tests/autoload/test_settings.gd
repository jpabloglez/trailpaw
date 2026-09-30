## Smoke test: the [code]Settings[/code] autoload is registered and uses its script.
extends GdUnitTestSuite

const SCRIPT_PATH: String = "res://scripts/autoload/settings.gd"


func test_autoload_is_registered() -> void:
	var node: Node = get_tree().root.get_node_or_null("Settings")
	assert_object(node).is_not_null()
	assert_str(node.get_script().resource_path).is_equal(SCRIPT_PATH)


func test_default_quality_is_medium() -> void:
	var settings: Node = get_tree().root.get_node("Settings")
	assert_str(String(settings.quality.id)).is_equal("medium")


func test_set_quality_emits_once_per_change() -> void:
	var settings: Node = get_tree().root.get_node("Settings")
	var original: QualityPreset = settings.quality
	var received: Array[StringName] = []
	var listener := func(preset: QualityPreset) -> void: received.append(preset.id)
	settings.quality_changed.connect(listener)
	var low: QualityPreset = load("res://data/quality/low.tres")
	settings.set_quality(low)
	settings.set_quality(low)  # no-op
	settings.set_quality(original)
	settings.quality_changed.disconnect(listener)
	assert_array(received).contains_exactly([&"low", &"medium"])


func test_audio_buses_exist_in_order_and_route_to_master() -> void:
	var settings: Node = get_tree().root.get_node("Settings")
	for i in settings.BUSES.size():
		assert_str(String(AudioServer.get_bus_name(i))).is_equal(String(settings.BUSES[i]))
		if i > 0:
			assert_str(String(AudioServer.get_bus_send(i))).is_equal("Master")


func test_set_volume_applies_decibels_and_mutes_at_zero() -> void:
	var settings: Node = get_tree().root.get_node("Settings")
	var index := AudioServer.get_bus_index(&"Ambience")
	var changes: Array = []
	var listener := func(bus: StringName, v: float) -> void: changes.append([bus, v])
	settings.volume_changed.connect(listener)
	settings.set_volume(&"Ambience", 0.5)
	assert_float(AudioServer.get_bus_volume_db(index)).is_equal_approx(linear_to_db(0.5), 1e-3)
	assert_bool(AudioServer.is_bus_mute(index)).is_false()
	settings.set_volume(&"Ambience", 0.0)
	assert_bool(AudioServer.is_bus_mute(index)).is_true()
	settings.set_volume(&"Ambience", 3.0)  # clamped
	assert_float(settings.volume(&"Ambience")).is_equal(1.0)
	assert_bool(AudioServer.is_bus_mute(index)).is_false()
	settings.volume_changed.disconnect(listener)
	assert_int(changes.size()).is_equal(3)
	assert_array(changes[0]).is_equal([&"Ambience", 0.5])
