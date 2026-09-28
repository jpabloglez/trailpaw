## Player settings: graphics presets, input remaps and audio volumes.
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

## Preset used until the player picks another (and before settings persistence exists).
const DEFAULT_QUALITY_PATH: String = "res://data/quality/medium.tres"

## Current graphics quality preset.
var quality: QualityPreset = preload(DEFAULT_QUALITY_PATH)


## Switches to [param preset] and notifies listeners (no-op if it is already active).
func set_quality(preset: QualityPreset) -> void:
	if preset == quality:
		return
	quality = preset
	quality_changed.emit(preset)
