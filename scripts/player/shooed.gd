class_name Shooed
extends Node
## Sends the fox off when a villager shoos it ([code]EventBus.fox_shooed[/code]): for
## [member seconds] the player's move intent is replaced by a trot straight away from the
## villager (a world direction), with a small camera jolt; then control returns. Runs after
## [PlayerInput] so its intent wins.

## The player's movement (its intent is overridden while shooed).
@export var movement: MovementComponent
## The player's body (to know which way is away).
@export var body: Node3D
## Shakes a little when shooed (optional).
@export var camera_rig: CameraRig
## How long the fox backs off (s).
@export_range(0.1, 5.0, 0.05, "suffix:s") var seconds: float = 1.2

var _left: float = 0.0
var _away := Vector2.ZERO


func _ready() -> void:
	process_physics_priority = -5  # after PlayerInput (-10), before movement
	EventBus.fox_shooed.connect(shoo)


func _physics_process(delta: float) -> void:
	if _left <= 0.0 or movement == null:
		return
	_left -= delta
	movement.camera_relative = false
	movement.move_input = _away
	movement.sprint = false
	if _left <= 0.0:
		movement.camera_relative = true  # the player has control again


## Sends the fox away from [param from] (global).
func shoo(from: Vector3) -> void:
	if body == null:
		return
	var away := body.global_position - from
	_away = (
		Vector2(away.x, away.z).normalized()
		if Vector2(away.x, away.z).length() > 0.01
		else Vector2.RIGHT
	)
	_left = seconds
	if camera_rig != null:
		camera_rig.jolt(0.45)


## Whether the fox is being sent off right now.
func is_active() -> bool:
	return _left > 0.0


## The direction it is sent (world X/Z).
func away() -> Vector2:
	return _away
