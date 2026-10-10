class_name DiscoveryCard
extends CanvasLayer
## The new-animal card: when [code]EventBus.animal_discovered[/code] fires, a card slides in from
## the right edge with the animal turning in a [PortraitStudio], its name and "New!", and a soft
## chime; it stays a few seconds and slides away by itself. Discoveries arriving while a card
## is out wait their turn. It never pauses the game, and while the game is paused (a menu, the
## map) it hides and its timing stops. Built in code.
## [br][br]
## A first visit to a biome ([code]EventBus.biome_discovered[/code], Phase 16b) gets the same
## card with a swatch of its ground colours instead of a figure, and "New biome!".

## Timings and look.
@export var settings: DiscoveryCardSettings
## The journal's entries (names and figures).
@export var journal: JournalSettings
## The biomes (names and colours of the biome cards).
@export var terrain: TerrainSettings

## Card currently out (its entry or biome id), or empty.
var showing: StringName = &""
## Whether the card out is a biome's.
var showing_biome: bool = false

var _queue: Array[StringName] = []
var _biome_queued: Array[bool] = []  # per queued id: a biome's card
var _new: Label
var _hint: Label
var _figure: Control
var _swatch: ColorRect
var _panel: PanelContainer
var _name: Label
var _studio: PortraitStudio
var _chime: AudioStreamPlayer
var _tween: Tween


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS  # to hide while paused; the tween itself stops
	_build()
	_panel.visible = false
	EventBus.animal_discovered.connect(enqueue)
	EventBus.biome_discovered.connect(enqueue_biome)


func _process(_delta: float) -> void:
	_panel.visible = showing != &"" and not get_tree().paused


## Shows the card of entry [param id] now, or after the cards already waiting.
func enqueue(id: StringName) -> void:
	if journal.entry(id) == null:
		return
	_queue.append(id)
	_biome_queued.append(false)
	if showing == &"":
		_next()


## Shows the card of biome [param id] now, or after the cards already waiting.
func enqueue_biome(id: StringName) -> void:
	if _biome(id) == null:
		return
	_queue.append(id)
	_biome_queued.append(true)
	if showing == &"":
		_next()


## Entries waiting for their card.
func waiting() -> int:
	return _queue.size()


## Text of the name on the card.
func shown_name() -> String:
	return _name.text


func _next() -> void:
	if _queue.is_empty():
		showing = &""
		showing_biome = false
		_studio.show_entry(null)
		return
	showing = _queue.pop_front()
	showing_biome = _biome_queued.pop_front()
	_figure.visible = not showing_biome
	_swatch.visible = showing_biome
	_new.text = "New biome!" if showing_biome else "New!"
	_hint.text = "Added to your atlas" if showing_biome else "Added to your journal"
	if showing_biome:
		var biome := _biome(showing)
		_name.text = biome.display_name
		_swatch.color = biome.ground_color_a
		_studio.show_entry(null)
	else:
		var entry := journal.entry(showing)
		_name.text = entry.display_name
		_studio.show_entry(entry)
	_chime.play()
	var hidden_x := _panel.size.x + settings.margin.x + 8.0
	_panel.position.x = _shown_x() + hidden_x
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)  # waits while the game is paused
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, ^"position:x", _shown_x(), settings.slide_in)
	_tween.tween_interval(settings.hold)
	_tween.set_ease(Tween.EASE_IN)
	_tween.tween_property(_panel, ^"position:x", _shown_x() + hidden_x, settings.slide_out)
	_tween.tween_callback(_next)


func _biome(id: StringName) -> BiomeDefinition:
	if terrain == null or terrain.biomes == null:
		return null
	for biome in terrain.biomes.biomes:
		if biome.id == id:
			return biome
	return null


func _shown_x() -> float:
	var width := get_viewport().get_visible_rect().size.x if is_inside_tree() else 1920.0
	return width - _panel.size.x - settings.margin.x


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Card"
	var style := StyleBoxFlat.new()
	style.bg_color = MenuStyle.PANEL
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override(&"panel", style)
	_panel.position.y = settings.margin.y
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	_panel.add_child(row)
	var backdrop := PanelContainer.new()  # opaque, so the world never shows through the figure
	var round := StyleBoxFlat.new()
	round.bg_color = Color(0.22, 0.27, 0.21)
	round.set_corner_radius_all(10)
	backdrop.add_theme_stylebox_override(&"panel", round)
	row.add_child(backdrop)
	_figure = backdrop
	_swatch = ColorRect.new()  # a biome's card shows its ground colour instead
	_swatch.name = "Swatch"
	_swatch.custom_minimum_size = Vector2.ONE * settings.portrait_size
	_swatch.visible = false
	row.add_child(_swatch)
	var frame := SubViewportContainer.new()
	frame.name = "Portrait"
	frame.stretch = true
	frame.custom_minimum_size = Vector2.ONE * settings.portrait_size
	backdrop.add_child(frame)
	_studio = PortraitStudio.new()
	_studio.size = Vector2i.ONE * settings.portrait_size
	_studio.spin = settings.spin
	frame.add_child(_studio)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	_new = MenuStyle.label("New!", 18, "New")
	_new.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.4))
	_new.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.add_child(_new)
	_name = MenuStyle.label("", 30, "Name")
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.add_child(_name)
	_hint = MenuStyle.label("Added to your journal", 15, "Hint")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.add_child(_hint)
	_chime = AudioStreamPlayer.new()
	_chime.stream = SynthSounds.chime()
	_chime.bus = &"SFX"
	_chime.volume_db = settings.chime_volume_db
	add_child(_chime)
