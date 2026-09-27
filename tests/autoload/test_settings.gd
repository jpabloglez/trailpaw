## Smoke test: the [code]Settings[/code] autoload is registered and uses its script.
extends GdUnitTestSuite

const SCRIPT_PATH: String = "res://scripts/autoload/settings.gd"


func test_autoload_is_registered() -> void:
	var node: Node = get_tree().root.get_node_or_null("Settings")
	assert_object(node).is_not_null()
	assert_str(node.get_script().resource_path).is_equal(SCRIPT_PATH)
