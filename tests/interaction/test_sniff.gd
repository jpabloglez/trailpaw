## Tests for sniffing ([Sniffer]): which food lights up, the cap, expiry, cooldown, the water
## hint and the trail towards water scented far away.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const SETTINGS: SniffSettings = preload("res://data/interaction/sniff.tres")
const BERRIES: InteractionDefinition = preload("res://data/interactions/berries.tres")
const GRASS: InteractionDefinition = preload("res://data/interactions/grass.tres")
const DEN: InteractionDefinition = preload("res://data/interactions/den.tres")

var _saved_water: float
var _saved_seed: int


func before_test() -> void:
	_saved_water = GameState.water_level
	_saved_seed = GameState.world_seed
	GameState.water_level = -INF


func after_test() -> void:
	GameState.water_level = _saved_water
	GameState.world_seed = _saved_seed


func _slab(center_z: float, depth: float, top: float) -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, depth)
	shape.shape = box
	shape.position = Vector3(0, top - 0.5, center_z)
	body.add_child(shape)
	add_child(body)


func _animal(at: Vector3 = Vector3(0, 0.05, 0)) -> Animal:
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	animal.position = at
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	return animal


func _item(definition: InteractionDefinition, at: Vector3) -> Interactable:
	var node: Interactable = auto_free(Interactable.new())
	node.definition = definition
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	node.add_child(shape)
	node.position = at
	add_child(node)
	return node


func _sniffer(animal: Animal) -> Sniffer:
	var sniffer := animal.get_node("%Sniffer") as Sniffer
	sniffer.set_process(false)  # driven by hand
	return sniffer


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_highlights_available_food_in_the_diet_within_the_radius_nearest_first() -> void:
	_slab(0.0, 120.0, 0.0)
	var animal := _animal()
	_item(BERRIES, Vector3(0, 0.3, -10))
	_item(BERRIES, Vector3(3, 0.3, 0))
	_item(BERRIES, Vector3(0, 0.3, 30))  # beyond the radius
	_item(GRASS, Vector3(-4, 0.3, 0))  # the fox does not graze
	_item(DEN, Vector3(0, 0.3, 5))  # not food
	var eaten := _item(BERRIES, Vector3(-2, 0.3, 2))
	eaten.available = false
	await _frames(10)
	var sniffer := _sniffer(animal)
	sniffer.sniff_now()
	var lit := sniffer.highlights()
	assert_int(lit.size()).is_equal(2)
	assert_float(lit[0].x).is_equal_approx(3.0, 0.01)  # nearest first
	assert_float(lit[1].z).is_equal_approx(-10.0, 0.01)
	assert_float(lit[0].y).is_equal_approx(0.3 + SETTINGS.lift, 0.01)
	# Far sparkles are drawn bigger so they stay legible.
	var markers := sniffer.get_children().filter(func(n: Node) -> bool: return n.visible)
	assert_float((markers[1] as Node3D).scale.x).is_greater((markers[0] as Node3D).scale.x)


func test_at_most_the_configured_number() -> void:
	_slab(0.0, 120.0, 0.0)
	var animal := _animal()
	for i in SETTINGS.max_highlights + 8:
		_item(BERRIES, Vector3(cos(i * 0.7) * (2.0 + i * 0.5), 0.3, sin(i * 0.7) * (2.0 + i * 0.5)))
	await _frames(10)
	var sniffer := _sniffer(animal)
	sniffer.sniff_now()
	assert_int(sniffer.highlights().size()).is_equal(SETTINGS.max_highlights)


func test_highlights_fade_out_and_expire() -> void:
	_slab(0.0, 120.0, 0.0)
	var animal := _animal()
	_item(BERRIES, Vector3(3, 0.3, 0))
	await _frames(10)
	var sniffer := _sniffer(animal)
	sniffer.sniff_now()
	sniffer._process(SETTINGS.duration - 0.1)
	assert_int(sniffer.highlights().size()).is_equal(1)
	sniffer._process(0.2)
	assert_int(sniffer.highlights().size()).is_equal(0)


func test_cooldown_between_sniffs() -> void:
	_slab(0.0, 120.0, 0.0)
	var animal := _animal()
	await _frames(10)
	var sniffer := _sniffer(animal)
	assert_bool(sniffer.request_sniff()).is_true()
	assert_bool(sniffer.request_sniff()).is_false()
	sniffer._process(SETTINGS.cooldown + 0.05)
	assert_bool(sniffer.request_sniff()).is_true()


func test_points_to_the_nearest_water() -> void:
	_slab(20.0, 40.0, 0.0)  # land for z > 0
	_slab(-20.0, 40.0, -1.0)  # a lake for z < 0
	GameState.water_level = -0.1
	var animal := _animal(Vector3(0, 0.05, 5))
	await _frames(20)
	var sniffer := _sniffer(animal)
	sniffer.sniff_now()
	var hint := sniffer.water_hint()
	assert_bool(hint == Vector3.INF).is_false()
	assert_float(hint.z).is_less(0.0)
	assert_float(hint.y).is_equal_approx(-0.1, 1e-4)
	assert_float(Vector2(hint.x, hint.z - 5.0).length()).is_less_equal(SETTINGS.radius + 0.01)
	var lit := sniffer.highlights()
	assert_float(lit[lit.size() - 1].z).is_less(0.0)  # the water sparkle is shown last


func test_no_water_hint_on_dry_land() -> void:
	_slab(0.0, 120.0, 0.0)
	GameState.water_level = -0.1
	var animal := _animal()
	await _frames(10)
	var sniffer := _sniffer(animal)
	sniffer.sniff_now()
	assert_bool(sniffer.water_hint() == Vector3.INF).is_true()


func _alpha(sniffer: Sniffer, index: int) -> float:
	var markers := sniffer.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D)
	var material := (markers[index] as MeshInstance3D).material_override as ShaderMaterial
	return material.get_shader_parameter(&"alpha")


func test_far_water_is_scented_and_shown_as_a_trail() -> void:
	_slab(0.0, 120.0, 0.0)  # dry land here; the real terrain has a lake ≈ 770 m away
	GameState.world_seed = 12345
	GameState.water_level = -6.0
	var animal := _animal()
	await _frames(10)
	var sniffer := _sniffer(animal)
	var scented: Array[Vector3] = []
	sniffer.water_scented.connect(func(at: Vector3) -> void: scented.append(at))
	sniffer.sniff_now()
	assert_bool(sniffer.is_scenting()).is_true()  # on a worker, not blocking the sniff
	sniffer.finish_scent_now()
	assert_bool(sniffer.is_scenting()).is_false()
	var hint := sniffer.water_hint()
	var to_water := Vector2(hint.x, hint.z)
	assert_float(to_water.length()).is_greater(SETTINGS.scent_radius * 0.3)
	assert_int(scented.size()).is_equal(1)
	assert_that(GameState.local_position(scented[0])).is_equal(hint)
	var trail := sniffer.highlights()
	assert_int(trail.size()).is_equal(SETTINGS.trail_count)
	for k in trail.size():
		var flat := Vector2(trail[k].x, trail[k].z)
		assert_float(flat.length()).is_equal_approx(SETTINGS.trail_spacing * (k + 1), 0.01)
		assert_float(flat.normalized().dot(to_water.normalized())).is_greater(0.999)
		assert_float(trail[k].y).is_equal_approx(SETTINGS.lift, 0.01)  # on the ground
	# The sparkles appear one after another, then fade out together.
	sniffer._process(SETTINGS.trail_stagger * 1.5)
	assert_float(_alpha(sniffer, 0)).is_equal(1.0)
	assert_float(_alpha(sniffer, SETTINGS.trail_count - 1)).is_equal(0.0)
	sniffer._process(SETTINGS.trail_stagger * SETTINGS.trail_count)
	assert_float(_alpha(sniffer, SETTINGS.trail_count - 1)).is_equal(1.0)
	sniffer._process(SETTINGS.duration)
	assert_int(sniffer.highlights().size()).is_equal(0)


func test_water_nearby_needs_no_scent() -> void:
	_slab(20.0, 40.0, 0.0)
	_slab(-20.0, 40.0, -1.0)
	GameState.water_level = -0.1
	var animal := _animal(Vector3(0, 0.05, 5))
	await _frames(20)
	var sniffer := _sniffer(animal)
	sniffer.sniff_now()
	assert_bool(sniffer.is_scenting()).is_false()


func test_no_scent_without_terrain_or_water() -> void:
	_slab(0.0, 120.0, 0.0)
	var animal := _animal()
	await _frames(10)
	var sniffer := _sniffer(animal)
	sniffer.sniff_now()  # GameState.water_level is -INF: a world without water
	assert_bool(sniffer.is_scenting()).is_false()
	GameState.water_level = -6.0
	sniffer.terrain = null
	sniffer.sniff_now()
	assert_bool(sniffer.is_scenting()).is_false()
