class_name FaunaWanderState
extends FaunaState
## Ambling around home: walk to a random point within [member radius], pause a while, repeat.

## How far from home targets are picked (m).
@export_range(1.0, 200.0, 0.5, "suffix:m") var radius: float = 12.0
## Walking pace (fraction of full input; walk band is below ~0.5).
@export_range(0.05, 1.0, 0.01) var pace: float = 0.35
## Pause at each target (s), uniform in [min, max].
@export var pause_range: Vector2 = Vector2(2.0, 6.0)
## A target counts as reached within this distance (m).
@export_range(0.1, 5.0, 0.1, "suffix:m") var arrive_distance: float = 0.8

var _target: Vector3
var _pause_left: float = 0.0


func enter(_previous: StringName) -> void:
	pick_target()


func physics_update(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left -= delta
		movement.move_input = Vector2.ZERO
		if _pause_left <= 0.0:
			pick_target()
	elif agent().horizontal_distance_to(_target) < arrive_distance:
		movement.move_input = Vector2.ZERO
		_pause_left = agent().rng.randf_range(pause_range.x, pause_range.y)
	else:
		steer_towards(_target, pace)
	ground_tick(delta)


## Chooses the next target around home.
func pick_target() -> void:
	var angle := agent().rng.randf() * TAU
	var distance := sqrt(agent().rng.randf()) * radius
	_target = agent().home + Vector3(cos(angle), 0.0, sin(angle)) * distance


## Sets the target directly (tests and scripted scenes).
func set_target(point: Vector3) -> void:
	_target = point
	_pause_left = 0.0


## Current target.
func target() -> Vector3:
	return _target
