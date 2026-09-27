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
