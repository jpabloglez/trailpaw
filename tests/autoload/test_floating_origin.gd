## Tests for the [code]FloatingOrigin[/code] autoload and [code]GameState[/code] origin API.
extends GdUnitTestSuite

const SCRIPT_PATH: String = "res://scripts/autoload/floating_origin.gd"
const CHUNK: float = 64.0

var _target: Node3D
var _other: Node3D


func before_test() -> void:
	FloatingOrigin.reset()
	FloatingOrigin.configure(CHUNK, 100.0)
	_target = _make_node(Vector3(250.0, 5.0, -130.0), true)
	_other = _make_node(Vector3(240.0, 8.0, -120.0), true)
	FloatingOrigin.track(_target)


func after_test() -> void:
	# Autoloads are global: never leak origin state into other suites.
	FloatingOrigin.reset()
	GameState.chunk_size = 0.0


func _make_node(pos: Vector3, shiftable: bool) -> Node3D:
	var node: Node3D = auto_free(Node3D.new())
	node.position = pos
	if shiftable:
		node.add_to_group(FloatingOrigin.SHIFTABLE_GROUP)
	add_child(node)
	return node


func test_autoload_is_registered() -> void:
	var node: Node = get_tree().root.get_node_or_null("FloatingOrigin")
	assert_object(node).is_not_null()
	assert_str(node.get_script().resource_path).is_equal(SCRIPT_PATH)


func test_game_state_absolute_and_local_positions_round_trip() -> void:
	GameState.origin_chunk = Vector2i(3, -2)
	var local := Vector3(10.0, 4.0, -7.5)
	var absolute: Vector3 = GameState.absolute_position(local)
	assert_vector(absolute).is_equal(Vector3(3.0 * CHUNK + 10.0, 4.0, -2.0 * CHUNK - 7.5))
	assert_vector(GameState.local_position(absolute)).is_equal(local)


func test_rebase_preserves_absolute_positions() -> void:
	var target_abs: Vector3 = GameState.absolute_position(_target.global_position)
	var other_abs: Vector3 = GameState.absolute_position(_other.global_position)
	var offset: Vector3 = FloatingOrigin.rebase_now()
	assert_vector(offset).is_equal(Vector3(4.0 * CHUNK, 0.0, -2.0 * CHUNK))
	assert_object(GameState.origin_chunk).is_equal(Vector2i(4, -2))
	assert_vector(GameState.absolute_position(_target.global_position)).is_equal(target_abs)
	assert_vector(GameState.absolute_position(_other.global_position)).is_equal(other_abs)
	assert_vector(_target.global_position).is_equal(Vector3(-6.0, 5.0, -2.0))


func test_rebase_shifts_whole_chunks_and_never_height() -> void:
	var offset: Vector3 = FloatingOrigin.rebase_now()
	assert_float(fmod(offset.x, CHUNK)).is_equal(0.0)
	assert_float(fmod(offset.z, CHUNK)).is_equal(0.0)
	assert_float(offset.y).is_equal(0.0)
	assert_float(_other.global_position.y).is_equal(8.0)


func test_non_shiftable_nodes_are_left_alone() -> void:
	var fixed := _make_node(Vector3(1.0, 2.0, 3.0), false)
	FloatingOrigin.rebase_now()
	assert_vector(fixed.global_position).is_equal(Vector3(1.0, 2.0, 3.0))


func test_rebase_emits_origin_shifted_with_offset() -> void:
	var received: Array[Vector3] = []
	var listener := func(offset: Vector3) -> void: received.append(offset)
	EventBus.origin_shifted.connect(listener)
	FloatingOrigin.rebase_now()
	EventBus.origin_shifted.disconnect(listener)
	assert_array(received).contains_exactly([Vector3(4.0 * CHUNK, 0.0, -2.0 * CHUNK)])


func test_no_rebase_below_threshold() -> void:
	_target.position = Vector3(90.0, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_object(GameState.origin_chunk).is_equal(Vector2i.ZERO)


func test_automatic_rebase_above_threshold() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_object(GameState.origin_chunk).is_equal(Vector2i(4, -2))
	assert_float(Vector2(_target.position.x, _target.position.z).length()).is_less(CHUNK)


func test_rebase_near_origin_is_a_no_op() -> void:
	_target.position = Vector3(20.0, 0.0, -20.0)
	assert_vector(FloatingOrigin.rebase_now()).is_equal(Vector3.ZERO)
	assert_object(GameState.origin_chunk).is_equal(Vector2i.ZERO)
