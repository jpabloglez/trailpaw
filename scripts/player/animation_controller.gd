class_name AnimationController
extends Node
## Drives the animal model's animations from gameplay: builds an [AnimationTree] in code with a
## state machine (locomotion blend space, jump, fall, swim, one-shot actions) and follows the
## [StateMachine] and [MovementComponent].
##
## Locomotion is a [AnimationNodeBlendSpace1D] over horizontal speed (idle, walk, trot, run
## clips at the species' gait speeds) behind a time scale that matches the clips' authored
## ground speed ([member AnimalSpecies.clip_ground_speeds]) so paws do not slide, capped at
## [member AnimalSpecies.max_animation_time_scale]. Loops are set on copies of the clips (the
## imported resources are never modified).
## [br][br]
## Budget: two parameter writes per frame; the tree is built once.

## Library name holding the looped copies of the model's clips.
const LIBRARY: StringName = &"trailpaw"
## Cross-fade between animation states (s).
const XFADE: float = 0.18
## Gameplay state → animation state (see [PlayerState]).
const STATE_MAP: Dictionary = {
	&"Idle": &"locomotion",
	&"Locomotion": &"locomotion",
	&"Jump": &"jump",
	&"Fall": &"fall",
	&"Swim": &"swim",
}
## One-shot actions (triggered by gameplay in Phase 7); they return to locomotion when done.
const ACTIONS: Array[StringName] = [&"eat", &"drink", &"lie_down", &"sniff"]

## Movement providing speed.
@export var movement: MovementComponent
## Gameplay state machine followed by the animation state machine.
@export var state_machine: StateMachine
## Node holding the instanced model (its [AnimationPlayer] is used).
@export var model_root: Node3D

var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _species: AnimalSpecies
var _current: StringName = &"locomotion"


func _ready() -> void:
	set_process(false)  # enabled by initialize() once the model exists


## Builds the tree for the model under [member model_root]. Called by [Animal] after it has
## instanced the species model (children are ready before their parent).
func initialize() -> void:
	_species = movement.species if movement != null else null
	if _species == null or _species.model_scene == null or model_root == null:
		return
	var player := (
		model_root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	)
	_add_looped_library(player)
	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	model_root.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(player)
	_tree.tree_root = _build_state_machine()
	_tree.active = true
	_playback = _tree.get("parameters/playback")
	_playback.start(&"locomotion")
	if state_machine != null:
		state_machine.state_changed.connect(_on_state_changed)
	set_process(true)


func _process(_delta: float) -> void:
	var speed := movement.horizontal_speed()
	_tree.set("parameters/locomotion/gait/blend_position", speed)
	_tree.set("parameters/locomotion/scale/scale", time_scale_for(speed, _species))


## Plays one-shot [param action] (see [constant ACTIONS]); it returns to locomotion when done.
func play_action(action: StringName) -> void:
	if ACTIONS.has(action):
		_travel(action)


## Current animation state name.
func current_state() -> StringName:
	return _playback.get_current_node() if _playback != null else &""


## The [AnimationTree] (for tests and tools).
func tree() -> AnimationTree:
	return _tree


## Locomotion playback scale at [param speed]: the idle→walk part blends from 1 towards the
## walk-matched scale; walk→trot interpolates walk- and gallop-matched scales like the blend
## space does; above that the run clip is matched. Capped by the species' maximum.
static func time_scale_for(speed: float, species: AnimalSpecies) -> float:
	var walk_clip: float = species.clip_ground_speeds.get(species.animations[&"walk"], 1.0)
	var run_clip: float = species.clip_ground_speeds.get(species.animations[&"run"], 1.0)
	var trot_clip: float = species.clip_ground_speeds.get(species.animations[&"trot"], run_clip)
	var scale: float
	if speed <= species.walk_speed:
		scale = lerpf(1.0, speed / walk_clip, clampf(speed / species.walk_speed, 0.0, 1.0))
	elif speed <= species.trot_speed:
		var t := (speed - species.walk_speed) / (species.trot_speed - species.walk_speed)
		scale = lerpf(speed / walk_clip, speed / trot_clip, t)
	else:
		var t := (speed - species.trot_speed) / (species.run_speed - species.trot_speed)
		scale = lerpf(speed / trot_clip, speed / run_clip, clampf(t, 0.0, 1.0))
	return clampf(scale, 0.0, species.max_animation_time_scale)


func _add_looped_library(player: AnimationPlayer) -> void:
	var library := AnimationLibrary.new()
	var added := {}
	for logical: StringName in _species.animations:
		var clip: String = _species.animations[logical]
		if added.has(clip):
			continue
		var anim := player.get_animation(clip).duplicate() as Animation
		var loops := false
		for l: StringName in _species.looping:
			loops = loops or _species.animations[l] == clip
		anim.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
		library.add_animation(clip, anim)
		added[clip] = true
	player.add_animation_library(LIBRARY, library)


func _clip_node(logical: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = "%s/%s" % [LIBRARY, _species.animations[logical]]
	return node


func _build_state_machine() -> AnimationNodeStateMachine:
	var machine := AnimationNodeStateMachine.new()
	var gait := AnimationNodeBlendSpace1D.new()
	gait.min_space = 0.0
	gait.max_space = _species.run_speed
	gait.add_blend_point(_clip_node(&"idle"), 0.0)
	gait.add_blend_point(_clip_node(&"walk"), _species.walk_speed)
	gait.add_blend_point(_clip_node(&"trot"), _species.trot_speed)
	gait.add_blend_point(_clip_node(&"run"), _species.run_speed)
	var locomotion := AnimationNodeBlendTree.new()
	locomotion.add_node(&"gait", gait)
	locomotion.add_node(&"scale", AnimationNodeTimeScale.new())
	locomotion.connect_node(&"scale", 0, &"gait")
	locomotion.connect_node(&"output", 0, &"scale")
	machine.add_node(&"locomotion", locomotion)
	for logical: StringName in [&"jump", &"fall", &"swim"]:
		machine.add_node(logical, _clip_node(logical))
		_connect(machine, &"locomotion", logical)
	_connect(machine, &"jump", &"fall")
	_connect(machine, &"fall", &"swim")
	_connect(machine, &"jump", &"swim")
	for action: StringName in ACTIONS:
		machine.add_node(action, _clip_node(action))
		_connect_one(machine, &"locomotion", action)
		var back := AnimationNodeStateMachineTransition.new()
		back.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		back.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		back.xfade_time = XFADE
		machine.add_transition(action, &"locomotion", back)
	return machine


func _connect_one(machine: AnimationNodeStateMachine, a: StringName, b: StringName) -> void:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = XFADE
	machine.add_transition(a, b, transition)


func _connect(machine: AnimationNodeStateMachine, a: StringName, b: StringName) -> void:
	for pair: Array in [[a, b], [b, a]]:
		if machine.has_transition(pair[0], pair[1]):
			continue
		var transition := AnimationNodeStateMachineTransition.new()
		transition.xfade_time = XFADE
		machine.add_transition(pair[0], pair[1], transition)


func _on_state_changed(_from: StringName, to: StringName) -> void:
	_travel(STATE_MAP.get(to, &"locomotion"))


func _travel(state: StringName) -> void:
	_current = state
	_playback.travel(state)
