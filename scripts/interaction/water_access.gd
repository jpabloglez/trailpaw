class_name WaterAccess
extends Node
## Virtual interaction provider for water (no shapes): DRINK when the ground just ahead of the
## nose lies under the water surface ([code]GameState.water_level[/code]) and the animal stands
## on the shore or wades; COOL_OFF while wading. When both apply, it offers whichever need is
## lower (thirst or comfort). Water never runs out.
## [br][br]
## Budget: one downward ray per [Interactor] probe (10 Hz); the query object is reused.

## Target key of drinking.
const DRINK_KEY: int = 0
## Target key of cooling off.
const COOL_OFF_KEY: int = 1

## Drinking (HOLD, thirst per second).
@export var drink: InteractionDefinition
## Cooling off while wading (HOLD, comfort per second).
@export var cool_off: InteractionDefinition
## The animal body.
@export var body: CharacterBody3D
## Movement (water depth, swimming, species).
@export var movement: MovementComponent
## Needs, to choose between drinking and cooling off (optional).
@export var needs: NeedsComponent
## Interactor this provider registers with.
@export var interactor: Interactor
## How far ahead of the body the nose reaches for water (m).
@export_range(0.1, 3.0, 0.05, "suffix:m") var nose_reach: float = 0.8
## Water must be at least this deep under the nose (m).
@export_range(0.0, 1.0, 0.01, "suffix:m") var min_depth: float = 0.05
## The paws may stand at most this far above the water surface to reach it (m).
@export_range(0.0, 2.0, 0.05, "suffix:m") var max_shore_height: float = 0.6

var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_query.collision_mask = 1  # world
	_query.collide_with_areas = false
	if body != null:
		_query.exclude = [body.get_rid()]
	if interactor != null:
		interactor.add_virtual_provider(self)


## The water target available now, or null.
func virtual_target() -> InteractionTarget:
	var wading := is_wading()
	var drinkable := can_drink()
	if wading and (not drinkable or _prefers_cooling()):
		return InteractionTarget.new(cool_off, body.global_position, self, COOL_OFF_KEY)
	if drinkable:
		var nose := _nose_point()
		var at := Vector3(nose.x, GameState.water_level, nose.z)
		return InteractionTarget.new(drink, at, self, DRINK_KEY)
	return null


## Whether the animal stands in shallow water (not swimming).
func is_wading() -> bool:
	if not _near_water():
		return false
	var depth := movement.water_depth()
	return depth > min_depth and depth < movement.species.swim_enter_depth


## Whether the animal can drink: wading, or water right ahead of its nose from the shore.
func can_drink() -> bool:
	return _near_water() and (is_wading() or _water_under(_nose_point()))


## Provider protocol: each target stays available while its own condition holds (a drink is
## not cut short because cooling off became the better offer).
func is_target_available(key: int) -> bool:
	return is_wading() if key == COOL_OFF_KEY else can_drink()


## Provider protocol: water never runs out.
func consume_target(_key: int) -> void:
	pass


func _near_water() -> bool:
	return movement != null and not movement.swimming and not is_inf(GameState.water_level)


func _nose_point() -> Vector3:
	var forward := -body.global_basis.z
	forward.y = 0.0
	return body.global_position + forward.normalized() * nose_reach


## Whether the ground at [param point] is under the water and the shore is low enough.
func _water_under(point: Vector3) -> bool:
	if body.global_position.y - GameState.water_level > max_shore_height:
		return false
	_query.from = Vector3(point.x, GameState.water_level + 2.0, point.z)
	_query.to = Vector3(point.x, GameState.water_level - 20.0, point.z)
	var hit := body.get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		return false
	return GameState.water_level - (hit.position as Vector3).y >= min_depth


func _prefers_cooling() -> bool:
	if needs == null:
		return true
	return needs.model.fraction(&"temperature") <= needs.model.fraction(&"thirst")
