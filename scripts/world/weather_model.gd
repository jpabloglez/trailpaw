class_name WeatherModel
extends RefCounted
## Pure, deterministic weather: a Markov chain over clear → cloudy → rain, one state per slot of
## game time, seeded by the world seed. The state of slot n depends on slot n − 1 and a roll
## seeded by (seed, n), so the same time always brings the same weather.
##
## Transition table (rows: from; columns: to clear / cloudy / rain) comes from [WeatherSettings]
## and gives ≈ 15 % rain in episodes of ~4 slots (user choice: "rain now and then").
## [br][br]
## Budget: evaluating slot n walks forward from the last evaluated slot (cached): O(1) per slot
## as time advances.

## Weather states.
enum Kind { CLEAR, CLOUDY, RAIN }

## Seed salt for weather rolls.
const SALT: int = 0x3EA7

var _seed: int
var _transitions: Array[Vector3] = []
var _cached_slot: int = -1
var _cached_state: Kind = Kind.CLEAR


func _init(world_seed: int, transitions: Array[Vector3]) -> void:
	_seed = HeightSampler.layer_seed(world_seed, SALT)
	_transitions = transitions


## Weather in slot [param slot] (slots start at 0 in CLEAR).
func state_at(slot: int) -> Kind:
	if slot <= 0:
		return Kind.CLEAR
	if slot < _cached_slot or _cached_slot < 0:
		_cached_slot = 0
		_cached_state = Kind.CLEAR
	while _cached_slot < slot:
		_cached_slot += 1
		_cached_state = next_state(_cached_state, _roll(_cached_slot))
	return _cached_state


## Kind after [param from] for a uniform [param roll] in [0, 1).
func next_state(from: Kind, roll: float) -> Kind:
	var row := _transitions[from]
	if roll < row.x:
		return Kind.CLEAR
	if roll < row.x + row.y:
		return Kind.CLOUDY
	return Kind.RAIN


func _roll(slot: int) -> float:
	return float(HeightSampler.layer_seed(_seed, slot)) / float(0x7FFFFFFF)
