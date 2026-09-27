## Verifies the main scene is configured and has the root layout from ARCHITECTURE §2.
extends GdUnitTestSuite

const MAIN_SCENE_PATH: String = "res://scenes/main/main.tscn"


func test_main_scene_is_project_entry_point() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	assert_str(main_scene).is_equal(MAIN_SCENE_PATH)


func test_main_scene_root_layout() -> void:
	var main: Node = auto_free(load(MAIN_SCENE_PATH).instantiate())
	assert_str(main.name).is_equal("Main")
	assert_object(main.get_node_or_null("World")).is_instanceof(Node3D)
	assert_object(main.get_node_or_null("UI")).is_instanceof(CanvasLayer)
