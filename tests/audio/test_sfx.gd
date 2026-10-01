## Tests for sound effects: footsteps by surface, animal calls (recorded and synthesised) and
## interface sounds.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const AGENT_SCENE: String = "res://scenes/fauna/fauna_agent.tscn"
const FOOTSTEPS: FootstepSettings = preload("res://data/audio/footsteps.tres")
const UI: UiSoundSettings = preload("res://data/audio/ui_sounds.tres")
const BERRIES: InteractionDefinition = preload("res://data/interactions/berries.tres")

var _saved_biome: StringName
var _saved_water: float


func before_test() -> void:
	_saved_biome = GameState.current_biome
	_saved_water = GameState.water_level


func after_test() -> void:
	GameState.current_biome = _saved_biome
	GameState.water_level = _saved_water


func _fox() -> Animal:
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	return animal


func _steps(animal: Animal) -> FootstepAudio:
	return animal.get_node("%FootstepAudio") as FootstepAudio


# --- footsteps ----------------------------------------------------------------------------


func test_the_surface_follows_the_biome_and_the_water() -> void:
	var steps := _steps(_fox())
	GameState.water_level = -INF
	GameState.current_biome = &"meadow"
	assert_int(steps.surface()).is_equal(FootstepAudio.Surface.GRASS)
	GameState.current_biome = &"hills"
	assert_int(steps.surface()).is_equal(FootstepAudio.Surface.GROUND)
	GameState.water_level = 0.3  # the fox's paws (y ≈ 0) are under water
	assert_int(steps.surface()).is_equal(FootstepAudio.Surface.WATER)


func test_each_step_plays_a_clip_of_its_surface_on_the_sfx_bus() -> void:
	var steps := _steps(_fox())
	GameState.water_level = -INF
	GameState.current_biome = &"meadow"
	var player := steps.step()
	assert_object(player).is_not_null()
	assert_bool(FOOTSTEPS.grass.has(player.stream)).is_true()
	assert_str(String(player.bus)).is_equal("SFX")
	assert_float(player.pitch_scale).is_between(FOOTSTEPS.pitch.x, FOOTSTEPS.pitch.y)
	await get_tree().create_timer(FOOTSTEPS.min_interval + 0.02).timeout
	GameState.current_biome = &"hills"
	assert_bool(FOOTSTEPS.ground.has(steps.step().stream)).is_true()


func test_steps_too_close_together_are_skipped() -> void:
	var steps := _steps(_fox())
	assert_object(steps.step()).is_not_null()
	assert_object(steps.step()).is_null()


func test_the_animation_footsteps_are_heard() -> void:
	var fox := _fox()
	var controller := fox.get_node("%AnimationController") as AnimationController
	controller.footstep.emit(&"FF.L")
	var any_playing := false
	for player in _steps(fox).get_children():
		any_playing = any_playing or (player as AudioStreamPlayer3D).playing
	assert_bool(any_playing).is_true()


# --- animals ------------------------------------------------------------------------------


func test_the_yip_is_a_short_clean_call() -> void:
	var yip := SynthSounds.yip()
	assert_float(yip.get_length()).is_between(0.15, 0.35)
	var data := yip.data
	var peak := 0
	for i in range(0, data.size(), 2):
		peak = maxi(peak, absi(data.decode_s16(i)))
	assert_int(peak).is_greater(8000)
	assert_int(absi(data.decode_s16(0))).is_less(500)  # no click at either end
	assert_int(absi(data.decode_s16(data.size() - 2))).is_less(2000)


func test_the_yip_is_synthesised_once_and_shared() -> void:
	assert_object(SynthSounds.yip()).is_same(SynthSounds.yip())


func _agent(id: String) -> FaunaAgent:
	var agent: FaunaAgent = auto_free(load(AGENT_SCENE).instantiate())
	agent.fauna = load("res://data/fauna/%s.tres" % id)
	add_child(agent)
	return agent


func test_donkeys_bray_shibas_yip_and_deer_stay_quiet() -> void:
	assert_object((_agent("donkey").get_node("%Voice") as AnimalVoice).stream).is_not_null()
	assert_object((_agent("shiba_inu").get_node("%Voice") as AnimalVoice).stream).is_not_null()
	var deer := _agent("deer").get_node("%Voice") as AnimalVoice
	assert_object(deer.stream).is_null()
	deer.call_now()
	assert_bool(deer.playing).is_false()


func test_a_greeted_animal_calls_back() -> void:
	var donkey := _agent("donkey")
	var voice := donkey.get_node("%Voice") as AnimalVoice
	donkey.social.started.emit()
	assert_bool(voice.playing).is_true()
	assert_str(String(voice.bus)).is_equal("SFX")


func test_only_nearby_animals_call_on_their_own() -> void:
	var shiba := _agent("shiba_inu")
	var voice := shiba.get_node("%Voice") as AnimalVoice
	voice.set_process(false)
	voice.enabled = false  # the AI LOD: not full detail
	voice._process(shiba.fauna.call_interval.y + 1.0)
	assert_bool(voice.playing).is_false()
	voice.enabled = true
	voice._process(shiba.fauna.call_interval.y + 1.0)
	assert_bool(voice.playing).is_true()


# --- interface ----------------------------------------------------------------------------


func _ui(fox: Animal) -> UiSounds:
	var ui: UiSounds = auto_free(UiSounds.new())
	ui.settings = UI
	ui.interactor = fox.get_node("%Interactor")
	ui.sniffer = fox.get_node("%Sniffer")
	add_child(ui)
	return ui


func test_interface_sounds_for_prompt_critical_need_and_sniff() -> void:
	var fox := _fox()
	var ui := _ui(fox)
	var interactor := fox.get_node("%Interactor") as Interactor
	interactor.target_changed.emit(InteractionTarget.new(BERRIES, Vector3.ZERO, self))
	assert_object(ui.player().stream).is_same(UI.prompt)
	assert_bool(ui.player().playing).is_true()
	EventBus.need_critical.emit(&"thirst")
	assert_object(ui.player().stream).is_same(UI.need_critical)
	(fox.get_node("%Sniffer") as Sniffer).sniffed.emit(3)
	assert_object(ui.player().stream).is_same(UI.sniff)
	assert_str(String(ui.player().bus)).is_equal("SFX")


func test_the_prompt_pluck_plays_once_per_appearance() -> void:
	var fox := _fox()
	var ui := _ui(fox)
	var interactor := fox.get_node("%Interactor") as Interactor
	var berries := InteractionTarget.new(BERRIES, Vector3.ZERO, self)
	interactor.target_changed.emit(berries)
	ui.player().stop()
	interactor.target_changed.emit(berries)  # another target while one is shown: no pluck
	assert_bool(ui.player().playing).is_false()
	interactor.target_changed.emit(null)
	interactor.target_changed.emit(berries)
	assert_bool(ui.player().playing).is_true()
