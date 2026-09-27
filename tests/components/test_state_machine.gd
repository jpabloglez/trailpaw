## Tests for the generic [StateMachine] using recording dummy states.
extends GdUnitTestSuite


## Dummy state that records its lifecycle calls into a shared log.
class RecordingState:
	extends State

	var records: Array[String]
	var ticks: int = 0

	func _init(state_name: StringName, shared_log: Array[String]) -> void:
		name = state_name
		records = shared_log

	func enter(previous: StringName) -> void:
		records.append("enter %s from '%s'" % [name, previous])

	func exit(next: StringName) -> void:
		records.append("exit %s to %s" % [name, next])

	func physics_update(_delta: float) -> void:
		ticks += 1


var _log: Array[String] = []


func before_test() -> void:
	_log = []


## Builds actor → machine → [A, B] and adds it to the tree.
func _make_machine(initial: StringName = &"") -> StateMachine:
	var actor: Node = auto_free(Node.new())
	var machine := StateMachine.new()
	machine.add_child(RecordingState.new(&"A", _log))
	machine.add_child(RecordingState.new(&"B", _log))
	if initial != &"":
		machine.initial_state = machine.get_node(NodePath(initial))
	actor.add_child(machine)
	add_child(actor)
	return machine


func test_starts_in_first_state_by_default() -> void:
	var machine := _make_machine()
	assert_str(machine.current_state_name()).is_equal("A")
	assert_array(_log).contains_exactly(["enter A from ''"])


func test_starts_in_configured_initial_state() -> void:
	var machine := _make_machine(&"B")
	assert_str(machine.current_state_name()).is_equal("B")


func test_injects_machine_and_actor_into_states() -> void:
	var machine := _make_machine()
	var state: State = machine.get_state(&"B")
	assert_object(state.machine).is_same(machine)
	assert_object(state.actor).is_same(machine.get_parent())


func test_transition_calls_exit_then_enter_and_emits_signal() -> void:
	var machine := _make_machine()
	var monitor := monitor_signals(machine)
	assert_bool(machine.transition_to(&"B")).is_true()
	assert_str(machine.current_state_name()).is_equal("B")
	assert_array(_log).contains_exactly(["enter A from ''", "exit A to B", "enter B from 'A'"])
	await assert_signal(monitor).is_emitted("state_changed", [&"A", &"B"])


func test_transition_to_unknown_state_is_ignored() -> void:
	var machine := _make_machine()
	assert_bool(machine.transition_to(&"Nope")).is_false()
	assert_str(machine.current_state_name()).is_equal("A")


func test_transition_to_current_state_is_ignored() -> void:
	var machine := _make_machine()
	assert_bool(machine.transition_to(&"A")).is_false()
	assert_array(_log).has_size(1)


func test_physics_ticks_reach_only_the_active_state() -> void:
	var machine := _make_machine()
	machine._physics_process(0.016)
	machine._physics_process(0.016)
	machine.transition_to(&"B")
	machine._physics_process(0.016)
	var a := machine.get_state(&"A") as RecordingState
	var b := machine.get_state(&"B") as RecordingState
	assert_int(a.ticks).is_equal(2)
	assert_int(b.ticks).is_equal(1)
