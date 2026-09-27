class_name BiomeTracker
extends Node
## Watches which biome the target is in and announces changes through
## [code]EventBus.biome_entered[/code], also updating [code]GameState.current_biome[/code].
##
## Samples at [constant SAMPLE_HZ] and switches only when another biome's weight reaches
## [constant ENTER_WEIGHT], so wandering along a boundary never flickers. The first sample
## announces the starting biome.
## [br][br]
## Budget: one [method BiomeResolver.weights_at] call every 250 ms.

## Samples per second.
const SAMPLE_HZ: float = 4.0
## Weight a different biome needs before it is announced (hysteresis; > 0.5).
const ENTER_WEIGHT: float = 0.6

## Terrain settings providing the biome table.
@export var terrain: TerrainSettings
## Node whose absolute position is tracked (the player, or the debug camera).
@export var target: Node3D

var _resolver: BiomeResolver
var _since_sample: float = 0.0
var _weights: Dictionary[StringName, float] = {}
var _names: Dictionary[StringName, String] = {}


func _ready() -> void:
	add_to_group(WorldStreamer.DEBUG_LINES_GROUP)


func _process(delta: float) -> void:
	_since_sample += delta
	if _since_sample >= 1.0 / SAMPLE_HZ:
		_since_sample = 0.0
		sample_now()


## Samples immediately and announces a biome change if the hysteresis allows it.
## Returns the current biome id.
func sample_now() -> StringName:
	if target == null or terrain == null or terrain.biomes == null:
		return GameState.current_biome
	if _resolver == null:
		# Built lazily: the world seed is set by the scene after children are ready.
		_resolver = BiomeResolver.new(terrain.biomes, GameState.world_seed)
		for biome in terrain.biomes.biomes:
			_names[biome.id] = biome.display_name
	var absolute: Vector3 = GameState.absolute_position(target.global_position)
	_weights = _resolver.weights_at(absolute.x, absolute.z)
	var best: StringName = GameState.current_biome
	var best_weight := -1.0
	for id: StringName in _weights:
		if _weights[id] > best_weight:
			best = id
			best_weight = _weights[id]
	var first := GameState.current_biome == &""
	if best != GameState.current_biome and (first or best_weight >= ENTER_WEIGHT):
		GameState.current_biome = best
		EventBus.biome_entered.emit(best, _names.get(best, String(best)))
	return GameState.current_biome


## Lines for the F3 overlay.
func get_debug_lines() -> PackedStringArray:
	var parts := PackedStringArray()
	for id: StringName in _weights:
		parts.append("%s %.2f" % [id, _weights[id]])
	return PackedStringArray(["biome %s  (%s)" % [GameState.current_biome, ", ".join(parts)]])
