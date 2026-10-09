class_name JournalSettings
extends Resource
## The animal journal: its entries (in the order the journal shows them) and what counts as an
## encounter. Values live in [code]data/journal/journal.tres[/code].

## Every animal, in journal order.
@export var entries: Array[JournalEntry] = []
## Seconds an animal must stay in sight (close and on screen) to be recorded.
@export_range(0.1, 10.0, 0.1, "suffix:s") var sight_seconds: float = 1.0
## Encounter checks per second.
@export_range(1.0, 30.0, 0.5) var check_hz: float = 4.0
## Fireflies count as seen once they glow at least this much around the player.
@export_range(0.0, 1.0, 0.05) var firefly_glow: float = 0.5


## The entry with [param id], or null.
func entry(id: StringName) -> JournalEntry:
	for e in entries:
		if e.id == id:
			return e
	return null


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := {}
	for e in entries:
		errors.append_array(e.get_validation_errors())
		if ids.has(e.id):
			errors.append("duplicate entry %s" % e.id)
		ids[e.id] = true
	return errors
