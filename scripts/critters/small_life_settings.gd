class_name SmallLifeSettings
extends Resource
## Fireflies at night ([Fireflies]; butterflies and dragonflies are [Flitters] of a
## [FlitterKind]). Values live in [code]data/critters/small_life.tres[/code].

@export_group("Fireflies")
## Biomes with fireflies at night.
@export var firefly_biomes: Array[StringName] = []
## Fireflies drifting around the player at full night.
@export_range(1, 256) var firefly_amount: int = 40
## Size of the box around the player they drift in (m).
@export var firefly_box: Vector3 = Vector3(28.0, 2.0, 28.0)
## Glow colour.
@export var firefly_color: Color = Color(0.85, 1.0, 0.45)
