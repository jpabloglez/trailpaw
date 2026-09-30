class_name Weather
extends Node3D
## Weather over the game clock: the [WeatherModel] state of the current slot, eased into cloud
## cover, rain and ground wetness (all per game minute, so resting ×10 speeds them up too).
##
## Publishes [code]GameState.weather[/code] and [code]EventBus.weather_changed[/code]; drives
## the sky's cloud cover and sunlight through the [DayNightCycle], the [code]wetness[/code] global
## shader uniform (terrain darker and glossier, foliage darker), stronger wind in rain and rain
## particles that follow the camera.
## [br][br]
## Budget: a few float ops and property writes per frame; one GPUParticles3D whose amount ratio
## follows the rain (no particles when dry).

## Global shader uniform for ground wetness (0…1).
const WETNESS_PARAM: StringName = &"wetness"
## Global shader uniform for wind (see [WindSettings]).
const WIND_PARAM: StringName = &"wind"
## Rain counts as falling above this intensity (for wetting).
const RAIN_WETS: float = 0.3
## State names, published in [code]GameState.weather[/code] and events.
const NAMES: Array[StringName] = [&"clear", &"cloudy", &"rain"]

## Pacing and looks.
@export var settings: WeatherSettings
## Sky and sunlight to dim under clouds (optional).
@export var day_night: DayNightCycle
## Base wind (strengthened in rain; optional).
@export var wind: WindSettings

## Current cloud cover (0…1).
var cloudiness: float = 0.0
## Current rain intensity (0…1).
var rain: float = 0.0
## Current ground wetness (0…1).
var wetness: float = 0.0

var _model: WeatherModel
var _state: WeatherModel.Kind = WeatherModel.Kind.CLEAR
var _particles: GPUParticles3D
var _started: bool = false


func _ready() -> void:
	_particles = _make_rain()
	add_child(_particles)


func _process(delta: float) -> void:
	advance(delta * GameState.CLOCK.minutes_per_second * GameState.clock_scale)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_particles.global_position = camera.global_position


## Advances the weather by [param game_minutes].
func advance(game_minutes: float) -> void:
	if _model == null:
		_model = WeatherModel.new(GameState.world_seed, settings.transitions())
	var slot := floori(GameState.game_minutes / settings.slot_minutes)
	var next := _model.state_at(slot)
	if next != _state or not _started:
		_state = next
		GameState.weather = NAMES[next]
		EventBus.weather_changed.emit(NAMES[next])
	var target_cloud := settings.cloudiness[_state]
	var target_rain := 1.0 if _state == WeatherModel.Kind.RAIN else 0.0
	if not _started:  # begin settled, not easing in from clear
		_started = true
		cloudiness = target_cloud
		rain = target_rain
		wetness = rain
	var step := settings.ease_per_minute * game_minutes
	cloudiness = move_toward(cloudiness, target_cloud, step)
	rain = move_toward(rain, target_rain, step)
	if rain > RAIN_WETS:
		wetness = minf(1.0, wetness + settings.wet_per_minute * game_minutes)
	else:
		wetness = maxf(0.0, wetness - settings.dry_per_minute * game_minutes)
	_apply()


## Current weather state.
func state() -> WeatherModel.Kind:
	return _state


## Lines for the F3 overlay.
func get_debug_lines() -> PackedStringArray:
	return PackedStringArray(
		["weather %s  clouds %.2f rain %.2f wet %.2f" % [NAMES[_state], cloudiness, rain, wetness]]
	)


func _enter_tree() -> void:
	add_to_group(WorldStreamer.DEBUG_LINES_GROUP)


func _apply() -> void:
	RenderingServer.global_shader_parameter_set(WETNESS_PARAM, wetness)
	if day_night != null:
		day_night.cloud_cover = cloudiness
		day_night.sunlight_factor = lerpf(1.0, settings.overcast_sun, cloudiness)
	if wind != null:
		var packed := wind.as_uniform()
		packed.z *= 1.0 + rain * settings.rain_wind
		RenderingServer.global_shader_parameter_set(WIND_PARAM, packed)
	_particles.emitting = rain > 0.02
	_particles.amount_ratio = rain


func _make_rain() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Rain"
	particles.amount = settings.rain_drops
	particles.lifetime = 1.1
	particles.local_coords = false
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-25, -30, -25), Vector3(50, 50, 50))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(18.0, 1.0, 18.0)
	process.direction = Vector3.DOWN
	process.spread = 4.0
	process.initial_velocity_min = 16.0
	process.initial_velocity_max = 20.0
	process.gravity = Vector3(0.0, -9.8, 0.0)
	particles.process_material = process
	var drop := QuadMesh.new()
	drop.size = Vector2(0.02, 0.45)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.albedo_color = Color(0.78, 0.84, 0.92, 0.35)
	drop.material = material
	particles.draw_pass_1 = drop
	particles.position = Vector3(0.0, 14.0, 0.0)
	return particles
