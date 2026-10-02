class_name AttractCamera
extends Camera3D
## The slow camera behind the main menu: glides along +X above the terrain at
## [member speed], looking a little ahead and down, so the menu sits on a living landscape.
## [br][br]
## Budget: one height sample per frame.

## Glide speed (m/s).
@export_range(0.1, 20.0, 0.1, "suffix:m/s") var speed: float = 2.5
## Height above the terrain (m).
@export_range(1.0, 100.0, 0.5, "suffix:m") var altitude: float = 14.0
## How far ahead it looks (m).
@export_range(1.0, 200.0, 1.0, "suffix:m") var look_ahead: float = 40.0

var _sampler: HeightSampler


## Starts gliding from the local [param at] over [param terrain] (absolute heights).
func begin(at: Vector3, terrain: TerrainSettings) -> void:
	_sampler = HeightSampler.new(terrain, GameState.world_seed)
	global_position = at
	_follow_ground(0.0)
	make_current()


func _process(delta: float) -> void:
	if _sampler != null:
		_follow_ground(delta)


func _follow_ground(delta: float) -> void:
	var p := global_position + Vector3(speed * delta, 0.0, 0.0)
	var absolute: Vector3 = GameState.absolute_position(p)
	var ground := maxf(_sampler.height_at(absolute.x, absolute.z), GameState.water_level)
	p.y = (
		lerpf(p.y, ground + altitude, clampf(delta * 0.5, 0.0, 1.0))
		if delta > 0.0
		else ground + altitude
	)
	global_position = p
	var ahead := GameState.absolute_position(p + Vector3(look_ahead, 0.0, 6.0))
	var target_y := maxf(_sampler.height_at(ahead.x, ahead.z), GameState.water_level) + 2.0
	look_at(p + Vector3(look_ahead, target_y - p.y, 6.0), Vector3.UP)
