class_name PlayerInteractState
extends PlayerState
## Performing an interaction with the [Interactor]'s target: the animal stops, plays the
## interaction's animation and applies its need effects — once at the end ([code]ONCE[/code])
## or per second while the action is held ([code]HOLD[/code]). Moving, or the target going
## away, cancels it without effects.

## Provides the target and the held flag.
@export var interactor: Interactor
## Needs changed by the effects.
@export var needs: NeedsComponent
## Plays the interaction's animation.
@export var animation: AnimationController

var _target: InteractionTarget
var _elapsed: float = 0.0


func enter(_previous: StringName) -> void:
	_target = interactor.begin()
	_elapsed = 0.0
	if _target != null:
		_target.begin()
	_play()


func exit(_next: StringName) -> void:
	_target = null
	interactor.end()


func physics_update(delta: float) -> void:
	movement.consume_jump_request()
	movement.apply_ground_movement(delta)
	movement.apply_gravity(delta)
	movement.move()
	if _target == null or movement.has_move_input() or not _target.is_available():
		_leave()
		return
	var definition := _target.definition
	if definition.mode == InteractionDefinition.Mode.ONCE:
		_elapsed += delta
		if _elapsed >= definition.duration:
			_apply(1.0)
			_target.consume()
			_performed()
			_leave()
		return
	if not interactor.interact_held or _effects_full():
		_performed()
		_leave()
		return
	_apply(delta)
	if animation != null and animation.current_state() == &"locomotion":
		_play()  # keep a held action going


## Seconds spent in the current interaction.
func elapsed() -> float:
	return _elapsed


func _apply(scale: float) -> void:
	if needs == null:
		return
	var effects := _target.definition.need_effects
	for id: StringName in effects:
		needs.add(id, effects[id] * scale)


func _effects_full() -> bool:
	if needs == null:
		return false
	var effects := _target.definition.need_effects
	for id: StringName in effects:
		if effects[id] > 0.0 and not needs.is_full(id):
			return false
	return true


func _play() -> void:
	if animation != null:
		animation.play_action(_target.definition.animation)


func _performed() -> void:
	EventBus.interaction_performed.emit(_target.definition.type, _target.definition.id)


func _leave() -> void:
	machine.transition_to(LOCOMOTION if movement.has_move_input() else IDLE)
