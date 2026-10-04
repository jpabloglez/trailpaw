class_name HintProgress
extends RefCounted
## Which onboarding hints the player has learnt and whether hints show at all. Owned by the
## [code]Settings[/code] autoload ([code]Settings.hints[/code]) and kept in
## [code]settings.cfg[/code] ([code][onboarding][/code]), so a new game does not teach again.

## Whether the hints show.
var enabled: bool = true

var _done: Array[StringName] = []


## Whether hint [param id] was learnt.
func is_done(id: StringName) -> bool:
	return _done.has(id)


## Records hint [param id] as learnt. Returns whether it is new.
func mark(id: StringName) -> bool:
	if _done.has(id):
		return false
	_done.append(id)
	return true


## Forgets every learnt hint.
func reset() -> void:
	_done.clear()


## Learnt hints, in the order they were learnt.
func done() -> Array[StringName]:
	return _done.duplicate()


## Stores the progress in [param config].
func write(config: ConfigFile) -> void:
	var ids := PackedStringArray()
	for id in _done:
		ids.append(String(id))
	config.set_value("onboarding", "enabled", enabled)
	config.set_value("onboarding", "done", ids)


## Reads the progress from [param config] (missing values: hints on, nothing learnt).
func read(config: ConfigFile) -> void:
	enabled = bool(config.get_value("onboarding", "enabled", true))
	_done.clear()
	for id: Variant in config.get_value("onboarding", "done", PackedStringArray()):
		_done.append(StringName(str(id)))
