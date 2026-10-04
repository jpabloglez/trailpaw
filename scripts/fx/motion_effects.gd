class_name MotionEffects
extends Node3D
## Small particle effects of the player's movement: a dust puff on each footstep when trotting
## or running on dry ground (tinted by the biome's ground colour), a bigger puff on a landing,
## and splashes on footsteps in water and when landing in or wading into it. The surface comes
## from [method FootstepAudio.surface], so sounds and effects always agree. Off when the
## quality preset turns [member QualityPreset.motion_effects] off.
## [br][br]
## Budget: a pool of [member MotionEffectsSettings.pool_size] one-shot [GPUParticles3D] (built
## once); per physics tick two comparisons; per effect one emitter restart.

## The effect last started ([code]&"dust"[/code], [code]&"landing"[/code],
## [code]&"splash"[/code]); for tests and tools.
signal effect_started(kind: StringName, at: Vector3)

## Look and triggers.
@export var settings: MotionEffectsSettings
## The animal body.
@export var body: CharacterBody3D
## Its movement (speed, grounded, water depth).
@export var movement: MovementComponent
## Emits the footsteps.
@export var animation: AnimationController
## Decides the surface under the paws.
@export var footsteps: FootstepAudio
## Biomes, for the dust colour (optional).
@export var biomes: BiomeTable

var _pool: Array[GPUParticles3D] = []
var _next: int = 0
var _was_grounded: bool = true
var _was_wading: bool = false
var _fall_speed: float = 0.0


func _ready() -> void:
	top_level = true
	add_to_group(FloatingOrigin.SHIFTABLE_GROUP)
	for i in settings.pool_size:
		_pool.append(_emitter())
	if animation != null:
		animation.footstep.connect(func(_paw: StringName) -> void: on_footstep())


func _physics_process(_delta: float) -> void:
	if movement == null:
		return
	var grounded := movement.is_grounded()
	var wading := footsteps != null and footsteps.surface() == FootstepAudio.Surface.WATER
	if not grounded:
		_fall_speed = maxf(_fall_speed, -body.velocity.y)
	elif not _was_grounded:
		if _fall_speed >= settings.landing_speed:
			if wading:
				_start(&"splash", settings.splash_amount, settings.splash_color)
			else:
				_start(&"landing", settings.landing_amount, _dust_color())
		_fall_speed = 0.0
	if wading and not _was_wading and grounded:
		_start(&"splash", settings.splash_amount, settings.splash_color)
	_was_grounded = grounded
	_was_wading = wading


## Whether effects are on (the quality preset allows them).
func enabled() -> bool:
	return Settings.quality == null or Settings.quality.motion_effects


## A footstep: a splash when wading, dust when trotting or running on dry ground.
func on_footstep() -> void:
	if footsteps != null and footsteps.surface() == FootstepAudio.Surface.WATER:
		_start(&"splash", settings.step_amount, settings.splash_color)
		return
	var species := movement.species if movement != null else null
	if species == null:
		return
	if movement.horizontal_speed() >= species.trot_speed * settings.dust_speed_factor:
		_start(&"dust", settings.step_amount, _dust_color())


## Emitters currently playing.
func active_count() -> int:
	return _pool.filter(func(e: GPUParticles3D) -> bool: return e.emitting).size()


func _start(kind: StringName, amount: int, color: Color) -> void:
	if not enabled():
		return
	var emitter := _pool[_next]
	_next = (_next + 1) % _pool.size()
	emitter.emitting = false
	emitter.amount_ratio = float(amount) / emitter.amount  # no buffer reallocation
	(emitter.process_material as ParticleProcessMaterial).color = color
	var spread := 1.6 if kind == &"splash" else 1.0
	(emitter.process_material as ParticleProcessMaterial).initial_velocity_max = spread
	emitter.global_position = body.global_position + Vector3.UP * 0.05
	emitter.restart()
	emitter.emitting = true
	effect_started.emit(kind, emitter.global_position)


func _dust_color() -> Color:
	var tint := settings.dust_tint
	if biomes == null:
		return tint
	for biome in biomes.biomes:
		if biome.id == GameState.current_biome:
			var ground := biome.ground_color_a.lerp(biome.ground_color_b, 0.5)
			return Color(ground.lerp(tint, 0.6), tint.a)
	return tint


func _emitter() -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.one_shot = true
	emitter.amount = maxi(
		settings.step_amount, maxi(settings.landing_amount, settings.splash_amount)
	)
	emitter.emitting = false
	emitter.explosiveness = 0.9
	emitter.lifetime = settings.lifetime
	emitter.local_coords = false
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 70.0
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 1.0
	process.gravity = Vector3(0.0, -2.5, 0.0)
	process.damping_min = 1.5
	process.damping_max = 2.5
	process.scale_min = 0.6
	process.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	emitter.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.18
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _soft_dot()
	quad.material = material
	emitter.draw_pass_1 = quad
	add_child(emitter)
	return emitter


# A soft round sprite (white centre fading to transparent), shared by every emitter.
static func _soft_dot() -> GradientTexture2D:
	var falloff := Gradient.new()
	falloff.set_color(0, Color(1, 1, 1, 1))
	falloff.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = falloff
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	return texture
