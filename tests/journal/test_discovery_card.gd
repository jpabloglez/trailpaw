## Tests for the new-animal card (slides in on a discovery with the animal's name, queues the
## next one, leaves by itself, waits while the game is paused), the chime, and the portrait
## studio that gives every journal animal a figure.
extends GdUnitTestSuite

const JOURNAL: JournalSettings = preload("res://data/journal/journal.tres")
const CARD: DiscoveryCardSettings = preload("res://data/ui/discovery_card.tres")


func after_test() -> void:
	get_tree().paused = false


func _card() -> DiscoveryCard:
	var fast: DiscoveryCardSettings = CARD.duplicate()
	fast.slide_in = 0.05
	fast.hold = 0.2
	fast.slide_out = 0.05
	var card: DiscoveryCard = auto_free(DiscoveryCard.new())
	card.settings = fast
	card.journal = JOURNAL
	add_child(card)
	return card


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func test_a_discovery_slides_a_card_in_and_it_leaves_by_itself() -> void:
	var card := _card()
	EventBus.animal_discovered.emit(&"heron")
	await get_tree().process_frame
	assert_str(String(card.showing)).is_equal("heron")
	assert_str(card.shown_name()).is_equal("Heron")
	var panel: Control = card.get_node("Card")
	assert_bool(panel.visible).is_true()
	await _wait(0.6)  # in, hold, out
	assert_str(String(card.showing)).is_equal("")
	assert_bool(panel.visible).is_false()


func test_discoveries_close_together_wait_their_turn() -> void:
	var card := _card()
	card.enqueue(&"frog")
	card.enqueue(&"dragonfly")
	card.enqueue(&"not_an_animal")  # ignored
	assert_str(String(card.showing)).is_equal("frog")
	assert_int(card.waiting()).is_equal(1)
	await _wait(0.45)
	assert_str(String(card.showing)).is_equal("dragonfly")
	assert_str(card.shown_name()).is_equal("Dragonfly")
	assert_int(card.waiting()).is_equal(0)


func test_while_paused_it_hides_and_waits() -> void:
	var card := _card()
	card.enqueue(&"deer")
	get_tree().paused = true  # the map or a menu is open
	await _wait(0.6)
	var panel: Control = card.get_node("Card")
	assert_bool(panel.visible).is_false()
	assert_str(String(card.showing)).is_equal("deer")  # still its turn
	get_tree().paused = false
	await get_tree().process_frame
	assert_bool(panel.visible).is_true()
	await _wait(0.6)
	assert_str(String(card.showing)).is_equal("")


func test_the_chime_is_short_soft_and_audible() -> void:
	var chime := SynthSounds.chime()
	assert_float(chime.get_length()).is_between(0.5, 1.2)
	var loudest := 0
	for i in range(0, chime.data.size(), 2):
		loudest = maxi(loudest, absi(chime.data.decode_s16(i)))
	assert_int(loudest).is_between(6000, 26000)  # never clipping
	assert_float(CARD.chime_volume_db).is_less(0.0)


func test_every_animal_gets_a_framed_figure_and_a_portrait() -> void:
	var studio: PortraitStudio = auto_free(PortraitStudio.new())
	studio.size = Vector2i(96, 96)
	add_child(studio)
	for entry in JOURNAL.entries:
		var figure := PortraitStudio.figure_for(entry)
		assert_object(figure).override_failure_message(String(entry.id)).is_not_null()
		var visuals := figure.find_children("*", "VisualInstance3D", true, false)
		(
			assert_bool(figure is VisualInstance3D or not visuals.is_empty())
			. override_failure_message(String(entry.id))
			. is_true()
		)
		figure.free()
		var texture: Texture2D = await studio.snapshot(entry)
		assert_object(texture).is_not_null()
		assert_int(texture.get_width()).is_equal(96)
		assert_object(PortraitStudio.cached(entry.id)).is_same(texture)
