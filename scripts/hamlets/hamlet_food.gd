class_name HamletFood
extends Node
## Food with a risk (Phase 16): each hamlet built ([signal HamletDirector.hamlet_built]) gets a
## [HamletPantry] — six cabbages in its vegetable patch and three eggs in the hens' nest. While the
## fox is close to any food, villagers are on alert ([method Villagers.set_food_alert]) and shoo it
## from farther away, which cancels eating (the shoo moves the fox). At night, or unseen, eating
## is safe.
## [br][br]
## Budget: a distance check per food item four times a second; pantries refresh every 2 s.

## The hamlets.
@export var director: HamletDirector
## Its chunk deltas remember eaten food (optional; tests set [member deltas]).
@export var streamer: WorldStreamer
## Alerted while the fox is at their food (optional).
@export var villagers: Villagers
## The player; defaults to the [code]player[/code] group.
@export var player: Node3D
## What eating an egg / a cabbage does.
@export var eggs: InteractionDefinition
@export var vegetables: InteractionDefinition
## The fox counts as at the food this close (m), and as having seen it this close (m).
@export_range(0.5, 20.0, 0.5, "suffix:m") var near: float = 3.0
@export_range(1.0, 60.0, 1.0, "suffix:m") var seen: float = 15.0

## Where eaten food is remembered.
var deltas: ChunkDeltaStore

var _pantries: Dictionary[Vector2i, HamletPantry] = {}
var _since: float = 0.0
var _since_refresh: float = 0.0
var _seen: bool = false
var _cabbage: Mesh
var _egg: Mesh
var _nest: Mesh
var _soil: Mesh
var _material: StandardMaterial3D


func _ready() -> void:
	if deltas == null and streamer != null:
		deltas = streamer.deltas()
	_cabbage = ProceduralMeshes.hamlet_food(&"cabbage")
	_egg = ProceduralMeshes.hamlet_food(&"egg")
	_nest = ProceduralMeshes.hamlet_food(&"nest")
	_soil = ProceduralMeshes.hamlet_food(&"soil")
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.95
	if director != null:
		director.hamlet_built.connect(stock)
		director.hamlet_freed.connect(func(cell: Vector2i) -> void: _pantries.erase(cell))


func _process(delta: float) -> void:
	_since += delta
	_since_refresh += delta
	if _since >= 0.25:
		_since = 0.0
		check()
	if _since_refresh >= 2.0:
		_since_refresh = 0.0
		for pantry: HamletPantry in _pantries.values():
			if is_instance_valid(pantry):
				pantry.refresh()


## Fills the patch and the nest of [param layout] (under [param root]).
func stock(layout: HamletLayout, root: Node3D) -> void:
	var settings := director.terrain.hamlets
	if deltas == null and streamer != null:
		deltas = streamer.deltas()  # (the streamer may be ready after us)
	var pantry := HamletPantry.new()
	pantry.name = "Pantry"
	pantry.deltas = deltas
	root.add_child(pantry)
	for i in layout.size():
		var place := layout.positions[i] - layout.centre
		var turn := Basis(Vector3.UP, layout.yaws[i])
		if layout.ids[i] == settings.patch_id:
			_mesh(root, _soil, place + Vector3.UP * 0.01, layout.yaws[i])
			for row in 2:
				for column in 3:
					var at := place + turn * Vector3((column - 1) * 1.1, 0.02, (row - 0.5) * 1.1)
					_add(
						pantry,
						layout,
						root,
						_mesh(root, _cabbage, at, layout.yaws[i] + column),
						vegetables
					)
		elif layout.ids[i] == settings.nest_id:
			_mesh(root, _nest, place, layout.yaws[i])
			for n in 3:
				var at := place + Vector3(cos(n * 2.1) * 0.07, 0.03, sin(n * 2.1) * 0.07)
				_add(pantry, layout, root, _mesh(root, _egg, at, n * 1.3), eggs)
	pantry.refresh()
	_pantries[layout.cell] = pantry


## Whether the fox is at some food now, and alerts the villagers accordingly.
func check() -> bool:
	var focus := _player()
	var at_food := false
	if focus != null:
		for pantry: HamletPantry in _pantries.values():
			if not is_instance_valid(pantry):
				continue
			for key in pantry.count():
				if not pantry.is_target_available(key):
					continue
				var d := pantry.position_of(key).distance_to(focus.global_position)
				at_food = at_food or d <= near
				if d <= seen and not _seen:
					_seen = true
					EventBus.hamlet_food_seen.emit()  # (the onboarding hint)
	if villagers != null:
		villagers.set_food_alert(at_food)
	return at_food


## The pantry of the hamlet of [param cell] (null when not built).
func pantry(cell: Vector2i) -> HamletPantry:
	return _pantries.get(cell)


func _add(
	pantry: HamletPantry,
	layout: HamletLayout,
	root: Node3D,
	mesh: Node3D,
	definition: InteractionDefinition
) -> void:
	var absolute := layout.centre + (mesh.global_position - root.global_position)
	var chunk := Vector2i(
		floori(absolute.x / director.terrain.chunk_size),
		floori(absolute.z / director.terrain.chunk_size)
	)
	pantry.add_item(mesh, definition, chunk)


func _mesh(root: Node3D, mesh: Mesh, at: Vector3, yaw: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material
	root.add_child(node)
	node.position = at
	node.rotation.y = yaw
	return node


func _player() -> Node3D:
	if player != null and is_instance_valid(player):
		return player
	return get_tree().get_first_node_in_group(Animal.PLAYER_GROUP) as Node3D
