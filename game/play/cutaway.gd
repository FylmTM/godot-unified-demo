class_name Cutaway
extends Node
## The wall cutaway: a wall standing between the camera and any hero fades out, dithered (game/fx/cutaway.gdshader),
## and comes back once nothing stands behind it, so a hero is never lost behind the near side of a room.
##
## A wall is a level part whose category is a wall (its root's `unified_category`, docs/ART.md, Kit parts): walls,
## pillars, columns, a brazier's stand. When a level shows, track() finds them under it and files each by the 4 m cells
## its bounds cover. Each frame, for each hero, a few segments run from the camera to points up its body; only the walls
## filed in the cells under the low end of those segments (where they are below a wall's top) are tested against them,
## so the cost is a handful of box tests a hero whatever the level's size. A wall met is cut toward CUT_MAX at RATE a
## second, one met no longer comes back at the same rate. While a wall is cut at all its meshes draw with `material`
## (one shared material, the cut a per-instance uniform); solid again, they draw with their own.

## The kit's grid: walls are filed by these cells.
const CELL: float = 4.0
## A wall part's category (docs/ART.md, Kit parts).
const CATEGORY_WALL: int = 2
## The points up a hero (above its feet, metres) the camera must see: its feet, its chest and its head.
const SIGHT_HEIGHTS: Array[float] = [0.3, 1.2, 2.2]
## The highest a wall stands (metres): above this a segment passes over every wall.
const WALL_TOP: float = 4.5
## The share of a cut wall's pixels dropped, and how fast a wall fades out or back (share a second).
const CUT_MAX: float = 0.75
const RATE: float = 4.0

## What a wall draws with while it is cut (cutaway.gdshader, the kit's atlas).
@export var material: ShaderMaterial

## The walls by the cells their bounds cover.
var _cells: Dictionary[Vector2i, Array] = {}
## Every wall, and those cut now or wanted cut.
var _walls: Array[Wall] = []
var _cutting: Array[Wall] = []


func _process(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or _walls.is_empty():
		return
	var heroes: Array[Vector3] = []
	for hero: Node in Unified.session.get_views(EnumView.HERO):
		heroes.append((hero as Node3D).global_position)
	update(camera.global_position, heroes, delta)


## Files the walls under `level` (the level root, the floor just shown under it), and lets go of the last floor's (it
## may still be under the root, queued for deletion, this frame).
func track(level: Node) -> void:
	_cells.clear()
	_walls.clear()
	_cutting.clear()
	var bodies: Array[Node] = []
	for floor_scene: Node in level.get_children():
		if not floor_scene.is_queued_for_deletion():
			bodies.append_array(floor_scene.find_children("*", "StaticBody3D", true, false))
	for body: Node in bodies:
		if body.get_meta(&"unified_category", 0) != CATEGORY_WALL:
			continue
		var wall := Wall.new()
		wall.part = body as Node3D
		for found: Node in body.find_children("*", "MeshInstance3D", true, false):
			var mesh := found as MeshInstance3D
			wall.meshes.append(mesh)
			var bounds: AABB = mesh.global_transform * mesh.get_aabb()
			wall.bounds = bounds if wall.meshes.size() == 1 else wall.bounds.merge(bounds)
		if wall.meshes.is_empty():
			continue
		_walls.append(wall)
		var low: Vector2i = _cell(wall.bounds.position)
		var high: Vector2i = _cell(wall.bounds.end)
		for x: int in range(low.x, high.x + 1):
			for z: int in range(low.y, high.y + 1):
				if not _cells.has(Vector2i(x, z)):
					_cells[Vector2i(x, z)] = []
				_cells[Vector2i(x, z)].append(wall)


## Cuts the walls between `eye` (the camera) and any of `heroes` (their feet), and brings back the rest, over `delta`
## seconds: the play scene's frames ask, a check by hand.
func update(eye: Vector3, heroes: Array[Vector3], delta: float) -> void:
	for wall: Wall in _cutting:
		wall.wanted = false
	for feet: Vector3 in heroes:
		for height: float in SIGHT_HEIGHTS:
			_cut_along(feet + Vector3(0, height, 0), eye)
	var step: float = RATE * delta
	for index: int in range(_cutting.size() - 1, -1, -1):
		var wall: Wall = _cutting[index]
		wall.cut = minf(wall.cut + step, CUT_MAX) if wall.wanted else maxf(wall.cut - step, 0.0)
		var drawn_with: Material = material if wall.cut > 0.0 else null
		for mesh: MeshInstance3D in wall.meshes:
			if mesh.material_override != drawn_with:
				mesh.material_override = drawn_with
			mesh.set_instance_shader_parameter(&"cut", wall.cut)
		if wall.cut <= 0.0 and not wall.wanted:
			_cutting.remove_at(index)


## How far the wall part `part` is cut now (0: solid, CUT_MAX: as cut as a wall gets); 0 for a part not filed.
func cut_of(part: Node3D) -> float:
	for wall: Wall in _cutting:
		if wall.part == part:
			return wall.cut
	return 0.0


## Marks every wall the segment from `point` to `eye` meets, below WALL_TOP, as wanted cut.
func _cut_along(point: Vector3, eye: Vector3) -> void:
	if eye.y <= WALL_TOP or point.y >= WALL_TOP:
		return
	var top: Vector3 = point.lerp(eye, (WALL_TOP - point.y) / (eye.y - point.y))
	var low: Vector2i = _cell(Vector3(minf(point.x, top.x), 0, minf(point.z, top.z)))
	var high: Vector2i = _cell(Vector3(maxf(point.x, top.x), 0, maxf(point.z, top.z)))
	for x: int in range(low.x, high.x + 1):
		for z: int in range(low.y, high.y + 1):
			for wall: Wall in _cells.get(Vector2i(x, z), []):
				if not wall.wanted and wall.bounds.intersects_segment(point, top) != null:
					wall.wanted = true
					if not _cutting.has(wall):
						_cutting.append(wall)


func _cell(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.z / CELL))


## A wall part: its meshes, its bounds in the world, and how far it is cut.
class Wall:
	extends RefCounted
	var part: Node3D
	var meshes: Array[MeshInstance3D] = []
	var bounds: AABB
	var cut: float = 0.0
	## Whether a hero stands behind it this frame.
	var wanted: bool = false
