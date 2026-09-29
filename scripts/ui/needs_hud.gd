class_name NeedsHud
extends CanvasLayer
## Minimal, cozy needs HUD: one [NeedMeter] per need of a [NeedsComponent], bottom left. Meters
## stay out of sight while needs are full and fade in as they drop.

## Look and timing shared by every meter.
@export var settings: NeedsHudSettings
## Needs shown.
@export var needs: NeedsComponent

var _meters: Dictionary[StringName, NeedMeter] = {}

@onready var _row: HBoxContainer = %Row


func _ready() -> void:
	if needs == null:
		return
	for id in needs.model.ids():
		var meter := NeedMeter.new()
		meter.name = String(id).capitalize()
		meter.definition = needs.model.definition(id)
		meter.settings = settings
		_row.add_child(meter)
		meter.set_value(needs.value(id), needs.model.is_critical(id))
		_meters[id] = meter
	needs.need_changed.connect(_refresh)
	needs.need_critical.connect(_refresh_state)
	needs.need_recovered.connect(_refresh_state)


## Meter showing [param need_id] (for tests and tools).
func meter(need_id: StringName) -> NeedMeter:
	return _meters.get(need_id)


func _refresh(need_id: StringName, value: float) -> void:
	_meters[need_id].set_value(value, needs.model.is_critical(need_id))


func _refresh_state(need_id: StringName) -> void:
	_refresh(need_id, needs.value(need_id))
