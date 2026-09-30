## Player settings: graphics presets, input remaps and audio volumes (per bus, Phase 9).
##
## Will persist to [code]user://settings.cfg[/code] via [ConfigFile] (Phase 10). Phase 4 adds
## the graphics quality preset, which systems read and follow through
## [signal quality_changed].
## [br][br]
## Autoload name: [code]Settings[/code]. No [code]class_name[/code]: it would hide the
## autoload singleton.
extends Node

## The graphics quality preset changed; systems depending on it (vegetation density, …)
## should apply [param preset].
signal quality_changed(preset: QualityPreset)
## The volume of audio bus [param bus] changed to [param linear] (0…1).
signal volume_changed(bus: StringName, linear: float)

## Preset used until the player picks another (and before settings persistence exists).
const DEFAULT_QUALITY_PATH: String = "res://data/quality/medium.tres"
## Audio buses in [code]default_bus_layout.tres[/code] order: everything goes through Master;
## the others are the groups players can set apart (Phase 10 settings menu).
const BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"Ambience"]

## Current graphics quality preset.
var quality: QualityPreset = preload(DEFAULT_QUALITY_PATH)
## Volume per bus, linear 0…1 (0 = muted).
var volumes: Dictionary[StringName, float] = {
	&"Master": 1.0, &"Music": 1.0, &"SFX": 1.0, &"Ambience": 1.0
}


## Sets the volume of [param bus] to [param linear] (0…1, clamped; 0 mutes) and applies it.
func set_volume(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		push_warning("Settings.set_volume: unknown bus '%s'" % bus)
		return
	var value := clampf(linear, 0.0, 1.0)
	volumes[bus] = value
	AudioServer.set_bus_mute(index, value <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))
	volume_changed.emit(bus, value)


## Volume of [param bus] (linear 0…1).
func volume(bus: StringName) -> float:
	return volumes.get(bus, 1.0)


## Switches to [param preset] and notifies listeners (no-op if it is already active).
func set_quality(preset: QualityPreset) -> void:
	if preset == quality:
		return
	quality = preset
	quality_changed.emit(preset)
