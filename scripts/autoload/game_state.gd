## Session-wide game state: world seed, floating-origin offset, current biome, water level
## and the game clock (Phase 7).
##
## Fields are added by the phase that needs them (see [code]docs/ARCHITECTURE.md[/code] §2).
## [br][br]
## Autoload name: [code]GameState[/code]. No [code]class_name[/code]: it would hide the
## autoload singleton.
extends Node

## Minutes in a game day.
const DAY_MINUTES: float = 1440.0
## Pace of the game clock.
const CLOCK: ClockSettings = preload("res://data/world/clock.tres")

## Seed for all procedural world generation. Set before the world starts streaming.
var world_seed: int = 0
## Chunk-grid offset of the floating origin: local position (0, 0, 0) is the corner of this
## chunk. Integer, so absolute positions stay exact however far the player travels.
var origin_chunk: Vector2i = Vector2i.ZERO
## Chunk size (m) used to convert [member origin_chunk] to metres. Set by
## [code]FloatingOrigin.configure()[/code].
var chunk_size: float = 0.0

## Absolute height of the water surface ([code]-INF[/code] when the world has no water).
## Published by the terrain streamer; Y is never shifted by rebases.
var water_level: float = -INF
## Biome the player is currently in (as last announced by the biome tracker).
var current_biome: StringName = &""
## Game clock: game minutes since midnight of the first day (advances in [method _process]).
var game_minutes: float = CLOCK.start_minutes
## Clock multiplier (1 = normal pace; resting speeds it up).
var clock_scale: float = 1.0
## Current weather ([code]&"clear"[/code], [code]&"cloudy"[/code] or [code]&"rain"[/code]; set by
## the weather node).
var weather: StringName = &"clear"


func _process(delta: float) -> void:
	advance_clock(delta)


## Advances the game clock by [param real_seconds] at the current pace.
func advance_clock(real_seconds: float) -> void:
	game_minutes += real_seconds * CLOCK.minutes_per_second * clock_scale


## Minutes after midnight (0…1440) of the current game day.
func time_of_day() -> float:
	return fposmod(game_minutes, DAY_MINUTES)


## World-space offset of the local origin (m).
func origin_offset() -> Vector3:
	return Vector3(origin_chunk.x, 0.0, origin_chunk.y) * chunk_size


## Absolute world position of a local (scene) position. Use this, never the local position,
## for anything distance-driven (biomes, saves). Exact origin + local offset in 64-bit
## script floats; the returned [Vector3] has single precision (≈ 1 mm at 10 km).
func absolute_position(local: Vector3) -> Vector3:
	return local + origin_offset()


## Local (scene) position of an absolute world position.
func local_position(absolute: Vector3) -> Vector3:
	return absolute - origin_offset()
