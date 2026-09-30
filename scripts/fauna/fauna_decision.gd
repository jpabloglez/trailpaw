class_name FaunaDecision
extends RefCounted
## Pure behaviour choice for fauna: given the current behaviour, whether it has finished, what
## the animal perceives and its [FaunaProfile], returns the behaviour to be in. An unfinished
## moment with the player (social, play, follow) comes first, then threats, then an ongoing or
## new approach, then idle time (wander / graze / rest by weight).

const WANDER: StringName = &"Wander"
const GRAZE: StringName = &"Graze"
const REST: StringName = &"Rest"
const FLEE: StringName = &"Flee"
const APPROACH: StringName = &"Approach"
const FOLLOW: StringName = &"Follow"
const SOCIAL: StringName = &"Social"
const PLAY: StringName = &"Play"


## Next behaviour. [param roll] and [param approach_roll] are uniform randoms in [0, 1).
static func decide(
	current: StringName,
	done: bool,
	perception: FaunaPerception,
	profile: FaunaProfile,
	roll: float,
	approach_roll: float
) -> StringName:
	var d := perception.player_distance
	if (current == SOCIAL or current == PLAY or current == FOLLOW) and not done:
		return current  # a moment with the player is never cut short
	if profile.flee_radius > 0.0 and d < profile.flee_radius:
		var startled := d < profile.startle_radius
		if startled or perception.closing_speed > profile.flee_trigger_speed:
			return FLEE
	if current == FLEE and d < profile.safe_distance:
		return FLEE
	if current == APPROACH and not done:
		return APPROACH
	if (
		current != APPROACH
		and done
		and profile.approach_radius > 0.0
		and d < profile.approach_radius
		and d > profile.approach_stop_distance
		and approach_roll < profile.approach_chance
	):
		return APPROACH
	if not done and current != FLEE and current != APPROACH:
		return current
	return idle_choice(profile, roll)


## Idle behaviour for [param roll] by the profile's weights.
static func idle_choice(profile: FaunaProfile, roll: float) -> StringName:
	var w := profile.idle_weights
	var total := w.x + w.y + w.z
	var r := roll * total
	if r < w.x:
		return WANDER
	if r < w.x + w.y:
		return GRAZE
	return REST
