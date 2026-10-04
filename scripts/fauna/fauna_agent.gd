class_name FaunaAgent
extends CharacterBody3D
## An AI-driven animal: the same [MovementComponent], [AnimationController], [GroundAligner]
## and [StateMachine] as the player's [Animal], but its intent comes from behaviour states
## instead of input, as world directions ([member MovementComponent.camera_relative] off).
##
## Set [member species] before adding it to the tree. It lives on the [code]fauna[/code]
## physics layer (collides with the world only) and follows floating-origin rebases.
## [br][br]
## Budget: like the player — one [method CharacterBody3D.move_and_slide] per physics tick,
## ground rays and one [AnimationTree]; the fauna AI LOD (Phase 8) throttles far agents.

## Group of every fauna agent.
const GROUP: StringName = &"fauna"
## Physics layer 4, [code]fauna[/code].
const LAYER: int = 1 << 3
## Height of the obstacle feeler above the paws (m).
const FEELER_HEIGHT: float = 0.4
## Length of the obstacle feeler (m).
const FEELER_LENGTH: float = 1.2
## How far ahead the ground is probed (m).
const PROBE_DISTANCE: float = 1.5
## Ground probe start above the paws (m).
const PROBE_UP: float = 2.0
## Ground probe length below the paws (m): deeper means a drop.
const PROBE_DOWN: float = 3.0
## The ground must be at least this far above the water surface (m).
const DRY_MARGIN: float = 0.1
## Seconds before an animal can be greeted again.
const GREET_COOLDOWN: float = 20.0
## Greeting (SOCIAL, once); its prompt names the species.
const GREET: InteractionDefinition = preload("res://data/interactions/greet.tres")
## Playing, offered after a greeting to animals that play.
const PLAY: InteractionDefinition = preload("res://data/interactions/play.tres")
## Behaviours during which the animal cannot be greeted.
const BUSY: Array[StringName] = [&"Flee", &"Follow", &"Play"]

## Wild species (animal, temperament, profile). Set before entering the tree; it provides
## [member species], the brain's profile and the wander radius.
@export var fauna: FaunaSpecies
## Species (model, gaits, animations). Set before entering the tree (or via [member fauna]).
@export var species: AnimalSpecies
## Seed of this agent's own decisions (wander targets, pauses).
@export var decision_seed: int = 0
## Physics ticks per behaviour tick (1 = every tick; the AI LOD raises it for distant animals,
## which then move in bigger steps with the accumulated delta).
@export_range(1, 10) var tick_stride: int = 1

## Where the agent belongs (wanders around it); set on entering the tree when zero.
var home: Vector3 = Vector3.ZERO
## The group it lives with (null for a loner, e.g. in tests).
var herd: FaunaHerd
## Random numbers for this agent's decisions (seeded with [member decision_seed]).
var rng := RandomNumberGenerator.new()

var _ray := PhysicsRayQueryParameters3D.new()
var _stride_count: int = 0
var _stride_delta: float = 0.0
var _greet: InteractionDefinition
var _play: InteractionDefinition
var _greet_cooldown: float = 0.0

@onready var movement: MovementComponent = %MovementComponent
@onready var state_machine: StateMachine = %StateMachine
@onready var model_root: Node3D = %Model
@onready var brain: FaunaBrain = get_node_or_null("%FaunaBrain")
@onready var animation: AnimationController = %AnimationController
@onready var social: Interactable = get_node_or_null("%Social")


func _enter_tree() -> void:
	if fauna != null:
		species = fauna.animal
		(get_node("FaunaBrain") as FaunaBrain).profile = fauna.profile
		var wander := get_node("StateMachine/Wander") as FaunaWanderState
		wander.radius = fauna.wander_radius
	if species != null:
		(get_node("MovementComponent") as MovementComponent).species = species


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 1  # world
	_ray.collision_mask = 1
	_ray.exclude = [get_rid()]
	rng.seed = decision_seed
	if home == Vector3.ZERO:
		home = global_position
	add_to_group(GROUP)
	add_to_group(FloatingOrigin.SHIFTABLE_GROUP)
	state_machine.set_physics_process(false)  # driven below, every tick_stride ticks
	_stride_count = decision_seed % 10  # stagger
	EventBus.origin_shifted.connect(_on_origin_shifted)
	_fit_capsule(movement.species)
	if social != null:
		_setup_social()
	if Animal.spawn_species_model(movement.species, model_root):
		(%AnimationController as AnimationController).initialize()


func _exit_tree() -> void:
	if herd != null:
		herd.remove(self)


## Where it wanders around: its herd's centre when it has company, else its home.
func wander_centre() -> Vector3:
	if herd != null and herd.size() > 1:
		var centre := herd.centroid()
		if centre != Vector3.INF:
			return centre
	return home


## Whether it has strayed beyond its herd's leash.
func strayed() -> bool:
	if herd == null or herd.size() < 2:
		return false
	return horizontal_distance_to(herd.centroid()) > herd.leash


func _physics_process(delta: float) -> void:
	if social != null:
		_greet_cooldown = maxf(0.0, _greet_cooldown - delta)
		var busy := BUSY.has(state_machine.current_state_name())
		social.available = _greet_cooldown <= 0.0 and not busy
	_stride_delta += delta
	_stride_count += 1
	if _stride_count < tick_stride:
		return
	_stride_count = 0
	if state_machine.current_state != null:
		state_machine.current_state.physics_update(_stride_delta)
	_stride_delta = 0.0


## Whether walking along [param direction] (horizontal unit vector) is fine: nothing blocks the
## way just ahead (trees, rocks, steep ground) and the ground a little further on is dry, not a
## drop and not steeper than the species can walk.
## [br][br]
## Budget: two rays; callers cache the answer ([constant FaunaState.STEER_INTERVAL]).
func is_clear(direction: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var max_slope_cos := cos(deg_to_rad(movement.species.max_slope_degrees))
	var chest := global_position + Vector3.UP * FEELER_HEIGHT
	_ray.from = chest
	_ray.to = chest + direction * FEELER_LENGTH
	var hit := space.intersect_ray(_ray)
	if not hit.is_empty() and (hit.normal as Vector3).y < max_slope_cos:
		return false
	var ahead := global_position + direction * PROBE_DISTANCE
	_ray.from = ahead + Vector3.UP * PROBE_UP
	_ray.to = ahead + Vector3.DOWN * PROBE_DOWN
	hit = space.intersect_ray(_ray)
	if hit.is_empty():
		return false
	if (hit.position as Vector3).y < GameState.water_level + DRY_MARGIN:
		return false
	return (hit.normal as Vector3).y >= max_slope_cos


## Horizontal distance (m) to [param point].
func horizontal_distance_to(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


## Resizes the (lying) collision capsule to the species' body, when it gives one.
func _fit_capsule(animal: AnimalSpecies) -> void:
	if animal == null or animal.body_length <= 0.0:
		return
	var holder := get_node("CollisionShape3D") as CollisionShape3D
	var capsule := (holder.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	capsule.radius = animal.body_radius
	capsule.height = animal.body_length
	holder.shape = capsule
	holder.position.y = animal.body_radius


## Greeting ([constant GREET]) or, after one, playing ([constant PLAY]): what the player can do
## with this animal now.
func social_definition() -> InteractionDefinition:
	return social.definition if social != null else null


func _setup_social() -> void:
	var animal_name := fauna.display_name.to_lower() if fauna != null else "animal"
	_greet = GREET.duplicate() as InteractionDefinition
	_greet.prompt = "Greet the %s" % animal_name
	_play = PLAY.duplicate() as InteractionDefinition
	_play.prompt = "Play with the %s" % animal_name
	social.definition = _greet
	social.started.connect(_on_social_started)
	social.consumed.connect(_on_social_done)


func _on_social_started() -> void:
	state_machine.transition_to(FaunaDecision.SOCIAL)  # stop and face the moment


func _on_social_done() -> void:
	var id := fauna.id if fauna != null else &""
	if social.definition == _greet:
		EventBus.animal_greeted.emit(id)
		if fauna != null and fauna.can_play():
			social.definition = _play
		else:
			_greet_cooldown = GREET_COOLDOWN
		return
	EventBus.animal_played.emit(id)
	social.definition = _greet
	_greet_cooldown = GREET_COOLDOWN
	state_machine.transition_to(FaunaDecision.PLAY)


func _on_origin_shifted(offset: Vector3) -> void:
	home -= offset
