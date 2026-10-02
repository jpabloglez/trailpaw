class_name Sniffer
extends Node3D
## Sniffing (Q): briefly highlights the food the animal can eat nearby — available, in its
## diet, within [member SniffSettings.radius], the nearest [member SniffSettings.max_highlights]
## — with soft sparkles, plus one blue sparkle at the nearest water. Sparkles fade out after
## [member SniffSettings.duration]; the next sniff waits [member SniffSettings.cooldown].
##
## Food is found with one sphere query on the [code]interactable[/code] layer through the same
## provider protocol as the [Interactor]; water by sampling ground heights on rings around the
## animal with downward rays. When no water is that close, it is [b]scented[/b] from far away
## ([WaterScent], up to [member SniffSettings.scent_radius], on a worker thread): a trail of
## blue sparkles appears one after another from the animal towards it.
## [br][br]
## Budget: only on a sniff — one shape query (≤ [constant MAX_QUERY] results),
## directions × rings rays (96 by default) and, for a scent, one worker task plus
## [member SniffSettings.trail_count] rays when it completes; sparkles are pooled and just fade
## per frame.

## A sniff happened; [param count] food highlights (water not included).
signal sniffed(count: int)
## Water was scented far away, at [param absolute] (absolute position, Y = the water surface).
signal water_scented(absolute: Vector3)

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
## Terrain the water is scented from (optional; no long-range scent without it).
@export var terrain: TerrainSettings

var _markers: Array[MeshInstance3D] = []
var _shown: int = 0
var _time_left: float = 0.0
var _cooldown_left: float = 0.0
var _water_hint: Vector3 = Vector3.INF
var _delays := PackedFloat32Array()
var _scent: WaterScent
var _sampler: HeightSampler
var _sampler_seed: int = 0
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


func _exit_tree() -> void:
	if _scent != null:
		WorkerThreadPool.wait_for_task_completion(_scent.task_id)
		_scent = null


func _process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if _scent != null and WorkerThreadPool.is_task_completed(_scent.task_id):
		_finish_scent()
	if _time_left <= 0.0:
		if _cooldown_left <= 0.0 and _scent == null:
			set_process(false)
		return
	_time_left = maxf(0.0, _time_left - delta)
	var fade := clampf(_time_left / settings.fade, 0.0, 1.0) if settings.fade > 0.0 else 1.0
	var elapsed := settings.duration - _time_left
	for i in _shown:
		var appear := clampf((elapsed - _delays[i]) / maxf(settings.trail_stagger, 0.001), 0.0, 1.0)
		var material := _markers[i].material_override as ShaderMaterial
		material.set_shader_parameter(&"alpha", fade * appear)
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
	else:
		_start_scent()
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


## Whether a long-range water scent is still being worked out.
func is_scenting() -> bool:
	return _scent != null


## Waits for the scent in progress (if any) and shows its trail now (tests and tools).
func finish_scent_now() -> void:
	if _scent != null:
		_finish_scent()


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


func _start_scent() -> void:
	if terrain == null or settings.scent_radius <= settings.radius or _scent != null:
		return
	if is_inf(GameState.water_level):
		return
	if _sampler == null or _sampler_seed != GameState.world_seed:
		_sampler = HeightSampler.new(terrain, GameState.world_seed)
		_sampler_seed = GameState.world_seed
	var at := GameState.absolute_position(body.global_position)
	_scent = WaterScent.new(
		_sampler,
		Vector2(at.x, at.z),
		settings.scent_radius,
		settings.scent_step,
		GameState.water_level,
		settings.scent_min_depth
	)
	_scent.task_id = WorkerThreadPool.add_task(_scent.run, false, "Water scent")


func _finish_scent() -> void:
	WorkerThreadPool.wait_for_task_completion(_scent.task_id)
	var found := _scent.result
	_scent = null
	if found == Vector3.INF:
		return
	_water_hint = GameState.local_position(found)
	_show_trail(_water_hint)
	water_scented.emit(found)


# Sparkles every trail_spacing metres from the animal towards [param target] (not past it), on
# the ground, appearing one after another; the sniff's fade restarts for them.
func _show_trail(target: Vector3) -> void:
	var origin := body.global_position
	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	var distance := flat.length()
	if distance < 0.01:
		return
	var direction := flat / distance
	_time_left = settings.duration + settings.trail_stagger * settings.trail_count
	var start := settings.duration - _time_left
	var space := body.get_world_3d().direct_space_state
	for k in settings.trail_count:
		var along := minf(settings.trail_spacing * (k + 1), distance)
		var point := origin + direction * along
		_ray.from = point + Vector3.UP * 20.0
		_ray.to = point + Vector3.DOWN * 40.0
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty():
			point.y = (hit.position as Vector3).y
		_show_marker(point, settings.water_color, start + settings.trail_stagger * k)
		if along >= distance:
			break


func _show_marker(at: Vector3, color: Color, delay: float = -INF) -> void:
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
	material.set_shader_parameter(&"alpha", 1.0 if is_inf(delay) else 0.0)  # trail: fades in
	node.global_position = at + Vector3.UP * settings.lift
	var distance := body.global_position.distance_to(at)
	node.scale = Vector3.ONE * maxf(1.0, distance / settings.grow_distance)
	node.visible = true
	if _delays.size() <= _shown:
		_delays.resize(_shown + 1)
	_delays[_shown] = delay
	_shown += 1


func _hide_markers() -> void:
	for i in _shown:
		_markers[i].visible = false
	_shown = 0
