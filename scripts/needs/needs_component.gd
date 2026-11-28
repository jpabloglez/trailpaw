class_name NeedsComponent
extends Node
## Ticks the animal's needs ([NeedsModel]) at [constant TICK_HZ] with the current activity
## (from the [MovementComponent]), the current biome's warmth, whether it is in water and
## whether it stands on snow (above [code]GameState.snow_line[/code], colder).
##
## Emits [signal need_changed] for the HUD and relays critical crossings both locally and on
## [code]EventBus.need_critical[/code] / [code]EventBus.need_recovered[/code]. The debug action
## [code]debug_refill_needs[/code] (F5) refills everything until eating and drinking exist
## (Phase 7).
## [br][br]
## Need effects (ADR-012, on top of ADR-003): every tick [member effects] ([NeedEffects], from
## [member effect_table]) is recomputed from the needs' tiers. The component eases
## [member MovementComponent.speed_multiplier] towards its speed factor, sets
## [member MovementComponent.jump_multiplier], gates [member MovementComponent.sprint_allowed]
## through [SprintBursts], and eases [method tiredness] up while the [code]&"tired"[/code] cue
## is active (tired idle animation). Asking to sprint when it may not emits
## [signal effect_blocked] once per need that limits it (also on
## [code]EventBus.need_effect_blocked[/code]) so the HUD and sounds can say why.
## [br][br]
## Budget: one [method NeedsModel.tick] and one [method NeedEffects.update] (O(needs + effects)
## float ops; the shade is asked only while comfort is low) every 250 ms.

## A need's value changed.
signal need_changed(need_id: StringName, value: float)
## A need reached its critical threshold.
signal need_critical(need_id: StringName)
## A critical need recovered.
signal need_recovered(need_id: StringName)
## The animal asked for [param ability] ([code]&"sprint"[/code]) and [param need_id] stops it.
signal effect_blocked(need_id: StringName, ability: StringName)

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
## Effects of low and empty needs (none when unset).
@export var effect_table: NeedEffectTable
## Object with [code]is_shaded(global_position) -> bool[/code] (heat effects pause in shade);
## defaults to the [WorldStreamer] in [constant WorldStreamer.GROUP].
@export var shade_source: Node

## The pure needs state (read it for values; write through [method set_value]).
var model: NeedsModel
## What the needs let the animal do now (recomputed every tick).
var effects: NeedEffects
## How strongly need effects apply (the player's setting).
var intensity: NeedEffects.Intensity = NeedEffects.Intensity.NORMAL

var _since_tick: float = 0.0
var _speed_multiplier: float = 1.0
var _tiredness: float = 0.0
var _warmth: Dictionary[StringName, float] = {}
var _night_drop: Dictionary[StringName, float] = {}
var _multipliers: Dictionary[StringName, Dictionary] = {}
var _dry: Dictionary[StringName, bool] = {}
var _bursts: SprintBursts
var _sprint_blocked: bool = false


func _ready() -> void:
	model = NeedsModel.new(needs, modifiers)
	model.value_changed.connect(func(id: StringName, v: float) -> void: need_changed.emit(id, v))
	model.critical_entered.connect(_on_critical_entered)
	model.critical_exited.connect(_on_critical_exited)
	if effect_table == null:
		effect_table = NeedEffectTable.new()
	effects = NeedEffects.new(effect_table)
	_bursts = SprintBursts.new(effect_table.burst_seconds, effect_table.burst_rest_seconds)
	if biomes != null:
		for biome in biomes.biomes:
			_warmth[biome.id] = biome.warmth
			_night_drop[biome.id] = biome.night_drop
			_multipliers[biome.id] = biome.need_multipliers
			_dry[biome.id] = biome.dry
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
	model.tick(
		delta,
		activity(),
		felt_warmth(),
		in_water(),
		is_raining(),
		_multipliers.get(GameState.current_biome, {}),
		effects
	)
	update_effects()


## Recomputes [member effects] from the needs now (each tick does it too).
func update_effects() -> void:
	effects.update(model, is_cold(), is_shaded(), intensity)


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


## Warmth of the current biome at this hour (0 when unknown): its warmth, less its
## [member BiomeDefinition.night_drop] towards midnight.
func biome_warmth() -> float:
	var biome := GameState.current_biome
	var night := 1.0 - NeedModifiers.day_fraction(GameState.time_of_day() / 60.0)
	return _warmth.get(biome, 0.0) - _night_drop.get(biome, 0.0) * night


## Warmth the animal feels: its biome's, plus the time of day, the weather and the snow.
func felt_warmth() -> float:
	return (
		biome_warmth()
		+ modifiers.time_warmth(GameState.time_of_day() / 60.0)
		+ modifiers.weather_warmth_for(GameState.weather)
		+ (modifiers.snow_warmth if on_snow() else 0.0)
	)


## Whether the animal stands above the snow line.
func on_snow() -> bool:
	return movement != null and movement.absolute_height() > GameState.snow_line


## Whether the animal is too cold now (comfort drops; never in water).
func is_cold() -> bool:
	return not in_water() and modifiers.is_too_cold(felt_warmth() + modifiers.heat(activity()))


## Whether the animal is in shade or water (heat effects pause). Only asked while comfort is
## low; otherwise [code]false[/code].
func is_shaded() -> bool:
	if model.tier(modifiers.warmth_need) == NeedsModel.Tier.NORMAL:
		return false
	if in_water():
		return true
	var shade := _shade()
	var body := movement.get_parent() as Node3D if movement != null else null
	return shade != null and body != null and bool(shade.call(&"is_shaded", body.global_position))


## Whether it rains (less thirst, see [member NeedModifiers.rain]).
func is_raining() -> bool:
	return GameState.weather == &"rain" and not _dry.get(GameState.current_biome, false)


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
		[
			(
				"needs %s  (%s, feels %+.2f%s)"
				% ["  ".join(parts), activity_name, felt_warmth(), ", cold" if is_cold() else ""]
			)
		]
	)


func _ease_effects(delta: float) -> void:
	_speed_multiplier = move_toward(
		_speed_multiplier, effects.speed_factor, modifiers.speed_ease_per_second * delta
	)
	var tired_target := 1.0 if effects.cues().has(&"tired") else 0.0
	_tiredness = move_toward(_tiredness, tired_target, modifiers.tired_ease_per_second * delta)
	if movement == null:
		return
	movement.speed_multiplier = _speed_multiplier
	movement.jump_multiplier = effects.jump_factor
	var wants := movement.wants_sprint()
	var allowed := _bursts.step(delta, effects.sprint, wants and movement.sprint_allowed)
	movement.sprint_allowed = allowed
	var blocked := wants and not allowed
	if blocked and not _sprint_blocked:
		for need_id in effects.sprint_limiters():
			effect_blocked.emit(need_id, &"sprint")
			EventBus.need_effect_blocked.emit(need_id, &"sprint")
	_sprint_blocked = blocked


func _shade() -> Node:
	if shade_source == null and is_inside_tree():
		shade_source = get_tree().get_first_node_in_group(WorldStreamer.GROUP)
	return shade_source


func _on_critical_entered(need_id: StringName) -> void:
	need_critical.emit(need_id)
	EventBus.need_critical.emit(need_id)


func _on_critical_exited(need_id: StringName) -> void:
	need_recovered.emit(need_id)
	EventBus.need_recovered.emit(need_id)
