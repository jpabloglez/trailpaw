class_name BiomeAtlasPage
extends VBoxContainer
## The journal's Biomes tab (Phase 16b): how many biomes have been visited and the area
## explored, then a card per biome of the table. Visited biomes show a swatch of their ground
## colours, their name, the day of the first visit and how many of their animals have been met;
## the others a grey swatch and "???". Built in code; [method refresh] fills it.

## Size of a card and of its swatch (px).
const CARD_WIDTH: float = 238.0
const SWATCH: Vector2 = Vector2(218.0, 72.0)
## Swatch of a biome not visited yet.
const UNSEEN: Color = Color(0.32, 0.33, 0.32)

var _counter: Label
var _explored: Label
var _grid: GridContainer
var _cards: Dictionary[StringName, Dictionary] = {}  # id → {swatch_a, swatch_b, name, visit, met}


func _init() -> void:
	name = "BiomesPage"
	add_theme_constant_override(&"separation", 8)
	_counter = MenuStyle.label("", 20, "Counter")
	add_child(_counter)
	_explored = MenuStyle.label("", 16, "Explored")
	add_child(_explored)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override(&"h_separation", 12)
	_grid.add_theme_constant_override(&"v_separation", 12)
	add_child(_grid)


## Fills the cards from [param table] (the biomes), [param journal] (visits and animals met,
## may be null), [param entries] (the journal's animals) and [param explored] (may be null).
func refresh(
	table: BiomeTable, journal: AnimalJournal, entries: JournalSettings, explored: ExploredMap
) -> void:
	if table == null:
		return
	if _cards.is_empty():
		for biome in table.biomes:
			_grid.add_child(_card(biome.id))
	var visited := 0
	for biome in table.biomes:
		var seen := journal != null and journal.has_visited(biome.id)
		visited += int(seen)
		var card := _cards[biome.id]
		(card.swatch_a as ColorRect).color = biome.ground_color_a if seen else UNSEEN
		(card.swatch_b as ColorRect).color = biome.ground_color_b if seen else UNSEEN
		(card.name as Label).text = biome.display_name if seen else "???"
		var day := floori(journal.first_visit(biome.id) / GameState.DAY_MINUTES) + 1 if seen else 0
		(card.visit as Label).text = "First visited: day %d" % day if seen else ""
		var lives := 0
		var met := 0
		for entry in entries.entries:
			if entry.biome_ids(table).has(biome.id):
				lives += 1
				met += int(journal != null and journal.is_seen(entry.id))
		(card.met as Label).text = "Animals met here: %d / %d" % [met, lives] if seen else ""
	_counter.text = "%d / %d biomes" % [visited, table.biomes.size()]
	var km2 := explored.area() / 1.0e6 if explored != null else 0.0
	_explored.text = "Explored: %.2f km²" % km2


## The counter's text ("N / M biomes").
func counter_text() -> String:
	return _counter.text


## The explored area's text.
func explored_text() -> String:
	return _explored.text


## What the card of biome [param id] shows: name, visit, met, and whether it is greyed out.
func card_texts(id: StringName) -> Dictionary:
	var card := _cards[id]
	return {
		"name": (card.name as Label).text,
		"visit": (card.visit as Label).text,
		"met": (card.met as Label).text,
		"greyed": (card.swatch_a as ColorRect).color == UNSEEN,
	}


func _card(id: StringName) -> Control:
	var panel := PanelContainer.new()
	panel.name = String(id)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.22, 0.27, 0.21)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.custom_minimum_size.x = CARD_WIDTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 4)
	panel.add_child(column)
	var swatch := HBoxContainer.new()  # the two ground colours side by side
	swatch.add_theme_constant_override(&"separation", 0)
	column.add_child(swatch)
	var halves: Array[ColorRect] = []
	for half in 2:
		var rect := ColorRect.new()
		rect.custom_minimum_size = Vector2(SWATCH.x * 0.5, SWATCH.y)
		swatch.add_child(rect)
		halves.append(rect)
	var title := MenuStyle.label("", 22, "Name")
	column.add_child(title)
	var visit := _small("Visit")
	visit.modulate = Color(0.85, 0.92, 0.75)
	column.add_child(visit)
	var met := _small("Met")
	column.add_child(met)
	_cards[id] = {
		"swatch_a": halves[0], "swatch_b": halves[1], "name": title, "visit": visit, "met": met
	}
	return panel


func _small(node_name: String) -> Label:
	var label := MenuStyle.label("", 14, node_name)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = CARD_WIDTH - 20.0
	return label
