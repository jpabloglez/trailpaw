## Tests for the explored area ([ExploredMap], [ExplorationTracker]): what a reveal covers, the
## water marks, the JSON round-trip and revealing as the animal walks (also across a rebase).
extends GdUnitTestSuite

const SETTINGS: ExplorationSettings = preload("res://data/world/exploration.tres")


func _map() -> ExploredMap:
	return ExploredMap.new(SETTINGS)


func test_reveal_covers_the_cells_within_the_radius() -> void:
	var map := _map()
	var at := Vector3(1000.0, 5.0, -2000.0)
	var added := map.reveal(at, SETTINGS.reveal_radius)
	assert_int(added).is_greater(0)
	assert_int(map.cell_count()).is_equal(added)
	assert_bool(map.is_explored(at.x, at.z)).is_true()
	var inside := SETTINGS.reveal_radius - SETTINGS.cell_size
	assert_bool(map.is_explored(at.x + inside, at.z)).is_true()
	var outside := SETTINGS.reveal_radius + SETTINGS.cell_size
	assert_bool(map.is_explored(at.x + outside, at.z)).is_false()
	assert_bool(map.is_explored(at.x + inside, at.z + inside)).is_false()  # a disc, not a square
	# About π r² of area.
	var area := added * SETTINGS.cell_size * SETTINGS.cell_size
	assert_float(area / (PI * SETTINGS.reveal_radius ** 2)).is_between(0.8, 1.25)


func test_revealing_again_adds_nothing_and_keeps_the_revision() -> void:
	var map := _map()
	map.reveal(Vector3.ZERO, SETTINGS.reveal_radius)
	var revision := map.revision
	assert_int(map.reveal(Vector3(1, 0, 1), SETTINGS.reveal_radius)).is_equal(0)
	assert_int(map.revision).is_equal(revision)
	map.reveal(Vector3(500, 0, 0), SETTINGS.reveal_radius)
	assert_int(map.revision).is_greater(revision)


func test_water_marks_merge_nearby_and_keep_a_limit() -> void:
	var map := _map()
	map.add_water_mark(Vector3(0, -6, 0))
	map.add_water_mark(Vector3(10, -6, 0))  # the same lake: replaced
	assert_int(map.water_marks().size()).is_equal(1)
	assert_float(map.water_marks()[0].x).is_equal(10.0)
	for i in SETTINGS.max_water_marks + 5:
		map.add_water_mark(Vector3(1000.0 * (i + 1), -6, 0))
	var marks := map.water_marks()
	assert_int(marks.size()).is_equal(SETTINGS.max_water_marks)
	assert_float(marks[marks.size() - 1].x).is_equal(1000.0 * (SETTINGS.max_water_marks + 5))


func test_round_trip_through_json() -> void:
	var map := _map()
	map.reveal(Vector3(-12345.5, 0, 6789.25), SETTINGS.reveal_radius)
	map.reveal(Vector3(300, 0, 300), SETTINGS.reveal_radius)
	map.add_water_mark(Vector3(242.9, -6, -699.2))
	var back := _map()
	back.from_dict(JSON.parse_string(JSON.stringify(map.to_dict())))
	assert_int(back.cell_count()).is_equal(map.cell_count())
	assert_bool(back.is_explored(-12345.5, 6789.25)).is_true()
	assert_bool(back.is_explored(300, 300)).is_true()
	assert_bool(back.is_explored(5000, 5000)).is_false()
	assert_vector(back.water_marks()[0]).is_equal_approx(
		Vector3(242.9, -6, -699.2), Vector3.ONE * 1e-3
	)


func test_an_empty_or_foreign_dictionary_gives_a_blank_map() -> void:
	var map := _map()
	map.reveal(Vector3.ZERO, SETTINGS.reveal_radius)
	map.from_dict({})
	assert_int(map.cell_count()).is_equal(0)
	map.from_dict({"cell_size": SETTINGS.cell_size * 2.0, "cells": [0, 0]})
	assert_int(map.cell_count()).is_equal(0)  # another grid: dropped, not misplaced


func test_the_tracker_reveals_as_the_animal_walks_even_after_a_rebase() -> void:
	var walker: Node3D = auto_free(Node3D.new())
	add_child(walker)
	var tracker: ExplorationTracker = auto_free(ExplorationTracker.new())
	tracker.settings = SETTINGS
	tracker.target = walker
	add_child(tracker)
	tracker.set_process(false)
	var saved_origin := GameState.origin_chunk
	var saved_size := GameState.chunk_size
	GameState.chunk_size = 64.0
	GameState.origin_chunk = Vector2i(100, -20)  # local 0 is absolute (6400, -1280)
	walker.position = Vector3(10, 0, 10)
	tracker.reveal_now()
	assert_bool(tracker.explored.is_explored(6410.0, -1270.0)).is_true()
	assert_bool(tracker.explored.is_explored(10.0, 10.0)).is_false()  # local, not absolute
	walker.position = Vector3(400, 0, 10)
	tracker._process(SETTINGS.interval * 0.5)
	assert_bool(tracker.explored.is_explored(6800.0, -1270.0)).is_false()  # not yet
	tracker._process(SETTINGS.interval * 0.6)
	assert_bool(tracker.explored.is_explored(6800.0, -1270.0)).is_true()
	GameState.origin_chunk = saved_origin
	GameState.chunk_size = saved_size


func test_scented_water_becomes_a_mark() -> void:
	var tracker: ExplorationTracker = auto_free(ExplorationTracker.new())
	tracker.settings = SETTINGS
	var sniffer: Sniffer = auto_free(Sniffer.new())
	tracker.sniffer = sniffer
	add_child(tracker)
	sniffer.water_scented.emit(Vector3(242.9, -6, -699.2))
	assert_int(tracker.explored.water_marks().size()).is_equal(1)
