## Re-centres the world when the tracked target moves too far from the local origin, keeping
## 32-bit float precision near the player (see ADR-004).
##
## Shifts happen in whole chunks: every node in [constant SHIFTABLE_GROUP] moves by
## [code]-offset[/code], [code]GameState.origin_chunk[/code] advances by the same number of
## chunks, the [constant SHADER_ORIGIN_PARAM] global shader uniform is updated and
## [code]EventBus.origin_shifted[/code] fires so systems with cached positions (e.g. the
## terrain streamer) can follow. Height (Y) is never shifted.
## [br][br]
## Autoload name: [code]FloatingOrigin[/code]. No [code]class_name[/code]: it would hide
## the autoload singleton.
extends Node

## Group of top-level [Node3D]s moved on every rebase (player, cameras, dynamic props).
const SHIFTABLE_GROUP: StringName = &"origin_shiftable"

## Global shader uniform holding [code]GameState.origin_offset()[/code], so shaders can
## work in absolute coordinates (declared in [code]project.godot[/code]).
const SHADER_ORIGIN_PARAM: StringName = &"world_origin_offset"

## Horizontal distance from the local origin that triggers a rebase (m). 0 disables it.
var rebase_distance: float = 0.0

var _target: Node3D
var _shader_origin: Vector3 = Vector3.ZERO


func _physics_process(_delta: float) -> void:
	if _target == null or rebase_distance <= 0.0 or not is_instance_valid(_target):
		return
	var p := _target.global_position
	if Vector2(p.x, p.z).length() > rebase_distance:
		rebase_now()


## Sets the chunk size shared with [code]GameState[/code] and the rebase threshold.
func configure(chunk_size: float, distance: float) -> void:
	GameState.chunk_size = chunk_size
	rebase_distance = distance


## Node whose distance from the origin triggers rebases (usually the player).
func track(target: Node3D) -> void:
	_target = target


## Stops tracking and puts the origin back at chunk (0, 0). For new sessions and tests.
func reset() -> void:
	_target = null
	rebase_distance = 0.0
	GameState.origin_chunk = Vector2i.ZERO
	_sync_shader_origin()


## Starts a session with the local origin at chunk [param chunk] (a loaded game far from the
## spawn): no node is shifted — call before placing anything.
func start_at(chunk: Vector2i) -> void:
	GameState.origin_chunk = chunk
	_sync_shader_origin()


## Shifts the world so the target is back near the origin. Returns the applied offset
## (zero when the target is already within half a chunk of the origin).
func rebase_now() -> Vector3:
	if _target == null or GameState.chunk_size <= 0.0:
		return Vector3.ZERO
	var p := _target.global_position
	var size := GameState.chunk_size
	var shift := Vector2i(roundi(p.x / size), roundi(p.z / size))
	if shift == Vector2i.ZERO:
		return Vector3.ZERO
	var offset := Vector3(shift.x, 0.0, shift.y) * size
	for node: Node in get_tree().get_nodes_in_group(SHIFTABLE_GROUP):
		var node_3d := node as Node3D
		if node_3d != null:
			node_3d.global_position -= offset
			node_3d.reset_physics_interpolation()
	GameState.origin_chunk += shift
	_sync_shader_origin()
	EventBus.origin_shifted.emit(offset)
	return offset


## Last value sent to the [constant SHADER_ORIGIN_PARAM] global shader uniform.
func shader_origin() -> Vector3:
	return _shader_origin


func _sync_shader_origin() -> void:
	_shader_origin = GameState.origin_offset()
	RenderingServer.global_shader_parameter_set(SHADER_ORIGIN_PARAM, _shader_origin)
