## Tests for the animal journal: its entries cover every animal of the world exactly once, the
## journal records each the first time only and saves, and an animal counts as met only when it
## stays close and on screen long enough.
extends GdUnitTestSuite

const JOURNAL: JournalSettings = preload("res://data/journal/journal.tres")
const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const BUTTERFLIES: FlitterKind = preload("res://data/critters/butterflies.tres")
const SMALL_LIFE: SmallLifeSettings = preload("res://data/critters/small_life.tres")
const WORLD: PackedScene = preload("res://scenes/main/world.tscn")

var _saved_biome: StringName
var _saved_minutes: float
var _discovered: Array[StringName] = []


func before_test() -> void:
	_saved_biome = GameState.current_biome
	_saved_minutes = GameState.game_minutes
	GameState.current_biome = &"meadow"
	GameState.game_minutes = 12.0 * 60.0
	_discovered.clear()
	EventBus.animal_discovered.connect(_on_discovered)


func after_test() -> void:
	EventBus.animal_discovered.disconnect(_on_discovered)
	GameState.current_biome = _saved_biome
	GameState.game_minutes = _saved_minutes


func _on_discovered(id: StringName) -> void:
	_discovered.append(id)


# Resources the world scene gives node [param node_name] in property [param property].
func _scene_value(node_name: String, property: String) -> Variant:
	var state := WORLD.get_state()
	for n in state.get_node_count():
		if state.get_node_name(n) != node_name:
			continue
		for p in state.get_node_property_count(n):
			if state.get_node_property_name(n, p) == property:
				return state.get_node_property_value(n, p)
	return null


func _entry_for(animal: Resource) -> Array[JournalEntry]:
	var out: Array[JournalEntry] = []
	for entry in JOURNAL.entries:
		if entry.animal == animal:
			out.append(entry)
	return out


func test_every_animal_of_the_world_has_exactly_one_entry() -> void:
	assert_array(Array(JOURNAL.get_validation_errors())).is_empty()
	var animals: Array[Resource] = []
	for biome in TERRAIN.biomes.biomes:  # the big fauna of every biome
		for fauna in biome.fauna:
			if not animals.has(fauna.species):
				animals.append(fauna.species)
	for kind: Resource in _scene_value("CritterSystem", "kinds"):  # rabbits, ducks, frogs...
		animals.append(kind)
	for kind: Resource in _scene_value("TreeLife", "kinds"):  # squirrels and owls
		animals.append(kind)
	for kind: Resource in _scene_value("FarmLife", "kinds"):  # the hamlets' sheep, pigs, cows
		animals.append(kind)
	animals.append(_scene_value("FarmLife", "chicken"))
	animals.append(_scene_value("BirdFlocks", "settings"))
	animals.append(_scene_value("Butterflies", "kind"))
	animals.append(_scene_value("Dragonflies", "kind"))
	animals.append(_scene_value("Fireflies", "settings"))
	for animal in animals:
		(
			assert_int(_entry_for(animal).size())
			. override_failure_message(animal.resource_path)
			. is_equal(1)
		)
	assert_int(JOURNAL.entries.size()).is_equal(animals.size())  # and nothing else
	for entry in JOURNAL.entries:  # every one lives somewhere the player can go
		var biomes := entry.biome_ids(TERRAIN.biomes)
		var somewhere := not biomes.is_empty() or not entry.lives_in.is_empty()
		assert_bool(somewhere).override_failure_message(String(entry.id)).is_true()


func test_the_journal_records_the_first_sighting_only_and_saves() -> void:
	var journal := AnimalJournal.new()
	assert_bool(journal.discover(&"frog", 600.0, &"wetland")).is_true()
	assert_bool(journal.discover(&"frog", 900.0, &"river_valley")).is_false()  # already met
	assert_bool(journal.discover(&"deer", 950.0, &"forest")).is_true()
	assert_int(journal.seen_count()).is_equal(2)
	var copy := AnimalJournal.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(journal.to_dict())))  # through JSON
	assert_bool(copy.is_seen(&"frog")).is_true()
	assert_bool(copy.is_seen(&"heron")).is_false()
	assert_str(String(copy.first_biome(&"frog"))).is_equal("wetland")  # the first time
	assert_int(copy.seen_count()).is_equal(2)
	copy.from_dict({})  # an old save: nobody met yet
	assert_int(copy.seen_count()).is_equal(0)


# Butterflies over one flower at the origin, a camera 3 m south looking at it, and a tracker.
func _scene(player_at: Vector3, look_at: Vector3) -> Array:
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	player.global_position = player_at
	var flowers := PackedVector3Array()
	for i in 12:
		flowers.append(Vector3(cos(i) * 0.5, 0.0, sin(i) * 0.5))
	var butterflies: Flitters = auto_free(Flitters.new())
	butterflies.kind = BUTTERFLIES
	butterflies.player = player
	butterflies.spot_source = func() -> PackedVector3Array: return flowers
	add_child(butterflies)
	butterflies.set_process(false)
	for t in 30:
		butterflies.step(1.0 / 30.0)  # they come out over the flowers
	var camera: Camera3D = auto_free(Camera3D.new())
	add_child(camera)
	camera.global_position = player_at + Vector3(0.0, 1.5, 0.0)
	camera.look_at(look_at)
	var tracker: EncounterTracker = auto_free(EncounterTracker.new())
	tracker.settings = JOURNAL
	tracker.player = player
	tracker.camera = camera
	tracker.flitters = [butterflies] as Array[Flitters]
	add_child(tracker)
	tracker.set_process(false)
	return [tracker, butterflies, player]


func _watch(tracker: EncounterTracker, seconds: float) -> void:
	for t in int(seconds * 4.0):
		tracker.check(0.25)


func test_an_animal_close_and_on_screen_for_a_second_is_met_once() -> void:
	var made := _scene(Vector3(0, 0, 3), Vector3(0, 0.6, 0))
	var tracker: EncounterTracker = made[0]
	assert_int((made[1] as Flitters).count()).is_greater(0)
	_watch(tracker, 0.5)
	assert_bool(tracker.journal.is_seen(&"butterfly")).is_false()  # a glimpse is not enough
	_watch(tracker, 1.0)
	assert_bool(tracker.journal.is_seen(&"butterfly")).is_true()
	_watch(tracker, 3.0)
	assert_array(_discovered).is_equal([&"butterfly"] as Array[StringName])  # announced once
	assert_str(String(tracker.journal.first_biome(&"butterfly"))).is_equal("meadow")


func test_far_away_or_off_screen_animals_are_not_met() -> void:
	var far: EncounterTracker = _scene(Vector3(0, 0, 20), Vector3(0, 0.6, 0))[0]
	_watch(far, 3.0)  # in view but 20 m away
	assert_bool(far.journal.is_seen(&"butterfly")).is_false()
	var behind: EncounterTracker = _scene(Vector3(0, 0, 2), Vector3(0, 1.5, 10))[0]
	_watch(behind, 3.0)  # 2 m away but behind the camera
	assert_bool(behind.journal.is_seen(&"butterfly")).is_false()
	assert_array(_discovered).is_empty()


func test_fireflies_are_met_when_they_glow_around_the_player() -> void:
	var made := _scene(Vector3(0, 0, 3), Vector3(0, 0.6, 0))
	var tracker: EncounterTracker = made[0]
	var fireflies: Fireflies = auto_free(Fireflies.new())
	fireflies.settings = SMALL_LIFE
	add_child(fireflies)
	fireflies.set_process(false)
	tracker.fireflies = fireflies
	fireflies.emitting = true
	fireflies.amount_ratio = 0.2  # dusk: only a few
	_watch(tracker, 2.0)
	assert_bool(tracker.journal.is_seen(&"firefly")).is_false()
	fireflies.amount_ratio = 0.9
	_watch(tracker, 2.0)
	assert_bool(tracker.journal.is_seen(&"firefly")).is_true()


func test_on_screen_follows_the_cameras_field_of_view() -> void:
	var camera: Camera3D = auto_free(Camera3D.new())
	add_child(camera)
	camera.fov = 60.0
	camera.global_position = Vector3.ZERO
	camera.look_at(Vector3(0, 0, -10))  # looking north
	var size := camera.get_viewport().get_visible_rect().size
	var half_wide := atan(tan(deg_to_rad(30.0)) * size.x / size.y)
	assert_bool(EncounterTracker.on_screen(camera, Vector3(0, 0, -10))).is_true()
	assert_bool(EncounterTracker.on_screen(camera, Vector3(0, 0, 10))).is_false()  # behind
	for side: float in [-1.0, 1.0]:  # just inside and just outside the left and right edges
		var inside := Vector3(sin(half_wide - 0.05) * side, 0, -cos(half_wide - 0.05)) * 10.0
		var outside := Vector3(sin(half_wide + 0.05) * side, 0, -cos(half_wide + 0.05)) * 10.0
		assert_bool(EncounterTracker.on_screen(camera, inside)).is_true()
		assert_bool(EncounterTracker.on_screen(camera, outside)).is_false()
	assert_bool(EncounterTracker.on_screen(camera, Vector3(0, 7, -10))).is_false()  # above the top


func test_an_entry_can_need_less_time_in_sight() -> void:
	var made := _scene(Vector3(0, 0, 3), Vector3(0, 0.6, 0))
	var tracker: EncounterTracker = made[0]
	var quick: JournalSettings = JOURNAL.duplicate()
	quick.entries = JOURNAL.entries.duplicate()
	var entry: JournalEntry = JOURNAL.entry(&"butterfly").duplicate()
	entry.sight_seconds = 0.25  # like a leaping fish
	quick.entries[JOURNAL.entries.find(JOURNAL.entry(&"butterfly"))] = entry
	tracker.settings = quick
	tracker.check(0.25)
	assert_bool(tracker.journal.is_seen(&"butterfly")).is_true()
	assert_float(JOURNAL.entry(&"fish").sight_seconds).is_between(0.1, 0.5)
