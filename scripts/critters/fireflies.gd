class_name Fireflies
extends GPUParticles3D
## Fireflies at night: soft glowing dots drifting in a box around the player, in the forest and
## the river valley, fading in with the dark (the inverse of daylight). Off by day, elsewhere
## and on the Low preset. One particle system, so they cost the GPU almost nothing and the CPU
## nothing.

## How many and where.
@export var settings: SmallLifeSettings
## The player; defaults to the [code]player[/code] group.
@export var player: Node3D
## Day and night (optional; never dark without it).
@export var day_night: DayNightCycle


func _ready() -> void:
	amount = settings.firefly_amount
	lifetime = 6.0
	preprocess = 3.0
	local_coords = false
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(-settings.firefly_box, settings.firefly_box * 2.0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = settings.firefly_box * 0.5
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.25
	process.gravity = Vector3.ZERO
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.6
	process.turbulence_noise_speed_random = 0.4
	var pulse := Gradient.new()
	pulse.offsets = PackedFloat32Array([0.0, 0.2, 0.35, 0.55, 0.7, 1.0])
	pulse.colors = PackedColorArray(
		[
			Color(1, 1, 1, 0),
			Color(1, 1, 1, 1),
			Color(1, 1, 1, 0.15),
			Color(1, 1, 1, 0.9),
			Color(1, 1, 1, 0.1),
			Color(1, 1, 1, 0),
		]
	)
	var ramp := GradientTexture1D.new()
	ramp.gradient = pulse
	process.color_ramp = ramp
	process.color = settings.firefly_color
	process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.12
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = MotionEffects.soft_dot()
	quad.material = material
	draw_pass_1 = quad
	emitting = false


func _process(_delta: float) -> void:
	var focus := _player()
	if focus != null:
		global_position = focus.global_position + Vector3.UP * (settings.firefly_box.y * 0.5 + 0.3)
	var level := darkness() if out_here() else 0.0
	amount_ratio = level
	emitting = level > 0.05


## 0 by day … 1 at full night (from the sky's stars); never dark without a cycle.
func darkness() -> float:
	if day_night == null:
		return 0.0
	var hour := GameState.time_of_day() / 60.0
	return DayCurve.sample(day_night.settings.key_hours, day_night.settings.stars, hour)


## Whether fireflies belong where the player is (biome and preset).
func out_here() -> bool:
	if Settings.quality != null and not Settings.quality.motion_effects:
		return false
	return settings.firefly_biomes.has(GameState.current_biome)


func _player() -> Node3D:
	if player != null and is_instance_valid(player):
		return player
	return get_tree().get_first_node_in_group(Animal.PLAYER_GROUP) as Node3D
