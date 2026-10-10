class_name HintDirector
extends CanvasLayer
## Teaches the first minutes without walls of text: one short, contextual hint at a time
## ("WASD to explore", "Thirsty or hungry? Q to sniff around", "Follow the blue sparkles to
## water"…) with the player's own keys, shown when it is useful and gone for good once the
## player has done it. Learnt hints are kept in the settings ([code]Settings.hints[/code], a
## [HintProgress]), so a new game does not teach them again; they can be turned off.
## [br][br]
## Budget: the rules are checked 4 times a second (a few comparisons); the label only fades.

## Order the hints are taught in.
const ORDER: Array[StringName] = [
	&"move", &"run", &"sniff", &"water", &"eat", &"map", &"rest", &"journal", &"hamlet_food"
]
## Seconds between rule checks.
const CHECK_INTERVAL: float = 0.25

## Texts and triggers.
@export var settings: HintSettings
## The player animal.
@export var body: CharacterBody3D
## Its movement (distance, running).
@export var movement: MovementComponent
## Its needs (thirst, hunger, energy).
@export var needs: NeedsComponent
## Its sniffer (sniffing, scented water).
@export var sniffer: Sniffer
## Its state machine (resting).
@export var state_machine: StateMachine
## Holds the animal until the ground is ready (hints wait for it; optional).
@export var spawner: AnimalSpawner

var _label: Label
var _current: StringName = &""
var _since_check: float = 0.0
var _playing_time: float = 0.0
var _landed_time: float = -1.0
var _start := Vector3.INF
var _walked: float = 0.0
var _last_position := Vector3.INF
var _ran: float = 0.0
var _met_animal: bool = false
var _seen_hamlet_food: bool = false
var _water_scented: bool = false


func _ready() -> void:
	layer = 85
	_label = MenuStyle.label("", 24, "Hint")
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.position.y -= 190.0
	_label.modulate.a = 0.0
	add_child(_label)
	if sniffer != null:
		sniffer.sniffed.connect(func(_count: int) -> void: complete(&"sniff"))
		sniffer.water_scented.connect(func(_at: Vector3) -> void: _water_scented = true)
	if state_machine != null:
		state_machine.state_changed.connect(
			func(_from: StringName, to: StringName) -> void:
				if to == &"Rest":
					complete(&"rest")
		)
	EventBus.interaction_performed.connect(_on_interaction)
	EventBus.map_opened.connect(func() -> void: complete(&"map"))
	EventBus.animal_discovered.connect(func(_id: StringName) -> void: _met_animal = true)
	EventBus.journal_opened.connect(func() -> void: complete(&"journal"))
	EventBus.hamlet_food_seen.connect(func() -> void: _seen_hamlet_food = true)


func _process(delta: float) -> void:
	_track(delta)
	_since_check += delta
	if _since_check >= CHECK_INTERVAL:
		_since_check = 0.0
		_current = pick()
		if _current != &"":
			_label.text = text_for(_current)
	var show := _current != &"" and Settings.hints.enabled
	_label.modulate.a = move_toward(
		_label.modulate.a, 1.0 if show else 0.0, delta * settings.fade_per_second
	)


## The hint that should show now (the first one not done whose moment has come), or empty.
func pick() -> StringName:
	if not Settings.hints.enabled or _landed_time < 0.0:
		return &""
	if _playing_time - _landed_time < settings.first_delay:
		return &""
	for id in ORDER:
		if Settings.hints.is_done(id):
			continue
		if is_due(id):
			return id
	return &""


## Whether hint [param id] is useful now.
func is_due(id: StringName) -> bool:
	var due := false
	match id:
		&"move":
			due = true
		&"run":
			due = Settings.hints.is_done(&"move")
		&"sniff":
			due = (
				_need(&"thirst") < settings.sniff_below
				or _need(&"hunger") < settings.sniff_below
				or _playing_time > settings.sniff_after
			)
		&"water":
			due = _water_scented and _need(&"thirst") < 100.0
		&"eat":
			due = Settings.hints.is_done(&"sniff") and _need(&"hunger") < settings.eat_below
		&"map":
			due = _water_scented or _playing_time > settings.map_after
		&"rest":
			due = _need(&"energy") < settings.rest_below
		&"journal":
			due = _met_animal  # once the first animal is in it
		&"hamlet_food":
			due = _seen_hamlet_food
	return due


## Marks hint [param id] as done (it never shows again) and saves the settings.
func complete(id: StringName) -> void:
	if not Settings.hints.mark(id):
		return
	Settings.save_settings()
	if _current == id:
		_current = &""


## The text of hint [param id] with the player's keys filled in.
func text_for(id: StringName) -> String:
	var text: String = settings.texts.get(id, "")
	var moves := PackedStringArray()
	for action: StringName in [&"move_forward", &"move_left", &"move_back", &"move_right"]:
		moves.append(Settings.binding_text(action).get_slice(",", 0).strip_edges())
	return (
		text
		. format(
			{
				"move":
				"".join(moves) if moves.size() == 4 and moves[0].length() == 1 else " ".join(moves),
				"sprint": Settings.binding_text(&"sprint"),
				"sniff": Settings.binding_text(&"sniff"),
				"interact": Settings.binding_text(&"interact"),
				"map": Settings.binding_text(&"map"),
				"journal": Settings.binding_text(&"journal"),
				"rest": Settings.binding_text(&"rest"),
				"hold_sprint": "Press" if Settings.sprint_toggle else "Hold",
				"hold_rest": "Press" if Settings.rest_toggle else "Hold",
			}
		)
	)


## The hint showing now (empty when none).
func current() -> StringName:
	return _current


## Current opacity of the hint.
func opacity() -> float:
	return _label.modulate.a


func _track(delta: float) -> void:
	if spawner != null and spawner.is_parked():
		return
	_playing_time += delta
	if _landed_time < 0.0:
		_landed_time = _playing_time
	if body == null:
		return
	var at := GameState.absolute_position(body.global_position)
	if _last_position != Vector3.INF:
		_walked += Vector2(at.x - _last_position.x, at.z - _last_position.z).length()
	_last_position = at
	if _walked >= settings.move_distance:
		complete(&"move")
	if movement != null and movement.species != null:
		if movement.horizontal_speed() > movement.species.trot_speed * 1.05:
			_ran += delta
			if _ran >= settings.run_seconds:
				complete(&"run")


func _need(id: StringName) -> float:
	return needs.value(id) if needs != null else 100.0


func _on_interaction(type: int, definition_id: StringName) -> void:
	match type:
		InteractionDefinition.Type.DRINK:
			complete(&"water")
		InteractionDefinition.Type.EAT:
			complete(&"eat")
			if definition_id == &"eggs" or definition_id == &"vegetables":
				complete(&"hamlet_food")  # learnt: they got some
