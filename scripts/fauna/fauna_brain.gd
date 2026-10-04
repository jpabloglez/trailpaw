class_name FaunaBrain
extends Node
## Decides what a [FaunaAgent] does: perceives the player (found through
## [constant Animal.PLAYER_GROUP]) at [member tick_hz], asks [FaunaDecision] for the behaviour
## and switches the [StateMachine]. Also keeps the separation push from other agents.
##
## Ticks are staggered per agent (seeded offset) so a herd does not think on the same frame.
## [br][br]
## Budget: per tick one group lookup, one decision and an O(agents) separation pass (≤ 10
## agents); the physics frame itself does nothing.

## Emitted when the behaviour changes.
signal behaviour_changed(from: StringName, to: StringName)

## Radius within which other agents push this one away (m).
const SEPARATION_RADIUS: float = 2.0

## Reactions and time use.
@export var profile: FaunaProfile
## The agent.
@export var agent: FaunaAgent
## Behaviour state machine.
@export var state_machine: StateMachine
## Perception and decision ticks per second (lowered by the AI LOD).
@export_range(0.1, 30.0, 0.1, "suffix:Hz") var tick_hz: float = 5.0

## Latest perception.
var perception := FaunaPerception.new()
## Push away from nearby agents (horizontal, length ≤ 1), refreshed every tick.
var separation: Vector3 = Vector3.ZERO

var _since: float = 0.0
var _previous_distance: float = INF
var _neighbours := PackedVector3Array()
var _alarm_left: float = 0.0


func _ready() -> void:
	process_physics_priority = -5
	_since = agent.rng.randf() / tick_hz  # stagger
	if state_machine != null:
		state_machine.state_changed.connect(
			func(from: StringName, to: StringName) -> void: behaviour_changed.emit(from, to)
		)


func _physics_process(delta: float) -> void:
	_since += delta
	if _since >= 1.0 / tick_hz:
		tick(_since)
		_since = 0.0


## Perceives and decides now ([param elapsed] seconds since the last tick).
func tick(elapsed: float) -> void:
	perceive(elapsed)
	_update_separation()
	var current := state_machine.current_state_name()
	var state := state_machine.current_state as FaunaState
	var done := state == null or state.is_done()
	var next := FaunaDecision.decide(
		current, done, perception, profile, agent.rng.randf(), agent.rng.randf()
	)
	_alarm_left = maxf(0.0, _alarm_left - elapsed)
	var moment := current in [FaunaDecision.SOCIAL, FaunaDecision.PLAY, FaunaDecision.FOLLOW]
	if _alarm_left > 0.0 and not (moment and not done):
		next = FaunaDecision.FLEE  # a herd mate bolted
	if next == FaunaDecision.FLEE and current != FaunaDecision.FLEE and agent.herd != null:
		agent.herd.alarm(agent)
	if next != current:
		state_machine.transition_to(next)
	elif done and state != null:
		state.restart()


## Makes it flee for at least [param seconds] (a herd mate bolted).
func alarm(seconds: float) -> void:
	_alarm_left = maxf(_alarm_left, seconds)


## Whether it is alarmed by its herd now.
func is_alarmed() -> bool:
	return _alarm_left > 0.0


## Updates [member perception] from the player's position.
func perceive(elapsed: float) -> void:
	var player := get_tree().get_first_node_in_group(Animal.PLAYER_GROUP) as Node3D
	if player == null:
		perception.player_distance = INF
		perception.closing_speed = 0.0
		perception.to_player = Vector3.ZERO
		_previous_distance = INF
		return
	var offset := player.global_position - agent.global_position
	offset.y = 0.0
	var distance := offset.length()
	perception.player_position = player.global_position
	perception.player_distance = distance
	perception.to_player = offset / distance if distance > 1e-4 else Vector3.ZERO
	var closing := 0.0
	if is_finite(_previous_distance) and elapsed > 0.0:
		closing = (_previous_distance - distance) / elapsed
	perception.closing_speed = closing
	_previous_distance = distance


## Starts following the player for [param seconds] (friendly animals after playing).
func start_follow(seconds: float) -> void:
	var follow := state_machine.get_state(FaunaDecision.FOLLOW) as FaunaFollowState
	follow.duration = seconds
	if not state_machine.transition_to(FaunaDecision.FOLLOW):
		follow.restart()


func _update_separation() -> void:
	_neighbours.clear()
	for node in get_tree().get_nodes_in_group(FaunaAgent.GROUP):
		if node != agent:
			_neighbours.append((node as Node3D).global_position)
	separation = FaunaSteering.separation(agent.global_position, _neighbours, SEPARATION_RADIUS)
