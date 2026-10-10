class_name FarmAnimalKind
extends Resource
## A farm animal that lives in a hamlet's pen ([FarmLife]): its model, clips and how it moves.
## Values live in [code]data/hamlets/farm/[/code].

## Identifier (journal, tests).
@export var id: StringName = &""
## The animated model (a CC0 glTF in [code]assets/animals/[/code]).
@export var scene: PackedScene
## Scale applied to the model, and its turn so it faces −Z like every animal here (degrees).
@export_range(0.01, 10.0, 0.01) var model_scale: float = 1.0
@export_range(-180.0, 180.0, 1.0, "suffix:°") var yaw_offset: float = 180.0
## Clip played while standing, and while moving.
@export var idle_clip: String = "Armature|Idle"
@export var move_clip: String = "Armature|Walk"
## True when it moves in little hops (one per play of [member move_clip]) instead of walking.
@export var hops: bool = false
## Walking speed (m/s), or the length of a hop (m).
@export_range(0.05, 5.0, 0.05) var move: float = 0.6
## Seconds it stands between moves (min, max).
@export var idle_seconds: Vector2 = Vector2(4.0, 12.0)
## Relative chance of being picked for a pen.
@export_range(0.0, 10.0, 0.1) var weight: float = 1.0
