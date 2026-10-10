class_name HamletSettings
extends Resource
## Where rural hamlets appear and how they are laid out ([HamletPlan]). Values live in
## [code]data/hamlets/hamlets.tres[/code].

@export_group("Where")
## Side of the square cells the world is split into; each may hold one hamlet (m).
@export_range(200.0, 10000.0, 10.0, "suffix:m") var cell_size: float = 1500.0
## Chance that a cell holds a hamlet (when it has a suitable site).
@export_range(0.0, 1.0, 0.01) var chance: float = 0.45
## Biomes hamlets are built in (the site must be fully inside one).
@export var biomes: Array[StringName] = [&"meadow", &"hills"]
## Tries for a suitable site per cell.
@export_range(1, 32) var tries: int = 8
## Radius checked around a site (m), on a grid with this spacing (m).
@export_range(5.0, 200.0, 1.0, "suffix:m") var site_radius: float = 45.0
@export_range(2.0, 50.0, 0.5, "suffix:m") var site_step: float = 11.25
## Steepest ground allowed across a site (degrees).
@export_range(0.0, 45.0, 0.5, "suffix:°") var max_slope: float = 8.0
## The site's ground must be this far above the water (m).
@export_range(0.0, 10.0, 0.1, "suffix:m") var above_water: float = 0.5

@export_group("Layout")
## Houses per hamlet (min, max).
@export var houses: Vector2i = Vector2i(3, 6)
## Houses stand on a ring this far from the well (min, max, m).
@export var ring: Vector2 = Vector2(18.0, 28.0)
## Radius of the open yard around the well (m).
@export_range(2.0, 40.0, 0.5, "suffix:m") var yard_radius: float = 10.0
## Trees, bushes, rocks and logs are cleared this far from the well (m).
@export_range(10.0, 120.0, 1.0, "suffix:m") var clear_radius: float = 40.0
## Scale applied to every piece's model (the pack is modelled at a tenth of a metre).
@export_range(0.1, 10.0, 0.05) var model_scale: float = 3.0
## Pieces by id: [code]house[/code] variants, [code]stable[/code], [code]well[/code],
## [code]fence[/code] and the small props.
@export var pieces: Array[HamletPiece] = []
## Ids of the house variants.
@export var house_ids: Array[StringName] = [&"house_a", &"house_b", &"house_c"]
## Ids of the small props scattered by the houses.
@export var prop_ids: Array[StringName] = [&"cart", &"barrel", &"hay", &"crate", &"bench"]
## Props per house (min, max).
@export var props_per_house: Vector2i = Vector2i(1, 3)
## Hamlets this close but not yet built show a tall smoke plume, a clue seen from afar (m), and
## how high it rises (m).
@export_range(100.0, 5000.0, 10.0, "suffix:m") var plume_radius: float = 1200.0
@export_range(5.0, 80.0, 1.0, "suffix:m") var plume_height: float = 60.0
## Ids of the vegetable patch and the hens' nest (food, Phase 16; pieces without a model).
@export var patch_id: StringName = &"patch"
@export var nest_id: StringName = &"nest"


## The piece with [param id], or null.
func piece(id: StringName) -> HamletPiece:
	for p in pieces:
		if p.id == id:
			return p
	return null


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for id in house_ids + prop_ids + [&"well", &"stable", &"fence"]:
		if piece(id) == null:
			errors.append("missing piece %s" % id)
	if ring.x > ring.y or ring.x <= yard_radius:
		errors.append("ring must be ordered and outside the yard")
	if clear_radius < ring.y:
		errors.append("clear_radius must reach past the ring")
	return errors
