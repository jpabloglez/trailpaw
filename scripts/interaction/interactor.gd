class_name Interactor
extends Node3D
## Finds what the animal can interact with and starts interactions.
##
## A [ShapeCast3D] sphere in front of the body probes the [code]interactable[/code] layer
## ([constant Interactable.LAYER]); every collider there implements
## [code]interaction_target(shape_index) -> InteractionTarget[/code]. Candidates are scored with
## [InteractionScoring] and the best available one becomes [method current_target]. A
## controller writes intent ([method request_interaction], [member interact_held]); when a
## request arrives on the ground with a target, the [StateMachine] goes to the Interact state
## (the Rest state for REST targets such as dens).
## [br][br]
## Budget: one shape cast and ≤ [constant MAX_RESULTS] small target objects every
## [constant PROBE_INTERVAL] seconds (and on a request).

## The best target changed (null when there is none).
signal target_changed(target: InteractionTarget)

## Seconds between probes.
const PROBE_INTERVAL: float = 0.1
## Colliders considered per probe.
const MAX_RESULTS: int = 8
## A request stays valid for this many physics frames.
const REQUEST_FRAMES: int = 1
## States from which an interaction may start.
const START_STATES: Array[StringName] = [&"Idle", &"Locomotion"]
## State that performs interactions.
const INTERACT_STATE: StringName = &"Interact"

## Reach and scoring.
@export var settings: InteractorSettings
## The animal body (position and facing).
@export var body: CharacterBody3D
## Movement (grounded, swimming).
@export var movement: MovementComponent
## Gameplay state machine.
@export var state_machine: StateMachine

## Whether the controller holds the interact action (HOLD interactions).
var interact_held: bool = false

var _cast: ShapeCast3D
var _virtual_providers: Array[Node] = []
var _target: InteractionTarget
var _active: InteractionTarget
var _since_probe: float = 0.0
var _request_frame: int = -1000


func _ready() -> void:
	process_physics_priority = -5  # after the controller's intent, before the states
	_cast = ShapeCast3D.new()
	_cast.name = "Probe"
	var sphere := SphereShape3D.new()
	sphere.radius = settings.reach_radius
	_cast.shape = sphere
	_cast.position = Vector3(0.0, settings.probe_height, 0.0)
	_cast.target_position = Vector3(0.0, 0.0, -settings.reach_distance)
	_cast.collision_mask = Interactable.LAYER
	_cast.collide_with_areas = true
	_cast.collide_with_bodies = false
	_cast.max_results = MAX_RESULTS
	_cast.enabled = false  # updated on demand
	add_child(_cast)
	add_to_group(WorldStreamer.DEBUG_LINES_GROUP)


func _physics_process(delta: float) -> void:
	_since_probe += delta
	var requested := Engine.get_physics_frames() - _request_frame <= REQUEST_FRAMES
	if _since_probe >= PROBE_INTERVAL or requested:
		_since_probe = 0.0
		probe()
	if requested:
		_request_frame = -1000
		if can_start():
			var resting := _target.definition.type == InteractionDefinition.Type.REST
			state_machine.transition_to(Rester.REST_STATE if resting else INTERACT_STATE)


## Asks to interact with the current target (consumed within [constant REQUEST_FRAMES]).
func request_interaction() -> void:
	_request_frame = Engine.get_physics_frames()


## Probes now and updates [method current_target].
func probe() -> void:
	_cast.force_shapecast_update()
	var best: InteractionTarget = null
	var best_score := -1.0
	var origin := body.global_position
	var forward := -body.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	for i in _cast.get_collision_count():
		var collider := _cast.get_collider(i)
		if collider == null or not collider.has_method(&"interaction_target"):
			continue
		var target: InteractionTarget = collider.call(
			&"interaction_target", _cast.get_collider_shape(i)
		)
		if target == null or not accepts(target):
			continue
		var score := InteractionScoring.score(
			origin,
			forward,
			target.position,
			settings.max_distance,
			settings.max_angle_degrees,
			settings.distance_weight
		)
		if score > best_score:
			best = target
			best_score = score
	for provider in _virtual_providers:
		var target: InteractionTarget = provider.call(&"virtual_target")
		if target == null or not accepts(target):
			continue
		var score := InteractionScoring.score(
			origin,
			forward,
			target.position,
			settings.max_distance,
			settings.max_angle_degrees,
			settings.distance_weight
		)
		if score > best_score:
			best = target
			best_score = score
	_set_target(best)


## Registers a provider without shapes (e.g. [WaterAccess]): a node with
## [code]virtual_target() -> InteractionTarget[/code], asked on every probe.
func add_virtual_provider(provider: Node) -> void:
	if not _virtual_providers.has(provider):
		_virtual_providers.append(provider)


## Whether this animal can use [param target]: available and, for food, in its diet.
func accepts(target: InteractionTarget) -> bool:
	if target.definition == null or not target.is_available():
		return false
	var food := target.definition.food_kind
	return food == &"" or movement.species.diet.has(food)


## Whether an interaction can start now.
func can_start() -> bool:
	return (
		_target != null
		and _active == null
		and movement.is_grounded()
		and not movement.swimming
		and START_STATES.has(state_machine.current_state_name())
	)


## The best target in reach, or null.
func current_target() -> InteractionTarget:
	return _target


## The target being interacted with, or null.
func active_target() -> InteractionTarget:
	return _active


## Whether an interaction is in progress.
func is_busy() -> bool:
	return _active != null


## Called by the Interact state on entry: the current target becomes the active one.
func begin() -> InteractionTarget:
	_active = _target
	return _active


## Called by the Interact state on exit.
func end() -> void:
	_active = null
	probe()


## Lines for the F3 overlay.
func get_debug_lines() -> PackedStringArray:
	var text := "none"
	if _target != null:
		var distance := body.global_position.distance_to(_target.position)
		text = "%s (%.1f m)" % [_target.definition.prompt, distance]
	if _active != null:
		text += "  [busy]"
	return PackedStringArray(["target %s" % text])


func _set_target(target: InteractionTarget) -> void:
	if target == null and _target == null:
		return
	if target != null and target.same_as(_target):
		_target = target
		return
	_target = target
	target_changed.emit(target)
