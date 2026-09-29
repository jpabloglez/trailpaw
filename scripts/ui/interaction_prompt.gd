class_name InteractionPrompt
extends CanvasLayer
## Discreet prompt at the bottom centre ("E · Eat berries") for the [Interactor]'s current
## target. Fades in when a target is in reach and out when it goes or while interacting.
## [br][br]
## Budget: a couple of comparisons per frame; the text changes only with the target.

## Look and timing.
@export var settings: InteractionPromptSettings
## Whose target is shown.
@export var interactor: Interactor

@onready var _label: Label = %Label


func _ready() -> void:
	_label.modulate.a = 0.0
	if interactor != null:
		interactor.target_changed.connect(_on_target_changed)
		_on_target_changed(interactor.current_target())


func _process(delta: float) -> void:
	advance(delta)


## Advances the fade by [param delta] seconds.
func advance(delta: float) -> void:
	var show := (
		interactor != null and interactor.current_target() != null and not interactor.is_busy()
	)
	var alpha := move_toward(
		_label.modulate.a, 1.0 if show else 0.0, settings.fade_per_second * delta
	)
	if alpha != _label.modulate.a:
		_label.modulate.a = alpha


## Text currently (or last) shown.
func text() -> String:
	return _label.text


## Current opacity.
func opacity() -> float:
	return _label.modulate.a


## Key bound to [code]interact[/code] as shown to the player (e.g. "E"). Named after the
## physical (QWERTY-position) key; layout-aware labels come with key remapping (Phase 10).
static func interact_key() -> String:
	for event in InputMap.action_get_events(&"interact"):
		var key := event as InputEventKey
		if key != null:
			return OS.get_keycode_string(key.physical_keycode)
	return "?"


func _on_target_changed(target: InteractionTarget) -> void:
	if target != null:
		_label.text = interact_key() + settings.separator + target.definition.prompt
