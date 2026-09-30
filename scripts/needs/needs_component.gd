class_name NeedsComponent
extends Node
## Ticks the animal's needs ([NeedsModel]) at [constant TICK_HZ] with the current activity
## (from the [MovementComponent]), the current biome's warmth and whether it is in water.
##
## Emits [signal need_changed] for the HUD and relays critical crossings both locally and on
## [code]EventBus.need_critical[/code] / [code]EventBus.need_recovered[/code]. The debug action
## [code]debug_refill_needs[/code] (F5) refills everything until eating and drinking exist
## (Phase 7).
## [br][br]
## Soft consequences (ADR-003): while needs are critical it eases
## [member MovementComponent.speed_multiplier] down to the lowest critical speed factor and
## eases [method tiredness] up (tired idle animation); both ease back when the needs recover.
## [br][br]
## Budget: one [method NeedsModel.tick] (a few float ops per need) every 250 ms.

## A need's value changed.
signal need_changed(need_id: StringName, value: float)
## A need reached its critical threshold.
signal need_critical(need_id: StringName)
## A critical need recovered.
signal need_recovered(need_id: StringName)

## Ticks per second.
const TICK_HZ: float = 4.0
## Below this horizontal speed the animal counts as idle (m/s).
const IDLE_SPEED: float = 0.2

## The needs this animal has.
@export var needs: Array[NeedDefinition] = []
## Activity, biome and water modifiers.
@export var modifiers: NeedModifiers
## Movement read for the activity.
@export var movement: MovementComponent
## Biomes providing warmth by id ([code]GameState.current_biome[/code]).
@export var biomes: BiomeTable

## The pure needs state (read it for values; write through [method set_value]).
var model: NeedsModel

var _since_tick: float = 0.0
var _speed_multiplier: float = 1.0
var _tiredness: float = 0.0
var _warmth: Dictionary[StringName, float] = {}


func _ready() -> void:
	model = NeedsModel.new(needs, modifiers)
	model.value_changed.connect(func(id: StringName, v: float) -> void: need_changed.emit(id, v))
	model.critical_entered.connect(_on_critical_entered)
	model.critical_exited.connect(_on_critical_exited)
	if biomes != null:
		for biome in biomes.biomes:
			_warmth[biome.id] = biome.warmth
	add_to_group(WorldStreamer.DEBUG_LINES_GROUP)


func _process(delta: float) -> void:
	_since_tick += delta
	var step := 1.0 / TICK_HZ
	while _since_tick >= step:
		_since_tick -= step
		tick(step)
	_ease_effects(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_refill_needs"):
		model.refill_all()


## Advances the needs by [param delta] seconds with the current conditions.
func tick(delta: float) -> void:
	model.tick(delta, activity(), felt_warmth(), in_water(), is_raining())


## Current movement speed multiplier from critical needs (eased; 1 = normal).
func speed_multiplier() -> float:
	return _speed_multiplier


## How tired the animal looks (eased 0…1; drives the tired idle animation).
func tiredness() -> float:
	return _tiredness


## Number of critical needs.
func critical_count() -> int:
	return model.critical_count()


## What the animal is doing now, as far as needs are concerned.
func activity() -> NeedsModel.Activity:
	if movement == null:
		return NeedsModel.Activity.IDLE
	if movement.swimming:
		return NeedsModel.Activity.SWIM
	if movement.horizontal_speed() < IDLE_SPEED:
		return NeedsModel.Activity.IDLE
	match movement.gait():
		LocomotionModel.Gait.WALK:
			return NeedsModel.Activity.WALK
		LocomotionModel.Gait.RUN:
			return NeedsModel.Activity.RUN
	return NeedsModel.Activity.TROT


## Warmth of the current biome (0 when unknown).
func biome_warmth() -> float:
	return _warmth.get(GameState.current_biome, 0.0)


## Warmth the animal feels: its biome's, plus the time of day and the weather.
func felt_warmth() -> float:
	return (
		biome_warmth()
		+ modifiers.time_warmth(GameState.time_of_day() / 60.0)
		+ modifiers.weather_warmth_for(GameState.weather)
	)


## Whether it rains (less thirst, see [member NeedModifiers.rain]).
func is_raining() -> bool:
	return GameState.weather == &"rain"


## Whether the animal stands or swims in water (it cools off).
func in_water() -> bool:
	return movement != null and (movement.swimming or movement.water_depth() > 0.0)


## Current value of [param need_id].
func value(need_id: StringName) -> float:
	return model.value(need_id)


## Sets [param need_id] (clamped); used by interactions (Phase 7), saves and tests.
func set_value(need_id: StringName, new_value: float) -> void:
	model.set_value(need_id, new_value)


## Adds [param amount] to [param need_id] (clamped); negative amounts subtract.
func add(need_id: StringName, amount: float) -> void:
	model.set_value(need_id, model.value(need_id) + amount)


## Whether [param need_id] is at its maximum.
func is_full(need_id: StringName) -> bool:
	return model.fraction(need_id) >= 1.0


## Lines for the F3 overlay.
func get_debug_lines() -> PackedStringArray:
	var parts := PackedStringArray()
	for id in model.ids():
		parts.append("%s %.0f%s" % [id, model.value(id), "!" if model.is_critical(id) else ""])
	var activity_name := NeedsModel.ACTIVITY_NAMES[activity()]
	return PackedStringArray(
		["needs %s  (%s, feels %+.2f)" % ["  ".join(parts), activity_name, felt_warmth()]]
	)


func _ease_effects(delta: float) -> void:
	_speed_multiplier = move_toward(
		_speed_multiplier, model.critical_speed_factor(), modifiers.speed_ease_per_second * delta
	)
	var tired_target := 1.0 if model.is_tired() else 0.0
	_tiredness = move_toward(_tiredness, tired_target, modifiers.tired_ease_per_second * delta)
	if movement != null:
		movement.speed_multiplier = _speed_multiplier


func _on_critical_entered(need_id: StringName) -> void:
	need_critical.emit(need_id)
	EventBus.need_critical.emit(need_id)


func _on_critical_exited(need_id: StringName) -> void:
	need_recovered.emit(need_id)
	EventBus.need_recovered.emit(need_id)
