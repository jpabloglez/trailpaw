class_name ChunkBorderGizmo
extends MeshInstance3D
## Debug lines along the border of every loaded terrain chunk, coloured by LOD. Follows the
## F3 overlay's visibility and rebuilds only when the streamer reports a change.
##
## Budget: rebuild is O(total border points) and only happens on [signal
## WorldStreamer.chunks_changed] while visible; nothing runs per frame.

## Line colour per LOD level (index = LOD).
const LOD_COLORS: Array[Color] = [Color(1.0, 0.85, 0.2), Color(0.3, 0.85, 1.0)]
## Lift above the terrain so lines are not z-fighting with the surface.
const LIFT: float = 0.15

## Streamer whose chunks are outlined.
@export var streamer: WorldStreamer

var _lines := ImmediateMesh.new()
var _dirty: bool = true


func _ready() -> void:
	mesh = _lines
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
	EventBus.debug_overlay_toggled.connect(_on_overlay_toggled)
	if streamer != null:
		streamer.chunks_changed.connect(_mark_dirty)


func _process(_delta: float) -> void:
	if visible and _dirty:
		rebuild()


## Redraws all outlines now. Returns the number of chunks drawn.
func rebuild() -> int:
	_dirty = false
	_lines.clear_surfaces()
	if streamer == null:
		return 0
	var drawn := 0
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for coord: Vector2i in streamer.loaded_coords():
		var chunk := streamer.get_chunk(coord)
		var outline := chunk.border_outline()
		if outline.is_empty():
			continue
		var color := LOD_COLORS[mini(chunk.lod, LOD_COLORS.size() - 1)]
		var origin := chunk.position + Vector3(0.0, LIFT, 0.0)
		for k in outline.size():
			_lines.surface_set_color(color)
			_lines.surface_add_vertex(origin + outline[k])
			_lines.surface_add_vertex(origin + outline[(k + 1) % outline.size()])
		drawn += 1
	if drawn == 0:
		# An empty surface is invalid; close it with a degenerate line.
		_lines.surface_add_vertex(Vector3.ZERO)
		_lines.surface_add_vertex(Vector3.ZERO)
	_lines.surface_end()
	return drawn


func _mark_dirty() -> void:
	_dirty = true


func _on_overlay_toggled(overlay_visible: bool) -> void:
	visible = overlay_visible
	_dirty = true
