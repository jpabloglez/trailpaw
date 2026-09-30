class_name FaunaPerception
extends RefCounted
## What an animal knows about the player at a perception tick (plain values, reused).

## Horizontal distance to the player (INF when there is none).
var player_distance: float = INF
## How fast the player closes in (m/s, positive = coming closer).
var closing_speed: float = 0.0
## Horizontal direction from the animal to the player (unit, zero when none).
var to_player: Vector3 = Vector3.ZERO
## The player's position (global).
var player_position: Vector3 = Vector3.ZERO
