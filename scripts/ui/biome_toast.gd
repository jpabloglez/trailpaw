class_name BiomeToast
extends CanvasLayer
## Shows the biome name when [code]EventBus.biome_entered[/code] fires: fade in, hold, fade
## out. A new biome arriving mid-toast restarts it with the new name.

## Fade timings.
@export var settings: BiomeToastSettings

var _tween: Tween

@onready var _label: Label = %Label


func _ready() -> void:
	_label.modulate.a = 0.0
	visible = false
	EventBus.biome_entered.connect(_on_biome_entered)


## Displays [param text] with the configured fade in / hold / fade out.
func show_text(text: String) -> void:
	if _tween != null:
		_tween.kill()
	_label.text = text
	_label.modulate.a = 0.0
	visible = true
	_tween = create_tween()
	_tween.tween_property(_label, "modulate:a", 1.0, settings.fade_in)
	_tween.tween_interval(settings.hold)
	_tween.tween_property(_label, "modulate:a", 0.0, settings.fade_out)
	_tween.tween_callback(func() -> void: visible = false)


## Text currently (or last) shown.
func text() -> String:
	return _label.text


func _on_biome_entered(_biome_id: StringName, display_name: String) -> void:
	show_text(display_name)
