class_name HamletPiece
extends Resource
## One kind of piece a hamlet is built from (a house, the well, a fence panel, a cart…): its
## model and how much room it takes. Values live in [code]data/hamlets/pieces/[/code].

## Identifier (layouts refer to pieces by it).
@export var id: StringName = &""
## The model (a CC0 glTF in [code]assets/village/[/code]).
@export var scene: PackedScene
## Radius of the ground it takes (m): pieces never overlap and no plant grows inside.
@export_range(0.1, 20.0, 0.1, "suffix:m") var footprint: float = 1.0
## Turn added to the layout's yaw so the model's front faces where the layout wants (degrees).
@export_range(-180.0, 180.0, 1.0, "suffix:°") var yaw_offset: float = 0.0
## Whether it gets a chimney with smoke.
@export var smoke: bool = false
## Height of the chimney top above the ground, as a fraction of the model's height.
@export_range(0.0, 1.0, 0.01) var smoke_height: float = 0.9
## Whether it collides (houses, the well, fences: the fox walks round them).
@export var solid: bool = true
