class_name UiSounds
extends Node
## Quiet interface feedback: a pluck when an interaction prompt appears, a gentle chime when a
## need becomes critical, a lower one when a low need blocks an action and a whoosh when
## sniffing. Non-positional, on the SFX bus.

## Sounds and volume.
@export var settings: UiSoundSettings
## Its prompts (optional).
@export var interactor: Interactor
## Its sniffs (optional).
@export var sniffer: Sniffer

var _player: AudioStreamPlayer
var _had_target: bool = false


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = settings.bus
	_player.volume_db = settings.volume_db
	add_child(_player)
	if interactor != null:
		interactor.target_changed.connect(_on_target_changed)
	if sniffer != null:
		sniffer.sniffed.connect(func(_count: int) -> void: play(settings.sniff))
	EventBus.need_critical.connect(func(_need: StringName) -> void: play(settings.need_critical))
	EventBus.need_effect_blocked.connect(_on_need_effect_blocked)


## Plays [param stream] at [param pitch] (the last sound wins; interface sounds are short).
func play(stream: AudioStream, pitch: float = 1.0) -> void:
	if stream == null:
		return
	_player.stream = stream
	_player.pitch_scale = pitch
	_player.play()


## The player (tests and tools).
func player() -> AudioStreamPlayer:
	return _player


func _on_need_effect_blocked(_need: StringName, _ability: StringName) -> void:
	if not _player.playing or _player.stream != settings.need_blocked:
		play(settings.need_blocked, settings.need_blocked_pitch)


func _on_target_changed(target: InteractionTarget) -> void:
	if target != null and not _had_target:
		play(settings.prompt)
	_had_target = target != null
