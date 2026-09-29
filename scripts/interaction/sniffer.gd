class_name Sniffer
extends Node3D
## Sniffing (Q): briefly highlights the food the animal can eat nearby — available, in its
## diet, within [member SniffSettings.radius], the nearest [member SniffSettings.max_highlights]
## — with soft sparkles, plus one blue sparkle at the nearest water. Sparkles fade out after
## [member SniffSettings.duration]; the next sniff waits [member SniffSettings.cooldown].
##
## Food is found with one sphere query on the [code]interactable[/code] layer through the same
## provider protocol as the [Interactor]; water by sampling ground heights on rings around the
## animal with downward rays.
## [br][br]
## Budget: only on a sniff — one shape query (≤ [constant MAX_QUERY] results) and
## directions × rings rays (96 by default); sparkles are pooled and just fade per frame.

## A sniff happened; [param count] food highlights (water not included).
signal sniffed(count: int)

## Shape query results considered.
const MAX_QUERY: int = 128
## Sparkles fade with the animal still moving: speed under which the sniff animation plays.
const ANIMATION_MAX_SPEED: float = 0.3
## Water must be at least this deep where the hint points (m).
const WATER_MIN_DEPTH: float = 0.05
## Sparkle shader.
const MARKER_SHADER: Shader = preload("res://shaders/sniff_marker.gdshader")

## What sniffing reveals and for how long.
@export var settings: SniffSettings
## The animal body.
@export var body: CharacterBody3D
## Movement (speed for the animation).
@export var movement: MovementComponent
## Decides what the animal can eat ([method Interactor.accepts]).
@export var interactor: Interactor
## Plays the sniff animation (optional).
@export var animation: AnimationController

var _markers: Array[MeshInstance3D] = []
var _shown: int = 0
var _time_left: float = 0.0
var _cooldown_left: float = 0.0
var _water_hint: Vector3 = Vector3.INF
var _query := PhysicsShapeQueryParameters3D.new()
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = settings.radius
	_query.shape = sphere
	_query.collision_mask = Interactable.LAYER
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	_ray.collision_mask = 1  # world
	if body != null:
		_ray.exclude = [body.get_rid()]
	set_process(false)


func _process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if _time_left <= 0.0:
		if _cooldown_left <= 0.0:
			set_process(false)
		return
	_time_left = maxf(0.0, _time_left - delta)
	var alpha := clampf(_time_left / settings.fade, 0.0, 1.0) if settings.fade > 0.0 else 1.0
	for i in _shown:
		(_markers[i].material_override as ShaderMaterial).set_shader_parameter(&"alpha", alpha)
	if _time_left <= 0.0:
		_hide_markers()


## Sniffs unless still cooling down. Returns whether it sniffed.
func request_sniff() -> bool:
	if _cooldown_left > 0.0:
		return false
	sniff_now()
	return true


## Highlights what is around now (ignores the cooldown, which it restarts).
func sniff_now() -> void:
	_cooldown_left = settings.cooldown
	_time_left = settings.duration
	if animation != null and movement.horizontal_speed() < ANIMATION_MAX_SPEED:
		animation.play_action(&"sniff")
	var food := find_food()
	_water_hint = find_water()
	_hide_markers()
	for target in food:
		_show_marker(target.position, settings.food_color)
	if _water_hint != Vector3.INF:
		_show_marker(_water_hint, settings.water_color)
	set_process(true)
	sniffed.emit(food.size())


## Available food in the animal's diet within the radius, nearest first, capped.
func find_food() -> Array[InteractionTarget]:
	var origin := body.global_position
	_query.transform = Transform3D(Basis.IDENTITY, origin)
	var hits := body.get_world_3d().direct_space_state.intersect_shape(_query, MAX_QUERY)
	var found: Array[InteractionTarget] = []
	for hit in hits:
		var collider: Object = hit.collider
		if collider == null or not collider.has_method(&"interaction_target"):
			continue
		var target: InteractionTarget = collider.call(&"interaction_target", hit.shape)
		if target == null or target.definition.type != InteractionDefinition.Type.EAT:
			continue
		if origin.distance_to(target.position) > settings.radius:
			continue
		if interactor != null and not interactor.accepts(target):
			continue
		if found.any(func(t: InteractionTarget) -> bool: return t.same_as(target)):
			continue
		found.append(target)
	found.sort_custom(
		func(a: InteractionTarget, b: InteractionTarget) -> bool:
			return origin.distance_squared_to(a.position) < origin.distance_squared_to(b.position)
	)
	if found.size() > settings.max_highlights:
		found.resize(settings.max_highlights)
	return found


## Nearest point (on rings around the animal, within the radius) where the ground lies under
## the water surface, at the surface; [constant Vector3.INF] if none.
func find_water() -> Vector3:
	if is_inf(GameState.water_level):
		return Vector3.INF
	var origin := body.global_position
	var space := body.get_world_3d().direct_space_state
	for ring in range(1, settings.water_rings + 1):
		var distance := settings.radius * ring / settings.water_rings
		for d in settings.water_directions:
			var angle := TAU * d / settings.water_directions
			var point := origin + Vector3(cos(angle), 0.0, sin(angle)) * distance
			_ray.from = Vector3(point.x, GameState.water_level + 40.0, point.z)
			_ray.to = Vector3(point.x, GameState.water_level - 40.0, point.z)
			var hit := space.intersect_ray(_ray)
			if hit.is_empty():
				continue
			if GameState.water_level - (hit.position as Vector3).y >= WATER_MIN_DEPTH:
				return Vector3(point.x, GameState.water_level, point.z)
	return Vector3.INF


## Positions of the sparkles showing now (food first, then the water hint if any).
func highlights() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in _shown:
		out.append(_markers[i].global_position)
	return out


## Where the water sparkle points ([constant Vector3.INF] when none).
func water_hint() -> Vector3:
	return _water_hint


## Seconds until sniffing is possible again.
func cooldown_left() -> float:
	return _cooldown_left


func _show_marker(at: Vector3, color: Color) -> void:
	if _shown >= _markers.size():
		var marker := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * settings.size
		marker.mesh = quad
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = MARKER_SHADER
		marker.material_override = material
		marker.top_level = true
		marker.add_to_group(FloatingOrigin.SHIFTABLE_GROUP)
		add_child(marker)
		_markers.append(marker)
	var node := _markers[_shown]
	var material := node.material_override as ShaderMaterial
	material.set_shader_parameter(&"color", color)
	material.set_shader_parameter(&"alpha", 1.0)
	node.global_position = at + Vector3.UP * settings.lift
	var distance := body.global_position.distance_to(at)
	node.scale = Vector3.ONE * maxf(1.0, distance / settings.grow_distance)
	node.visible = true
	_shown += 1


func _hide_markers() -> void:
	for i in _shown:
		_markers[i].visible = false
	_shown = 0
