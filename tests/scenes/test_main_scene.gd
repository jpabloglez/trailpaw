## Verifies the main scene is configured: the game flow (menus) over the world scene
## (ARCHITECTURE §2).
extends GdUnitTestSuite

const MAIN_SCENE_PATH: String = "res://scenes/main/main.tscn"


func test_main_scene_is_project_entry_point() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	assert_str(main_scene).is_equal(MAIN_SCENE_PATH)


func test_main_scene_root_layout() -> void:
	var main: Node = auto_free(load(MAIN_SCENE_PATH).instantiate())
	assert_str(main.name).is_equal("Main")
	assert_object(main).is_instanceof(GameFlow)
	var world_scene: PackedScene = (main as GameFlow).world_scene
	assert_str(world_scene.resource_path).is_equal("res://scenes/main/world.tscn")
