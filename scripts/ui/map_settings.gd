class_name MapSettings
extends Resource
## How the map screen looks. Values live in [code]data/ui/map.tres[/code].

## Map image side (pixels; rendered on a worker thread).
@export_range(32, 1024, 1) var image_size: int = 256
## Side of the image on screen (pixels, before UI scaling).
@export_range(64.0, 2048.0, 1.0) var display_size: float = 640.0
## Zoom levels: metres across the map, nearest first.
@export var spans: PackedFloat32Array = PackedFloat32Array([1000.0, 2000.0, 4000.0])
## Unexplored land.
@export var fog_color: Color = Color(0.86, 0.8, 0.66)
## Shallow water.
@export var shallow_color: Color = Color(0.45, 0.7, 0.85)
## Deep water.
@export var deep_color: Color = Color(0.13, 0.3, 0.52)
## Ground above the snow line (the mountain peaks).
@export var snow_color: Color = Color(0.94, 0.95, 0.97)
## Depth at which water reaches [member deep_color] (m).
@export_range(0.1, 50.0, 0.1, "suffix:m") var deep_depth: float = 6.0
## Hillshade strength (0 = flat colours).
@export_range(0.0, 10.0, 0.05) var shade: float = 1.5
## Player arrow.
@export var player_color: Color = Color(1.0, 0.45, 0.2)
## Start point marker.
@export var start_color: Color = Color(1.0, 0.95, 0.75)
## Scented water marker.
@export var water_mark_color: Color = Color(0.45, 0.8, 1.0)
## Colour of an explored hamlet's house icon (Phase 16).
@export var hamlet_color: Color = Color(0.95, 0.75, 0.45)
## Marker size on screen (pixels).
@export_range(4.0, 64.0, 1.0) var marker_size: float = 20.0
