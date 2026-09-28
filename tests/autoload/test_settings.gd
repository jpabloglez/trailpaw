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
