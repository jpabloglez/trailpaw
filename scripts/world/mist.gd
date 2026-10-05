class_name Mist
extends Node
## Morning mist: from dawn until mid-morning, where the [MistSettings] biomes are (the wetland,
## a little in the valley), the environment's depth fog closes in and turns pale. Its strength
## follows the hour ([method MistSettings.hour_amount]), the biome weights at the player (the
## resolver's blend, so it fades in across a border) and the quality preset, and it eases
## towards that target. With no mist the fog is exactly the environment's own.
## [br][br]
## Budget: [constant APPLY_HZ] updates per second — one biome blend and a few property writes;
## no allocations.

## Updates per second.
const APPLY_HZ: float = 10.0

## Where, when and how thick.
@export var settings: MistSettings
## Terrain (biomes).
@export var terrain: TerrainSettings
## The world environment whose fog it thickens.
@export var world_environment: WorldEnvironment
## Day and night (the mist's colour is mixed in there).
@export var day_night: DayNightCycle
## The player; defaults to the [code]player[/code] group.
@export var player: Node3D

var _amount: float = 0.0
var _since: float = 0.0
var _base_begin: float = 0.0
var _base_end: float = 0.0
var _resolver: BiomeResolver
var _resolver_seed: int = -1
var _blend := BiomeBlend.new()


func _ready() -> void:
	var environment := world_environment.environment
	_base_begin = environment.fog_depth_begin
	_base_end = environment.fog_depth_end


func _process(delta: float) -> void:
	_since += delta
	if _since >= 1.0 / APPLY_HZ:
		step(_since)
		_since = 0.0


## Eases the mist towards its target over [param elapsed] seconds and applies it.
func step(elapsed: float) -> void:
	var target := target_amount()
	_amount = move_toward(_amount, target, settings.response * elapsed)
	var environment := world_environment.environment
	environment.fog_depth_begin = lerpf(_base_begin, settings.depth_begin, _amount)
	environment.fog_depth_end = lerpf(_base_end, settings.depth_end, _amount)
	if day_night != null:
		day_night.mist_color = settings.color
		day_night.mist_amount = _amount * settings.color_mix


## Mist strength now (0…1), after easing.
func amount() -> float:
	return _amount


## Mist strength it is easing towards (0…1): the hour × the biomes at the player × the preset.
func target_amount() -> float:
	var by_hour := settings.hour_amount(GameState.time_of_day() / 60.0)
	if by_hour <= 0.0:
		return 0.0
	var scale := Settings.quality.mist if Settings.quality != null else 1.0
	return by_hour * biome_amount() * scale


## How much mist the biomes at the player get (0…1), blended across borders.
func biome_amount() -> float:
	var focus := _player()
	if focus == null or terrain == null:
		return 0.0
	if _resolver == null or _resolver_seed != GameState.world_seed:
		_resolver = BiomeResolver.new(terrain.biomes, GameState.world_seed)
		_resolver_seed = GameState.world_seed
	var at := GameState.absolute_position(focus.global_position)
	_resolver.blend_into(at.x, at.z, _blend)
	var out: float = settings.biomes.get(_blend.primary.id, 0.0) * (1.0 - _blend.secondary_weight)
	if _blend.secondary != null:
		out += settings.biomes.get(_blend.secondary.id, 0.0) * _blend.secondary_weight
	return out


func _player() -> Node3D:
	if player != null and is_instance_valid(player):
		return player
	return get_tree().get_first_node_in_group(Animal.PLAYER_GROUP) as Node3D
