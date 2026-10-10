class_name VillagerSettings
extends Resource
## The hamlets' villagers ([Villagers]): their look, their day and how wary they are of the fox.
## Values live in [code]data/hamlets/villagers.tres[/code].

## The animated model and its scale (it is modelled ≈ 5.3 units tall).
@export var scene: PackedScene
@export_range(0.01, 10.0, 0.01) var model_scale: float = 0.33
## Clothing palettes (one picked per villager).
@export var palettes: Array[Texture2D] = []
## Villagers per hamlet (min, max).
@export var per_hamlet: Vector2i = Vector2i(1, 3)
## Walking speed (m/s).
@export_range(0.2, 4.0, 0.05, "suffix:m/s") var walk_speed: float = 1.1

@export_group("Day")
## Hours of the day (0…24): up and out to the well, off to work, back to the well at midday,
## work again, a rest by the door, and home for the night. Each villager keeps its own offset of
## up to ± [member jitter] hours.
@export var wake: float = 6.0
@export var work: float = 7.5
@export var midday: float = 12.0
@export var afternoon: float = 14.0
@export var evening: float = 18.0
@export var night: float = 20.5
@export_range(0.0, 2.0, 0.05, "suffix:h") var jitter: float = 0.5

@export_group("Wary")
## It notices the fox this close and inside its field of view (m, degrees).
@export_range(1.0, 50.0, 0.5, "suffix:m") var notice_radius: float = 12.0
@export_range(10.0, 360.0, 1.0, "suffix:°") var field_of_view: float = 120.0
## It shoos the fox away when it comes this close (m); closer still when it is at their food.
@export_range(0.5, 30.0, 0.5, "suffix:m") var shoo_radius: float = 6.0
@export_range(0.5, 30.0, 0.5, "suffix:m") var food_shoo_radius: float = 9.0
## Seconds before the same villager shoos again.
@export_range(0.5, 30.0, 0.5, "suffix:s") var shoo_cooldown: float = 4.0
## Clips: idle, walking, working, and the shoo gesture (with its playback speed).
@export var idle_clip: String = "Idle"
@export var walk_clip: String = "Walk"
@export var work_clip: String = "Working"
@export var shoo_clip: String = "Punch"
@export_range(0.1, 3.0, 0.05) var shoo_speed: float = 0.6
