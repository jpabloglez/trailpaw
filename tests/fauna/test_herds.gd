## Tests for herds ([FaunaHerd]): members wander around the group's centre instead of drifting
## apart, strays head back, fleeing spreads through the herd, and herds spawn whole.
extends GdUnitTestSuite

const SETTINGS: FaunaSettings = preload("res://data/fauna/director.tres")
const AGENT_SCENE: String = "res://scenes/fauna/fauna_agent.tscn"
const DEER: String = "res://data/fauna/deer.tres"

var _saved_water: float


func before_test() -> void:
	_saved_water = GameState.water_level
	GameState.water_level = -INF


func after_test() -> void:
	GameState.water_level = _saved_water


func _floor() -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	add_child(body)


func _herd(at: Array[Vector3]) -> FaunaHerd:
	var herd := FaunaHerd.new()
	herd.leash = SETTINGS.herd_leash
	herd.alarm_radius = SETTINGS.alarm_radius
	herd.alarm_seconds = SETTINGS.alarm_seconds
	for i in at.size():
		var agent: FaunaAgent = auto_free(load(AGENT_SCENE).instantiate())
		agent.fauna = load(DEER)
		agent.decision_seed = 100 + i
		agent.position = at[i]
		herd.add(agent)
		add_child(agent)
	return herd


func _spread(herd: FaunaHerd) -> float:
	var centre := herd.centroid()
	var most := 0.0
	for member in herd.members:
		most = maxf(most, member.horizontal_distance_to(centre))
	return most


func test_wander_targets_stay_around_the_herd() -> void:
	_floor()
	var herd := _herd([Vector3(0, 0.1, 0), Vector3(30, 0.1, 0), Vector3(15, 0.1, 20)])
	await get_tree().physics_frame
	var lone := herd.members[1]
	var wander := lone.state_machine.get_state(FaunaDecision.WANDER) as FaunaWanderState
	for i in 20:
		wander.pick_target()
		var radius: float = lone.fauna.wander_radius
		(
			assert_float(
				Vector2(wander.target().x, wander.target().z).distance_to(
					Vector2(herd.centroid().x, herd.centroid().z)
				)
			)
			. is_less_equal(radius + 0.01)
		)


func test_a_stray_heads_back_to_the_herd() -> void:
	_floor()
	var herd := _herd([Vector3(0, 0.1, 0), Vector3(2, 0.1, 1), Vector3(40, 0.1, 0)])
	var stray := herd.members[2]
	assert_bool(stray.strayed()).is_true()
	var before := stray.horizontal_distance_to(herd.centroid())
	stray.state_machine.transition_to(FaunaDecision.WANDER)
	for i in 240:
		await get_tree().physics_frame
	assert_float(stray.horizontal_distance_to(herd.centroid())).is_less(before - 5.0)


func test_a_herd_stays_together_over_time() -> void:
	_floor()
	var herd := _herd(
		[Vector3(0, 0.1, 0), Vector3(6, 0.1, 3), Vector3(-4, 0.1, 5), Vector3(3, 0.1, -6)]
	)
	for i in 60 * 30:  # 30 s of wandering, grazing and resting
		await get_tree().physics_frame
	assert_float(_spread(herd)).is_less_equal(herd.leash + 6.0)


func test_when_one_flees_the_herd_flees() -> void:
	_floor()
	var herd := _herd(
		[Vector3(0, 0.1, 0), Vector3(4, 0.1, 2), Vector3(-3, 0.1, 4), Vector3(60, 0.1, 0)]
	)
	await get_tree().physics_frame
	var scared := herd.members[0]
	var alarmed := herd.alarm(scared)
	assert_int(alarmed).is_equal(2)  # the far one (60 m away) keeps grazing
	assert_bool(herd.members[1].brain.is_alarmed()).is_true()
	assert_bool(herd.members[3].brain.is_alarmed()).is_false()
	herd.members[1].brain.tick(0.2)
	assert_str(String(herd.members[1].state_machine.current_state_name())).is_equal("Flee")


func test_a_herd_leaves_with_its_members() -> void:
	_floor()
	var herd := _herd([Vector3(0, 0.1, 0), Vector3(4, 0.1, 2)])
	await get_tree().physics_frame
	herd.members[0].queue_free()
	await get_tree().process_frame
	assert_int(herd.size()).is_equal(1)
	assert_bool(herd.members[0].strayed()).is_false()  # alone: no leash
