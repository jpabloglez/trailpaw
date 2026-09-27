class_name StateMachine
extends Node
## Generic finite state machine. Its child [State] nodes are the states.
##
## Reusable by the player and, from Phase 8, by fauna. The machine forwards physics ticks
## and unhandled input to the active state only. State names are the child node names.
## [br][br]
## Budget: O(1) per tick and no per-frame allocations (one virtual call per tick).

## Emitted after a transition, once the new state's [method State.enter] has run.
signal state_changed(from: StringName, to: StringName)

## State entered on start. Defaults to the first child [State] when unset.
@export var initial_state: State
## Node the states drive. Defaults to this machine's parent.
@export var actor: Node

## The active state, or [code]null[/code] before the machine has started.
var current_state: State

var _states: Dictionary[StringName, State] = {}


func _ready() -> void:
	if actor == null:
		actor = get_parent()
	for child: Node in get_children():
		var state := child as State
		if state != null:
			state.machine = self
			state.actor = actor
			_states[StringName(state.name)] = state
	if initial_state == null and not _states.is_empty():
		initial_state = _states.values()[0]
	if initial_state == null:
		push_error("StateMachine '%s' has no State children" % get_path())
		return
	# States may rely on the actor being fully initialised.
	if actor != null and not actor.is_node_ready():
		await actor.ready
	current_state = initial_state
	current_state.enter(&"")


func _physics_process(delta: float) -> void:
	if current_state != null:
		current_state.physics_update(delta)


func _unhandled_input(event: InputEvent) -> void:
	if current_state != null:
		current_state.handle_input(event)


## Switches to the state named [param state_name]. Returns [code]false[/code] (and does
## nothing) if the state is unknown, already active, or the machine has not started.
func transition_to(state_name: StringName) -> bool:
	if current_state == null:
		return false
	var next: State = _states.get(state_name)
	if next == null:
		push_warning("StateMachine '%s': unknown state '%s'" % [get_path(), state_name])
		return false
	if next == current_state:
		return false
	var previous: StringName = StringName(current_state.name)
	current_state.exit(state_name)
	current_state = next
	current_state.enter(previous)
	state_changed.emit(previous, state_name)
	return true


## Name of the active state, or an empty [StringName] before start.
func current_state_name() -> StringName:
	return StringName(current_state.name) if current_state != null else &""


## Returns the state named [param state_name], or [code]null[/code].
func get_state(state_name: StringName) -> State:
	return _states.get(state_name)
