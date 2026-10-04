class_name MapScreen
extends CanvasLayer
## The map (the [code]map[/code] action, M): what the player has explored around them, with
## water, the player as an arrow, the start point and the water sniffed from far away. Opening
## it pauses the world; M or Esc closes it, and the camera zoom inputs (mouse wheel) change the
## scale. The image is drawn by a [MapRenderer] on a worker thread and kept while nothing
## changed. Built in code.
## [br][br]
## Budget: on open, one worker task (see [MapRenderer]); while open, a few draw calls for the
## markers. Nothing while closed.

## Look and zoom levels.
const SETTINGS: MapSettings = preload("res://data/ui/map.tres")

## Whether M opens the map (off while in the main menu).
var enabled: bool = false
## The world being played (set by [GameFlow]).
var world: WorldController

var _root: Control
var _texture_rect: TextureRect
var _overlay: Control
var _status: Label
var _zoom: int = 0
var _renderer: MapRenderer
var _shown: MapRenderer
var _shown_revision: int = -1
var _sampler: HeightSampler
var _sampler_seed: int = 0


func _ready() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var box := MenuStyle.centred_box(_root, "MapPage")
	box.add_child(MenuStyle.label("Map", 36))
	var frame := Control.new()
	frame.name = "Frame"
	frame.custom_minimum_size = Vector2.ONE * SETTINGS.display_size
	box.add_child(frame)
	_texture_rect = TextureRect.new()
	_texture_rect.name = "Image"
	_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	frame.add_child(_texture_rect)
	_overlay = Control.new()
	_overlay.name = "Markers"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_markers)
	frame.add_child(_overlay)
	_status = MenuStyle.label("", 18, "Status")
	box.add_child(_status)
	visible = false
	set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed(&"map"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"camera_zoom_in"):
		zoom(-1)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"camera_zoom_out"):
		zoom(1)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _renderer != null and WorkerThreadPool.is_task_completed(_renderer.task_id):
		_finish_render()


func _exit_tree() -> void:
	if _renderer != null:
		WorkerThreadPool.wait_for_task_completion(_renderer.task_id)
		_renderer = null


## Pauses the world and shows the map around the player.
func open() -> void:
	if world == null:
		return
	visible = true
	MenuStyle.fade_in(_root)
	get_tree().paused = true
	EventBus.map_opened.emit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(true)
	_request_render()
	_overlay.queue_redraw()


## Hides the map and resumes the world.
func close() -> void:
	visible = false
	get_tree().paused = false
	set_process(false)


## Moves [param steps] zoom levels out (positive) or in (negative), within the levels.
func zoom(steps: int) -> void:
	var level := clampi(_zoom + steps, 0, SETTINGS.spans.size() - 1)
	if level == _zoom:
		return
	_zoom = level
	if visible:
		_request_render()


## Metres across the map at the current zoom.
func span() -> float:
	return SETTINGS.spans[_zoom]


## Whether the image is still being drawn.
func is_rendering() -> bool:
	return _renderer != null


## Waits for the drawing in progress (if any) and shows it (tests and tools).
func finish_render_now() -> void:
	if _renderer != null:
		_finish_render()


## The image shown (null before the first drawing).
func image() -> Image:
	return _shown.image if _shown != null else null


## Map pixel (fractional, in the image) of absolute point ([param x], [param z]).
func pixel_of(x: float, z: float) -> Vector2:
	return _shown.pixel_of(x, z) if _shown != null else Vector2.INF


## Unit screen direction the player arrow points (north is up).
func player_direction() -> Vector2:
	var yaw := world.animal.rotation.y
	return Vector2(-sin(yaw), -cos(yaw))


## The note under the map.
func status_text() -> String:
	return _status.text


func _player_absolute() -> Vector3:
	return GameState.absolute_position(world.animal.global_position)


func _request_render() -> void:
	var at := _player_absolute()
	var centre := Vector2(at.x, at.z)
	var explored := world.exploration.explored
	if (
		_shown != null
		and _shown_revision == explored.revision
		and is_equal_approx(_shown.span, span())
	):
		var mpp := _shown.span / SETTINGS.image_size
		if _shown.centre.distance_to(centre) < mpp * 2.0:
			return  # nothing changed since it was drawn
	if _renderer != null:
		WorkerThreadPool.wait_for_task_completion(_renderer.task_id)
		_renderer = null
	if _sampler == null or _sampler_seed != GameState.world_seed:
		_sampler = HeightSampler.new(world.streamer.terrain, GameState.world_seed)
		_sampler_seed = GameState.world_seed
	_renderer = MapRenderer.new(
		_sampler,
		explored.cells_snapshot(),
		explored.cell_size,
		centre,
		span(),
		GameState.water_level,
		SETTINGS
	)
	_shown_revision = explored.revision
	_renderer.task_id = WorkerThreadPool.add_task(_renderer.run, false, "Map")
	_status.text = "Drawing the map…"


func _finish_render() -> void:
	WorkerThreadPool.wait_for_task_completion(_renderer.task_id)
	_shown = _renderer
	_renderer = null
	_texture_rect.texture = ImageTexture.create_from_image(_shown.image)
	_status.text = "%d m across · wheel to zoom · M or Esc to close" % roundi(_shown.span)
	_overlay.queue_redraw()


func _draw_markers() -> void:
	if _shown == null or world == null:
		return
	var scale := _overlay.size.x / SETTINGS.image_size
	var r := SETTINGS.marker_size * 0.5
	var start := _shown.pixel_of(
		WorldController.NEW_GAME_POSITION.x, WorldController.NEW_GAME_POSITION.z
	)
	_marker(start * scale, r, SETTINGS.start_color, true)
	for mark in world.exploration.explored.water_marks():
		_marker(_shown.pixel_of(mark.x, mark.z) * scale, r, SETTINGS.water_mark_color, false)
	var at := _player_absolute()
	var tip := _shown.pixel_of(at.x, at.z) * scale
	var forward := player_direction()
	var side := Vector2(-forward.y, forward.x)
	var arrow := PackedVector2Array(
		[
			tip + forward * r * 1.4,
			tip - forward * r + side * r * 0.9,
			tip - forward * r * 0.4,
			tip - forward * r - side * r * 0.9,
		]
	)
	_overlay.draw_colored_polygon(arrow, SETTINGS.player_color)
	_overlay.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color.BLACK, 2.0, true)


func _marker(at: Vector2, r: float, color: Color, square: bool) -> void:
	var inside := Rect2(Vector2.ZERO, _overlay.size).grow(-r)
	if not inside.has_point(at):
		return
	if square:
		_overlay.draw_rect(Rect2(at - Vector2.ONE * r * 0.7, Vector2.ONE * r * 1.4), color)
		_overlay.draw_rect(
			Rect2(at - Vector2.ONE * r * 0.7, Vector2.ONE * r * 1.4), Color.BLACK, false, 2.0
		)
	else:
		_overlay.draw_circle(at, r * 0.7, color)
		_overlay.draw_arc(at, r * 0.7, 0.0, TAU, 24, Color.BLACK, 2.0, true)
