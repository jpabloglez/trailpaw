class_name VegetationType
extends Resource
## One kind of plant or prop: its model and how instances look, fade and collide. Placement
## rules per biome live in [VegetationEntry]. Values live in [code]data/vegetation/[/code].
##
## Sizes are in model units and multiplied by each instance's scale. The model must be a single
## mesh standing on its origin (see [code]tests/assets[/code]).

## Stable identifier (one MultiMesh per type per chunk).
@export var id: StringName = &""
## Model (a single-mesh [code].glb[/code]); empty for a [member procedural_shape].
@export var scene: PackedScene
## Mesh built in code instead of a model ([constant ProceduralMeshes.SHAPES]), e.g. the round
## berry bush the CC0 packs lack.
@export var procedural_shape: StringName = &""
## Colour of a [member procedural_shape] mesh.
@export var procedural_color: Color = Color.WHITE
## Instance scale range (uniform).
@export_range(0.05, 20.0, 0.05) var scale_min: float = 0.0
## Instance scale range (uniform).
@export_range(0.05, 20.0, 0.05) var scale_max: float = 0.0
## How much instances tilt with the ground (0 = upright, e.g. trees; 1 = follow the slope).
@export_range(0.0, 1.0, 0.05) var align_to_ground: float = 0.0
## Distance beyond which the type is not drawn.
@export_range(5.0, 1000.0, 1.0, "suffix:m") var visibility_range: float = 0.0
## Small plants only near the player: scattered in full-detail (LOD 0) chunks only.
@export var near_only: bool = false
## Wind sway strength (0 = rigid).
@export_range(0.0, 2.0, 0.05) var sway: float = 0.0
## Collision cylinder radius in model units (0 = no collision).
@export_range(0.0, 5.0, 0.01) var collision_radius: float = 0.0
## Collision cylinder height in model units.
@export_range(0.0, 10.0, 0.01) var collision_height: float = 0.0
## What interacting with an instance does (null = none): eating it, resting by it. Such
## instances in full-detail chunks become interaction targets.
@export var interaction: InteractionDefinition
## Radius of the shade the instance casts, in model units (0 = none; trees).
@export_range(0.0, 5.0, 0.01) var shade_radius: float = 0.0
## Props derived from each instance (berries on a bush, apples under an oak).
@export var drop: VegetationDrop


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if scene == null and procedural_shape == &"":
		errors.append("scene or procedural_shape must be set")
	if procedural_shape != &"" and not ProceduralMeshes.SHAPES.has(procedural_shape):
		errors.append("procedural_shape must be one of %s" % [ProceduralMeshes.SHAPES])
	if scale_min <= 0.0 or scale_min > scale_max:
		errors.append("scales must satisfy 0 < scale_min <= scale_max")
	if visibility_range <= 0.0:
		errors.append("visibility_range must be > 0")
	if collision_radius > 0.0 and collision_height <= 0.0:
		errors.append("collision_height must be > 0 when collision_radius is set")
	if interaction != null and not interaction.is_valid():
		errors.append("interaction: %s" % ", ".join(interaction.get_validation_errors()))
	if drop != null:
		for problem in drop.get_validation_errors():
			errors.append("drop: %s" % problem)
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()


## Whether instances of this type get collision shapes.
func has_collision() -> bool:
	return collision_radius > 0.0
