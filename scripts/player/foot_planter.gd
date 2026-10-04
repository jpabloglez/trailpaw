class_name FootPlanter
extends Node
## Plants the player's paws on uneven ground: each physics tick it probes the ground under every
## animated paw ([LegIK.tips]) and asks [LegIK] to move the paw by the difference between that
## ground and the plane the animation assumes — the model's tilted ground plane through the
## body ([GroundAligner] tilts the model). On flat ground or an even slope that difference is 0
## and the animation is untouched; on steps and bumps each paw reaches its own ground. Off in
## the air, while swimming and above [member FootPlantSettings.max_speed_factor] × trot.
## [br][br]
## Budget: one ray per leg per physics tick (4); the query is reused.

## How the paws follow the ground.
@export var settings: FootPlantSettings
## The animal body.
@export var body: CharacterBody3D
## Its movement (speed, grounded, swimming).
@export var movement: MovementComponent
## The model (holds the species' skeleton; tilted by the ground aligner).
@export var model_root: Node3D

var _ik: LegIK
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_ray.collision_mask = 1  # world
	if body != null:
		_ray.exclude = [body.get_rid()]


func _physics_process(delta: float) -> void:
	if _ik == null and not _setup():
		return
	var rate := clampf(delta * settings.smoothing, 0.0, 1.0)
	_ik.influence = lerpf(_ik.influence, 1.0 if planting() else 0.0, rate)
	var space := body.get_world_3d().direct_space_state
	var up := model_root.global_basis.y.normalized()
	var origin := body.global_position
	for i in _ik.leg_count():
		var tip := _ik.tips[i]
		var wanted := 0.0
		_ray.from = tip + Vector3.UP * settings.probe_up
		_ray.to = tip + Vector3.DOWN * settings.probe_down
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty() and absf(up.y) > 0.1:
			var ground: float = (hit.position as Vector3).y
			# Height of the model's ground plane (through the body, normal = model up) here.
			var plane := origin.y - (up.x * (tip.x - origin.x) + up.z * (tip.z - origin.z)) / up.y
			wanted = clampf(ground - plane, -settings.max_drop, settings.max_raise)
		_ik.offsets[i] = lerpf(_ik.offsets[i], wanted, rate)


## Whether the feet are being planted now (on the ground, not swimming, not running).
func planting() -> bool:
	if movement == null or movement.species == null:
		return false
	if movement.swimming or not movement.is_grounded():
		return false
	return movement.horizontal_speed() <= movement.species.trot_speed * settings.max_speed_factor


## The leg IK modifier (null until the model exists or when the species has no leg chains).
func leg_ik() -> LegIK:
	return _ik


func _setup() -> bool:
	if model_root == null or movement == null or movement.species == null:
		return false
	if movement.species.leg_chains.is_empty():
		set_physics_process(false)
		return false
	var skeletons := model_root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return false
	var skeleton := skeletons[0] as Skeleton3D
	_ik = LegIK.new()
	_ik.name = "LegIK"
	_ik.influence = 0.0
	skeleton.add_child(_ik)
	if _ik.setup(skeleton, movement.species.leg_chains) == 0:
		_ik.queue_free()
		_ik = null
		set_physics_process(false)
		return false
	return true
