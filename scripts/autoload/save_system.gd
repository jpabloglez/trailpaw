## Reads and writes the one saved game (Phase 10: a single game with autosave) as JSON under
## [code]user://saves/[/code].
##
## Writes are atomic: the new file is written next to the old one and only then takes its
## place, so a crash mid-write never leaves a broken save. Reading migrates older versions
## ([SaveMigrations]) and reports problems in [member last_error] instead of loading
## half-way.
## [br][br]
## Autoload name: [code]SaveSystem[/code]. No [code]class_name[/code]: it would hide the
## autoload singleton.
extends Node

## The game was saved to [param path].
signal saved(path: String)

## File name of the save.
const FILE_NAME: String = "save.json"
## Suffix of the file being written.
const TEMP_SUFFIX: String = ".tmp"

## Folder of the save (tests point it elsewhere).
var save_dir: String = "user://saves"
## Why the last [method read] or [method write] failed (empty after success).
var last_error: String = ""


## Path of the save file.
func path() -> String:
	return save_dir.path_join(FILE_NAME)


## Whether a save exists.
func exists() -> bool:
	return FileAccess.file_exists(path())


## Writes [param data] (stamped with the current time). Returns [constant OK] or an error.
func write(data: SaveData) -> Error:
	last_error = ""
	var made := DirAccess.make_dir_recursive_absolute(save_dir)
	if made != OK and not DirAccess.dir_exists_absolute(save_dir):
		return _fail(made, "cannot create %s" % save_dir)
	data.saved_at = int(Time.get_unix_time_from_system())
	var temp := path() + TEMP_SUFFIX
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return _fail(FileAccess.get_open_error(), "cannot write %s" % temp)
	file.store_string(JSON.stringify(data.to_dict(), "\t"))
	file.close()
	if FileAccess.file_exists(path()):
		DirAccess.remove_absolute(path())
	var renamed := DirAccess.rename_absolute(temp, path())
	if renamed != OK:
		return _fail(renamed, "cannot replace %s" % path())
	saved.emit(path())
	return OK


## Reads and migrates the save; null (with [member last_error]) when missing or unreadable.
func read() -> SaveData:
	last_error = ""
	var source := path()
	if not FileAccess.file_exists(source):
		if FileAccess.file_exists(source + TEMP_SUFFIX):
			source += TEMP_SUFFIX  # the game stopped between writing and replacing
		else:
			last_error = "no save"
			return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(source)) != OK:
		last_error = (
			"corrupt save: %s (line %d)" % [json.get_error_message(), json.get_error_line()]
		)
		return null
	if not json.data is Dictionary:
		last_error = "corrupt save: not an object"
		return null
	var reasons: Array[String] = []
	var current := SaveMigrations.migrate(json.data, reasons)
	if current.is_empty():
		last_error = ", ".join(reasons)
		return null
	return SaveData.from_dict(current)


## Deletes the save (New game).
func erase() -> void:
	for file in [path(), path() + TEMP_SUFFIX]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


func _fail(code: Error, message: String) -> Error:
	last_error = message
	push_warning("SaveSystem: " + message)
	return code
