## Tests for the Phase 11 transitions: menus fade in (also while paused), the landing signal,
## and the subtle camera shake on hard landings that the player can turn off.
extends GdUnitTestSuite

const RIG_SCENE: String = "res://scenes/player/camera_rig.tscn"
const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"


func after_test() -> void:
	get_tree().paused = false
	Settings.set_camera_shake(true)


func test_the_pause_menu_fades_in_while_paused() -> void:
	var menu: PauseMenu = auto_free(PauseMenu.new())
	add_child(menu)
	menu.open()
	var root := menu.get_child(0) as Control
	assert_bool(get_tree().paused).is_true()
	assert_float(root.modulate.a).is_less(0.5)  # starts transparent
	await get_tree().create_timer(MenuStyle.FADE_SECONDS + 0.1, true).timeout
	assert_float(root.modulate.a).is_equal_approx(1.0, 0.01)
	menu.close()


func _floor() -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shape.shape = box
	body.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	add_child(body)


func test_a_fall_ends_with_a_landing_and_its_speed() -> void:
	_floor()
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	animal.position = Vector3(0, 4.0, 0)
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	var landings: Array[float] = []
	animal.movement.landed.connect(func(speed: float) -> void: landings.append(speed))
	for i in 120:
		await get_tree().physics_frame
	assert_array(landings).has_size(1)
	assert_float(landings[0]).is_between(6.0, 10.0)  # √(2·g·4 m) ≈ 8.9 m/s


func _rig() -> CameraRig:
	var target: Node3D = auto_free(Node3D.new())
	add_child(target)
	var rig: CameraRig = auto_free(load(RIG_SCENE).instantiate())
	rig.target = target
	add_child(rig)
	return rig


func test_a_hard_landing_shakes_the_camera_briefly() -> void:
	var rig := _rig()
	rig.on_landed(rig.settings.shake_max_fall)
	assert_float(rig.trauma()).is_equal(1.0)
	var moved := 0.0
	for i in 5:
		await get_tree().process_frame
		moved = maxf(moved, absf(rig.camera.h_offset) + absf(rig.camera.v_offset))
	assert_float(moved).is_greater(0.0)
	assert_float(moved).is_less_equal(rig.settings.shake_offset * 2.0 + 1e-4)  # subtle
	await get_tree().create_timer(rig.settings.shake_duration + 0.2).timeout
	assert_float(rig.trauma()).is_equal(0.0)
	assert_float(rig.camera.h_offset).is_equal(0.0)
	assert_float(rig.camera.rotation.z).is_equal(0.0)


func test_soft_landings_and_the_setting_do_not_shake() -> void:
	var rig := _rig()
	rig.on_landed(rig.settings.shake_min_fall - 1.0)  # an ordinary hop
	assert_float(rig.trauma()).is_equal(0.0)
	Settings.set_camera_shake(false)
	rig.on_landed(rig.settings.shake_max_fall)
	assert_float(rig.trauma()).is_equal(0.0)


func test_the_shake_can_be_turned_off_in_the_settings_menu() -> void:
	var menu: SettingsMenu = auto_free(SettingsMenu.new())
	add_child(menu)
	menu.open()
	var box := menu.control("CameraShake") as CheckBox
	assert_bool(box.button_pressed).is_true()
	box.button_pressed = false
	assert_bool(Settings.camera_shake).is_false()
	menu.visible = false
