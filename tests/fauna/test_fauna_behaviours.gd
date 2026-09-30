## Scene tests for fauna behaviours with the [FaunaBrain]: fleeing, following, avoiding water
## and taking turns between idle behaviours.
extends GdUnitTestSuite

const AGENT_SCENE: String = "res://scenes/fauna/fauna_agent.tscn"
const FOX: String = "res://data/species/fox.tres"

var _saved_water: float


func before_test() -> void:
	_saved_water = GameState.water_level


func after_test() -> void:
	GameState.water_level = _saved_water


func _slab(center: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape)
	add_child(body)


func _floor() -> void:
	_slab(Vector3(0, -0.5, 0), Vector3(200, 1, 200))


func _agent(at: Vector3, profile: FaunaProfile = null) -> FaunaAgent:
	var agent: FaunaAgent = auto_free(load(AGENT_SCENE).instantiate())
	agent.species = load(FOX)
	agent.decision_seed = 3
	agent.position = at
	add_child(agent)
	if profile != null:
		agent.brain.profile = profile
	return agent


func _player(at: Vector3) -> Node3D:
	var player: Node3D = auto_free(Node3D.new())
	player.position = at
	add_child(player)
	player.add_to_group(Animal.PLAYER_GROUP)
	return player


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _state(agent: FaunaAgent) -> String:
	return String(agent.state_machine.current_state_name())


func test_flees_from_a_rushing_player_and_gains_distance() -> void:
	_floor()
	var agent := _agent(Vector3(0, 0.1, 0))
	var player := _player(Vector3(0, 0, 9))
	await _frames(10)
	for i in 30:  # the player rushes in at 6 m/s for half a second
		player.position.z -= 0.1
		await get_tree().physics_frame
	await _frames(10)
	assert_str(_state(agent)).is_equal("Flee")
	var start := agent.horizontal_distance_to(player.global_position)
	await _frames(120)
	assert_float(agent.horizontal_distance_to(player.global_position)).is_greater(start + 2.0)


func test_a_calm_profile_ignores_a_slow_walk_past() -> void:
	_floor()
	var calm := FaunaProfile.new()  # never flees, never approaches
	var agent := _agent(Vector3(0, 0.1, 0), calm)
	var player := _player(Vector3(0, 0, 9))
	await _frames(10)
	for i in 60:
		player.position.z -= 0.02  # 1.2 m/s
		await get_tree().physics_frame
	assert_str(_state(agent)).is_not_equal("Flee")


func test_never_walks_into_water() -> void:
	_slab(Vector3(-20, -0.5, 0), Vector3(50, 1, 60))  # land for x < 5
	_slab(Vector3(30, -1.5, 0), Vector3(50, 1, 60))  # lake bed for x > 5
	GameState.water_level = -0.1
	var calm := FaunaProfile.new()
	calm.idle_weights = Vector3(1, 0, 0)
	var agent := _agent(Vector3(1, 0.1, 0), calm)
	await _frames(5)
	var wander := agent.state_machine.get_state(&"Wander") as FaunaWanderState
	wander.set_target(Vector3(15, 0, 0))
	var furthest := -INF
	for i in 300:
		await get_tree().physics_frame
		furthest = maxf(furthest, agent.global_position.x)
	assert_float(furthest).is_less(5.0)


func test_follows_at_a_distance_then_stops_following() -> void:
	_floor()
	var agent := _agent(Vector3(0, 0.1, 0), FaunaProfile.new())
	var player := _player(Vector3(0, 0, -8))
	await _frames(10)
	agent.brain.start_follow(4.0)
	assert_str(_state(agent)).is_equal("Follow")
	await _frames(150)
	var distance := agent.horizontal_distance_to(player.global_position)
	assert_float(distance).is_between(1.0, agent.brain.profile.follow_distance + 2.0)
	await get_tree().create_timer(2.0).timeout
	assert_str(_state(agent)).is_not_equal("Follow")


func test_takes_turns_between_idle_behaviours() -> void:
	_floor()
	var busy := FaunaProfile.new()
	busy.graze_time = Vector2(0.3, 0.3)
	busy.rest_time = Vector2(0.3, 0.3)
	busy.idle_weights = Vector3(0, 1, 1)  # graze and rest only
	var agent := _agent(Vector3(0, 0.1, 0), busy)
	await _frames(2)
	agent.state_machine.transition_to(&"Graze")  # skip the initial wander
	var seen := {}
	for i in 240:
		await get_tree().physics_frame
		seen[_state(agent)] = true
	assert_bool(seen.has("Graze")).is_true()
	assert_bool(seen.has("Rest")).is_true()
