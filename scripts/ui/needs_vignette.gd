class_name NeedsVignette
extends CanvasLayer
## Subtle warm darkening at the screen edges while needs are critical: the visual hint of the
## soft consequences (ADR-003). One critical need gives half intensity, two or more full; it
## eases in and out at [member NeedsVignetteSettings.fade_per_second]. While the animal is too
## cold (the snow) the edges turn frosty blue instead, at least at
## [member NeedsVignetteSettings.cold_intensity].
## [br][br]
## Budget: one full-screen alpha-blended quad, hidden while the intensity is 0.

## Look and timing.
@export var settings: NeedsVignetteSettings
## Needs whose critical count drives the intensity.
@export var needs: NeedsComponent

var _intensity: float = 0.0
var _cold: float = 0.0  # 0 warm tint … 1 frosty tint, eased
var _material: ShaderMaterial

@onready var _rect: ColorRect = %Rect


func _ready() -> void:
	_material = _rect.material as ShaderMaterial
	_material.set_shader_parameter(&"tint", settings.tint)
	_material.set_shader_parameter(&"max_alpha", settings.max_alpha)
	_material.set_shader_parameter(&"inner_radius", settings.inner_radius)
	_material.set_shader_parameter(&"outer_radius", settings.outer_radius)
	_apply()


func _process(delta: float) -> void:
	var count := needs.critical_count() if needs != null else 0
	var cold := needs != null and needs.is_cold()
	var target := settings.target_intensity(count)
	if cold:
		target = maxf(target, settings.cold_intensity)
	var cold_target := 1.0 if cold else 0.0
	if target == _intensity and cold_target == _cold:
		return
	_intensity = move_toward(_intensity, target, settings.fade_per_second * delta)
	_cold = move_toward(_cold, cold_target, settings.fade_per_second * delta)
	_apply()


## Current (eased) intensity, 0…1.
func intensity() -> float:
	return _intensity


## How frosty the tint is (eased 0 warm … 1 cold).
func coldness() -> float:
	return _cold


func _apply() -> void:
	_rect.visible = _intensity > 0.0
	_material.set_shader_parameter(&"intensity", _intensity)
	_material.set_shader_parameter(&"tint", settings.tint.lerp(settings.cold_tint, _cold))
