class_name VegetationDrop
extends Resource
## Small props derived from each instance of a [VegetationType]: berry clusters on a bush,
## apples fallen under an oak. Placed deterministically per parent instance on the worker
## ([VegetationScatterer]), in full-detail (LOD 0) chunks only, with a mesh built in code
## ([VegetationLibrary]). Usually edible ([member interaction]).
##
## Offsets are in the parent's model units (they scale with the parent instance).

## How a drop is placed.
enum Placement { ON_PARENT, GROUND }
## Mesh built in code.
enum Shape { BERRY_CLUSTER, FRUIT }

## Identifier of the drop's MultiMesh (e.g. [code]&"berries"[/code]).
@export var id: StringName = &""
## Mesh built in code.
@export var shape: Shape = Shape.BERRY_CLUSTER
## Mesh colour.
@export var color: Color = Color.WHITE
## Size of the mesh (m).
@export_range(0.01, 1.0, 0.005, "suffix:m") var size: float = 0.0
## Drops per parent instance (uniform in [min, max]).
@export_range(0, 16) var count_min: int = 0
## Drops per parent instance (uniform in [min, max]).
@export_range(0, 16) var count_max: int = 0
## On the parent's surface or on the ground around it.
@export var placement: Placement = Placement.ON_PARENT
## Horizontal distance from the parent's origin (model units).
@export_range(0.0, 10.0, 0.005) var radius_min: float = 0.0
## Horizontal distance from the parent's origin (model units).
@export_range(0.0, 10.0, 0.005) var radius_max: float = 0.0
## Height above the parent's origin for ON_PARENT (model units).
@export_range(0.0, 10.0, 0.005) var height_min: float = 0.0
## Height above the parent's origin for ON_PARENT (model units).
@export_range(0.0, 10.0, 0.005) var height_max: float = 0.0
## What interacting with it does, usually eating (null = decorative).
@export var interaction: InteractionDefinition


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if size <= 0.0:
		errors.append("size must be > 0")
	if count_max <= 0 or count_min > count_max:
		errors.append("counts must satisfy 0 <= count_min <= count_max, count_max > 0")
	if radius_min > radius_max:
		errors.append("radius_min must be <= radius_max")
	if placement == Placement.ON_PARENT and height_min > height_max:
		errors.append("height_min must be <= height_max")
	if interaction != null and not interaction.is_valid():
		errors.append("interaction: %s" % ", ".join(interaction.get_validation_errors()))
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
