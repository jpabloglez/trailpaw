class_name DayNightCycle
extends Node
## Drives light and sky from the game clock ([code]GameState.time_of_day()[/code]): the sun's
## path, colour and energy, a dim bluish moon at night, ambient light, fog colour and a sky
## shader with stars and clouds. Tracks come from [DayNightSettings]; the night keeps enough
## ambient light to stay readable (a cozy, moonlit night).
##
## It replaces the environment's sky material with [constant SKY_SHADER] and switches ambient
## light to a colour it controls.
## [br][br]
## Budget: [constant APPLY_HZ] updates per second — a few track samples and property writes;
## no allocations.

## Updates per second (the clock moves 1 game minute per real second: steps stay tiny).
const APPLY_HZ: float = 10.0
## Day/night sky shader.
const SKY_SHADER: Shader = preload("res://shaders/sky.gdshader")
## Below this sunlight energy the sun casts no shadows (and is hidden).
const SUN_MIN_ENERGY: float = 0.02

## Tracks over the day.
@export var settings: DayNightSettings
## The sun (a [DirectionalLight3D] in the scene).
@export var sun: DirectionalLight3D
## The world environment (sky, ambient, fog).
@export var world_environment: WorldEnvironment

## Current cloud cover (0…1) shown in the sky (set by the weather).
var cloud_cover: float = 0.0

var _moon: DirectionalLight3D
var _sky_material: ShaderMaterial
var _since: float = 0.0


func _ready() -> void:
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.shadow_enabled = false
	_moon.light_color = settings.moon_color
	add_child(_moon)
	var environment := world_environment.environment
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SKY_SHADER
	if environment.sky == null:
		environment.sky = Sky.new()
	environment.sky.sky_material = _sky_material
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.fog_sky_affect = settings.fog_sky_affect
	apply_now()


func _process(delta: float) -> void:
	_since += delta
	if _since >= 1.0 / APPLY_HZ:
		_since = 0.0
		apply_now()


## Applies the current time of day now.
func apply_now() -> void:
	apply_hour(GameState.time_of_day() / 60.0)


## Applies [param hour] (0…24).
func apply_hour(hour: float) -> void:
	var s := settings
	var keys := s.key_hours
	var towards_sun := sun_direction(hour)
	var sun_energy := DayCurve.sample(keys, s.sun_energy, hour)
	_aim(sun, towards_sun)
	sun.light_energy = sun_energy
	sun.light_color = DayCurve.sample_color(keys, s.sun_color, hour)
	sun.visible = sun_energy > SUN_MIN_ENERGY
	var moon_energy := DayCurve.sample(keys, s.moon_energy, hour)
	_aim(_moon, -towards_sun)
	_moon.light_energy = moon_energy
	_moon.visible = moon_energy > SUN_MIN_ENERGY
	var environment := world_environment.environment
	environment.ambient_light_color = DayCurve.sample_color(keys, s.ambient_color, hour)
	environment.ambient_light_energy = DayCurve.sample(keys, s.ambient_energy, hour)
	environment.fog_light_color = DayCurve.sample_color(keys, s.fog_color, hour)
	var top := DayCurve.sample_color(keys, s.sky_top, hour)
	var horizon := DayCurve.sample_color(keys, s.sky_horizon, hour)
	_sky_material.set_shader_parameter(&"top_color", top)
	_sky_material.set_shader_parameter(&"horizon_color", horizon)
	_sky_material.set_shader_parameter(&"ground_color", horizon.darkened(0.55))
	_sky_material.set_shader_parameter(&"sun_color", sun.light_color)
	_sky_material.set_shader_parameter(&"sun_direction", towards_sun)
	_sky_material.set_shader_parameter(&"moon_direction", -towards_sun)
	_sky_material.set_shader_parameter(&"stars", DayCurve.sample(keys, s.stars, hour))
	_sky_material.set_shader_parameter(&"cloud_cover", cloud_cover)


## Unit vector towards the sun at [param hour]: it rises in the east (+X) at sunrise, peaks at
## [member DayNightSettings.max_elevation] midway (towards −Z, "south") and sets in the west;
## at night it is below the horizon on the opposite arc.
func sun_direction(hour: float) -> Vector3:
	var s := settings
	var day_length := s.sunset_hour - s.sunrise_hour
	var h := fposmod(hour - s.sunrise_hour, 24.0)
	var angle: float
	if h <= day_length:
		angle = PI * h / day_length  # 0 at sunrise … π at sunset
	else:
		angle = PI + PI * (h - day_length) / (24.0 - day_length)  # below the horizon
	var elevation_scale := sin(deg_to_rad(s.max_elevation))
	var up := sin(angle) * elevation_scale
	var across := cos(angle)  # +1 east at sunrise, −1 west at sunset
	var south := sin(angle) * cos(deg_to_rad(s.max_elevation))
	return Vector3(across, up, -south).normalized()


## Elevation of the sun above the horizon at [param hour] (degrees; negative at night).
func sun_elevation(hour: float) -> float:
	return rad_to_deg(asin(clampf(sun_direction(hour).y, -1.0, 1.0)))


## The moon light (for tests and tools).
func moon() -> DirectionalLight3D:
	return _moon


## The sky shader material (for tests and tools).
func sky_material() -> ShaderMaterial:
	return _sky_material


## Points [param light] so that it shines from [param towards_light] (a light shines along −Z).
static func _aim(light: DirectionalLight3D, towards_light: Vector3) -> void:
	var forward := -towards_light
	var up := Vector3.UP if absf(forward.y) < 0.99 else Vector3.FORWARD
	light.global_basis = Basis.looking_at(forward, up)
