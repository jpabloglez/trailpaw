## Tests for every species' animation set: coverage, documented fallbacks, loops, clip speeds.
extends GdUnitTestSuite

const SPECIES_PATHS: Array[String] = [
	"res://data/species/husky.tres",
	"res://data/species/fox.tres",
]

var _species: AnimalSpecies


func _each() -> Array[AnimalSpecies]:
	var out: Array[AnimalSpecies] = []
	for path in SPECIES_PATHS:
		out.append(load(path) as AnimalSpecies)
	return out


func _player() -> AnimationPlayer:
	var model: Node = auto_free(_species.model_scene.instantiate())
	return model.find_children("*", "AnimationPlayer", true, false)[0]


func test_every_logical_animation_resolves_to_a_clip() -> void:
	for species in _each():
		_species = species
		var player := _player()
		for logical: StringName in AnimalSpecies.LOGICAL_ANIMATIONS:
			(
				assert_bool(_species.animations.has(logical))
				. override_failure_message(String(logical))
				. is_true()
			)
			var clip := _species.animations[logical]
			assert_bool(player.has_animation(clip)).override_failure_message(clip).is_true()


func test_only_documented_fallbacks_share_or_substitute_clips() -> void:
	for species in _each():
		_species = species
		var by_clip := {}
		for logical: StringName in AnimalSpecies.LOGICAL_ANIMATIONS:
			var clip := _species.animations[logical]
			if not by_clip.has(clip):
				by_clip[clip] = []
			(by_clip[clip] as Array).append(logical)
		for clip: String in by_clip:
			var users: Array = by_clip[clip]
			var undocumented := users.filter(
				func(l: StringName) -> bool: return not _species.animation_fallbacks.has(l)
			)
			(
				assert_int(undocumented.size())
				. override_failure_message(
					"clip %s shared by %s without a documented fallback" % [clip, users]
				)
				. is_less_equal(1)
			)
		for logical: StringName in _species.animation_fallbacks:
			assert_str(_species.animation_fallbacks[logical]).is_not_empty()


func test_locomotion_loops_and_one_shots_do_not() -> void:
	for species in _each():
		_species = species
		for logical: StringName in [&"idle", &"walk", &"trot", &"run", &"swim"]:
			assert_bool(_species.looping.has(logical)).is_true()
		for logical: StringName in [&"jump", &"eat", &"drink", &"sniff"]:
			assert_bool(_species.looping.has(logical)).is_false()


func test_clip_ground_speeds_match_the_animation() -> void:
	for species in _each():
		_species = species
		var model: Node3D = auto_free(_species.model_scene.instantiate())
		model.scale = Vector3.ONE * _species.model_scale
		add_child(model)
		for clip: String in _species.clip_ground_speeds:
			var measured := ClipAnalysis.ground_speed(model, clip, _species.paw_bones)
			assert_float(_species.clip_ground_speeds[clip]).is_equal_approx(
				measured, measured * 0.1
			)
		assert_float(_species.clip_ground_speeds["Gallop"]).is_greater(
			_species.clip_ground_speeds["Walk"]
		)


func test_placeholder_species_without_model_stays_valid() -> void:
	var placeholder := load("res://data/species/placeholder.tres") as AnimalSpecies
	assert_object(placeholder.model_scene).is_null()
	assert_bool(placeholder.is_valid()).is_true()


func test_species_with_model_must_cover_the_animation_set() -> void:
	for species in _each():
		_species = species
		var broken := _species.duplicate() as AnimalSpecies
		var partial := _species.animations.duplicate()
		partial.erase(&"swim")
		broken.animations = partial
		assert_array(Array(broken.get_validation_errors())).contains(
			["animations is missing 'swim'"]
		)
