class_name AnimalVoice
extends AudioStreamPlayer3D
## A wild animal's call ([method FaunaSpecies.call_stream]): when greeted or played with, and
## now and then while it is near the player ([member enabled] is set by the fauna AI LOD).
## Quiet species (deer, horses, alpacas) have no call.
## [br][br]
## Budget: one timer countdown per frame.

## Whether idle calls may play (full-detail animals only).
var enabled: bool = true

var _agent: FaunaAgent
var _next_call: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	bus = &"SFX"
	unit_size = 8.0
	_agent = get_parent() as FaunaAgent
	if _agent == null or _agent.fauna == null:
		set_process(false)
		return
	stream = _agent.fauna.call_stream()
	_rng.seed = _agent.decision_seed
	_schedule()
	# The agent (our parent) is ready after us: hook its social area then.
	_agent.ready.connect(
		func() -> void:
			if _agent.social != null:
				_agent.social.started.connect(call_now),
		CONNECT_ONE_SHOT
	)
	if stream == null or _agent.fauna.call_interval.y <= 0.0:
		set_process(false)


func _process(delta: float) -> void:
	_next_call -= delta
	if _next_call <= 0.0:
		_schedule()
		if enabled:
			call_now()


## Calls now (no-op for quiet species).
func call_now() -> void:
	if stream == null:
		return
	pitch_scale = _rng.randf_range(0.92, 1.08)
	play()


func _schedule() -> void:
	var interval := _agent.fauna.call_interval
	_next_call = _rng.randf_range(interval.x, interval.y)
