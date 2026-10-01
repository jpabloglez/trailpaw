class_name FootstepSettings
extends Resource
## Footstep sounds by surface. Values live in [code]data/audio/footsteps.tres[/code].

## Steps on grass (most biomes).
@export var grass: Array[AudioStream] = []
## Steps on bare ground and rock.
@export var ground: Array[AudioStream] = []
## Steps in shallow water.
@export var water: Array[AudioStream] = []
## Biomes whose ground is bare (hills).
@export var ground_biomes: Array[StringName] = []
## Water deeper than this over the paws counts as wading (m).
@export_range(0.0, 1.0, 0.01, "suffix:m") var wading_depth: float = 0.02
## Random pitch range (small paws step higher).
@export var pitch: Vector2 = Vector2(1.0, 1.0)
## Volume per surface: grass, ground, water.
@export var volume_db: Vector3 = Vector3.ZERO
## Steps closer together than this are skipped (s).
@export_range(0.0, 1.0, 0.01, "suffix:s") var min_interval: float = 0.0
## Audio bus.
@export var bus: StringName = &"SFX"
