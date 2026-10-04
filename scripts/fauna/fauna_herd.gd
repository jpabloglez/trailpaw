class_name FaunaHerd
extends RefCounted
## The animals that spawned together and live as a group: they wander around the group's
## current centre (not each around its own spawn point), drift back when they stray beyond the
## leash, and when one of them flees the others close by flee with it.
## [br][br]
## Budget: a pass over ≤ 5 members per call.

## Members still alive.
var members: Array[FaunaAgent] = []
## Members drift back beyond this distance from the centre (m).
var leash: float = 10.0
## Fleeing spreads to members within this distance (m)…
var alarm_radius: float = 15.0
## …for this long (s).
var alarm_seconds: float = 3.0


## Adds [param agent] (it keeps a reference to this herd).
func add(agent: FaunaAgent) -> void:
	members.append(agent)
	agent.herd = self


## Removes [param agent] (when it leaves the world).
func remove(agent: FaunaAgent) -> void:
	members.erase(agent)


## Live members.
func size() -> int:
	return members.size()


## Average position of the live members (local), or [constant Vector3.INF] when empty.
func centroid() -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for member in members:
		if is_instance_valid(member) and member.is_inside_tree():
			sum += member.global_position
			count += 1
	return sum / count if count > 0 else Vector3.INF


## [param source] started to flee: the other members within [member alarm_radius] are alarmed
## for [member alarm_seconds] and flee too. Returns how many were alarmed.
func alarm(source: FaunaAgent) -> int:
	var alarmed := 0
	for member in members:
		if member == source or not is_instance_valid(member) or member.brain == null:
			continue
		if member.global_position.distance_to(source.global_position) <= alarm_radius:
			member.brain.alarm(alarm_seconds)
			alarmed += 1
	return alarmed
