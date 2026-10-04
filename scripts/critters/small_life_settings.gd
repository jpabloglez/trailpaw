class_name SmallLifeSettings
extends Resource
## Butterflies by day and fireflies at night ([Butterflies], [Fireflies]). Values live in
## [code]data/critters/small_life.tres[/code].

@export_group("Butterflies")
## Biomes where butterflies visit the flowers.
@export var butterfly_biomes: Array[StringName] = []
## Most butterflies around the player.
@export_range(0, 64) var max_butterflies: int = 14
## One butterfly per this many flowers nearby.
@export_range(1, 50) var flowers_per_butterfly: int = 6
## Flowers this close to the player get visitors; farther butterflies leave (m).
@export_range(5.0, 100.0, 1.0, "suffix:m") var butterfly_radius: float = 22.0
## Flitting and scattering speeds (m/s).
@export_range(0.1, 10.0, 0.1, "suffix:m/s") var flit_speed: float = 1.1
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var scatter_speed: float = 3.5
## The fox within this distance moving faster than [member scare_speed] scatters them.
@export_range(0.0, 20.0, 0.1, "suffix:m") var scare_radius: float = 2.5
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var scare_speed: float = 2.5
## Wing colours.
@export var butterfly_palette: Array[Color] = []

@export_group("Fireflies")
## Biomes with fireflies at night.
@export var firefly_biomes: Array[StringName] = []
## Fireflies drifting around the player at full night.
@export_range(1, 256) var firefly_amount: int = 40
## Size of the box around the player they drift in (m).
@export var firefly_box: Vector3 = Vector3(28.0, 2.0, 28.0)
## Glow colour.
@export var firefly_color: Color = Color(0.85, 1.0, 0.45)
