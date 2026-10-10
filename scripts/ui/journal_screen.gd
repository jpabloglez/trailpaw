class_name JournalScreen
extends CanvasLayer
## The animal journal (the [code]journal[/code] action, J): a card per animal of the world, in
## journal order, under a count of those met. Met animals show their figure, name, the biomes
## they live in and a short line; the others a dark silhouette, "???" and where to look for them.
## Opening it pauses the world; J or Esc closes it. Portraits are rendered by a
## [PortraitStudio] one at a time on the first opening and kept for the session. Built in code.
## [br][br]
## Budget: nothing while closed; on the first opening one portrait render per frame.

## The journal's entries.
const SETTINGS: JournalSettings = preload("res://data/journal/journal.tres")
## Size of a card and of its portrait (px).
const CARD_WIDTH: float = 238.0
const PORTRAIT: int = 132
## Cards per row.
const COLUMNS: int = 5
## Tint of an animal not met yet (its figure as a silhouette).
const SILHOUETTE: Color = Color(0.0, 0.0, 0.0, 0.75)

## Whether J opens the journal (off while in the main menu).
var enabled: bool = false
## The world being played (set by [GameFlow]).
var world: WorldController

var _root: Control
var _counter: Label
var _scroll: ScrollContainer
var _cards: Dictionary[StringName, Dictionary] = {}  # id → {portrait, name, biomes, blurb}
var _studio: PortraitStudio
var _loading: bool = false


func _ready() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var box := MenuStyle.centred_box(_root, "JournalPage")
	box.add_child(MenuStyle.label("Journal", 36))
	_counter = MenuStyle.label("", 20, "Counter")
	box.add_child(_counter)
	_scroll = ScrollContainer.new()
	_scroll.name = "Cards"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 12)
	_scroll.add_child(grid)
	for entry in SETTINGS.entries:
		grid.add_child(_card(entry))
	_studio = PortraitStudio.new()
	_studio.name = "Studio"
	_studio.size = Vector2i.ONE * PORTRAIT * 2  # rendered at twice the size, shown smoothly
	_studio.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_studio)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed(&"journal"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()


## Pauses the world and shows the journal.
func open() -> void:
	if world == null:
		return
	visible = true
	MenuStyle.fade_in(_root)
	get_tree().paused = true
	EventBus.journal_opened.emit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var height := _root.get_viewport_rect().size.y
	_scroll.custom_minimum_size = Vector2(
		(CARD_WIDTH + 12.0) * COLUMNS, minf(820.0, maxf(240.0, height - 230.0))
	)
	refresh()
	_load_portraits()


## Hides the journal and resumes the world.
func close() -> void:
	visible = false
	get_tree().paused = false


## Fills every card from the journal (met or not).
func refresh() -> void:
	var met := _journal()
	var count := 0
	for entry in SETTINGS.entries:
		var seen := met != null and met.is_seen(entry.id)
		count += int(seen)
		var card := _cards[entry.id]
		(card.name as Label).text = entry.display_name if seen else "???"
		(card.blurb as Label).text = entry.blurb if seen else ""
		var lives := (
			entry.lives_in if not entry.lives_in.is_empty() else ", ".join(_biome_names(entry))
		)
		(card.biomes as Label).text = "Lives in: " + lives
		var portrait := card.portrait as TextureRect
		portrait.texture = PortraitStudio.cached(entry.id)
		portrait.self_modulate = Color.WHITE if seen else SILHOUETTE
	_counter.text = "%d / %d animals" % [count, SETTINGS.entries.size()]


## The counter's text.
func counter_text() -> String:
	return _counter.text


## What the card of [param id] shows: name, biomes, blurb, and whether it is a silhouette.
func card_texts(id: StringName) -> Dictionary:
	var card := _cards[id]
	return {
		"name": (card.name as Label).text,
		"biomes": (card.biomes as Label).text,
		"blurb": (card.blurb as Label).text,
		"silhouette": (card.portrait as TextureRect).self_modulate != Color.WHITE,
	}


## Whether portraits are still being rendered.
func is_loading() -> bool:
	return _loading


# Renders the portraits not cached yet, one per frame, showing each as soon as it is ready.
func _load_portraits() -> void:
	if _loading:
		return
	_loading = true
	for entry in SETTINGS.entries:
		if PortraitStudio.cached(entry.id) != null:
			continue
		var texture: Texture2D = await _studio.snapshot(entry)
		(_cards[entry.id].portrait as TextureRect).texture = texture
	_studio.show_entry(null)
	_loading = false


func _card(entry: JournalEntry) -> Control:
	var panel := PanelContainer.new()
	panel.name = String(entry.id)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.22, 0.27, 0.21)  # opaque: the world must not show through
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.custom_minimum_size.x = CARD_WIDTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 4)
	panel.add_child(column)
	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2.ONE * PORTRAIT
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(portrait)
	var name := MenuStyle.label("", 22, "Name")
	column.add_child(name)
	var biomes := _small(14, "Biomes")
	biomes.modulate = Color(0.85, 0.92, 0.75)
	column.add_child(biomes)
	var blurb := _small(14, "Blurb")
	column.add_child(blurb)
	_cards[entry.id] = {"portrait": portrait, "name": name, "biomes": biomes, "blurb": blurb}
	return panel


func _small(size: int, node_name: String) -> Label:
	var label := MenuStyle.label("", size, node_name)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = CARD_WIDTH - 20.0
	return label


func _biome_names(entry: JournalEntry) -> PackedStringArray:
	var names := PackedStringArray()
	var table := _biome_table()
	if table == null:
		return names
	for id in entry.biome_ids(table):
		for biome in table.biomes:
			if biome.id == id:
				names.append(biome.display_name)
	return names


func _journal() -> AnimalJournal:
	if world == null or world.encounters == null:
		return null
	return world.encounters.journal


func _biome_table() -> BiomeTable:
	if world == null or world.streamer == null or world.streamer.terrain == null:
		return null
	return world.streamer.terrain.biomes
