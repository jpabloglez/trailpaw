class_name IslandSettings
extends Resource
## Where island treasures are and what they look like ([IslandPlan], [IslandDirector];
## Phase 19). Values live in [code]data/world/islands.tres[/code].

## Side of the square cells the world is cut into; each may hold one treasure (m).
@export_range(100.0, 2000.0, 10.0, "suffix:m") var cell_size: float = 300.0
## Chance that a cell holding an island gets a treasure on it.
@export_range(0.0, 1.0, 0.01) var chance: float = 0.8
## Random spots tried per cell to find an island.
@export_range(1, 32) var tries: int = 10
## Biomes where treasure islands may be.
@export var biomes: Array[StringName] = [&"lakes"]
## The spot must stand this far above the water (m).
@export_range(0.0, 10.0, 0.1, "suffix:m") var above_water: float = 1.0
## Every one of [constant IslandPlan.RAYS] rays from the top must reach the water within this
## distance: an island, not the shore of the mainland (m).
@export_range(20.0, 500.0, 5.0, "suffix:m") var max_reach: float = 150.0
## …and the nearest water must be at least this far: an island to stand on, not a rock (m).
@export_range(0.0, 100.0, 1.0, "suffix:m") var min_reach: float = 14.0
## Step of the rays (m).
@export_range(1.0, 20.0, 0.5, "suffix:m") var ray_step: float = 8.0
## Hill-climbing steps towards the island's top, and their length (m).
@export_range(0, 20) var climb_steps: int = 6
@export_range(1.0, 20.0, 0.5, "suffix:m") var climb_step: float = 6.0
## Weights of the treasures, in the order of [enum IslandPlan.Treasure].
@export var weights := PackedFloat32Array([1.0, 1.0, 1.0])
## Tall plants (trees, bushes, rocks) are cleared within this distance of a treasure (m).
@export_range(0.0, 50.0, 0.5, "suffix:m") var clear_radius: float = 10.0

@export_group("Discovery")
## A treasure counts as found within this distance of the fox (m).
@export_range(1.0, 50.0, 0.5, "suffix:m") var discover_radius: float = 12.0
## Treasures closer than this are built, and freed beyond [member free_radius] (m).
@export_range(50.0, 1000.0, 10.0, "suffix:m") var build_radius: float = 260.0
@export_range(50.0, 1500.0, 10.0, "suffix:m") var free_radius: float = 340.0

@export_group("Ancient tree")
## The tree's vegetation type (its look matches its smaller kin, through the [WorldStreamer]'s
## foliage mesh), and its scale (a giant among the pines).
@export var tree_type: VegetationType
@export_range(0.5, 20.0, 0.1) var tree_scale: float = 12.0
## Shade radius under its crown, and the trunk's collision radius (m).
@export_range(0.0, 30.0, 0.5, "suffix:m") var tree_shade: float = 7.0
@export_range(0.0, 5.0, 0.05, "suffix:m") var tree_trunk: float = 0.9
## Motes of light drifting round its crown at dusk and night.
@export var mote_color: Color = Color(1.0, 0.86, 0.5)
@export_range(0, 200) var motes: int = 70

@export_group("Rare flowers")
## Flowers in the ring, its radius (m), and their colours (found nowhere else).
@export_range(0, 400) var flowers: int = 90
@export_range(1.0, 20.0, 0.5, "suffix:m") var flower_radius: float = 6.0
@export var flower_colors := PackedColorArray(
	[Color(0.55, 0.42, 0.95), Color(0.98, 0.85, 0.35), Color(0.4, 0.85, 0.95)]
)

@export_group("Otter den")
## Logs heaped into the den.
@export_range(1, 20) var den_logs: int = 7


## Problems that would break placement (empty when valid).
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if weights.size() != 3:
		errors.append("weights needs one value per treasure (3)")
	if min_reach >= max_reach:
		errors.append("min_reach must be below max_reach")
	if max_reach * 2.0 > cell_size * 1.5:
		errors.append("max_reach too large for the cells")
	if free_radius <= build_radius:
		errors.append("free_radius must exceed build_radius")
	if tree_type == null or tree_type.scene == null:
		errors.append("no tree_type with a model")
	return errors
