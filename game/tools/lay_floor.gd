extends UnifiedTool
## Lays a level's floor and walls from an ASCII room map, from the kit's parts on its 4 m grid (docs/ART.md, Kit
## parts): `./uni tool lay_floor -- --scene res://game/levels/<name>.tscn [--map <file>]`, then `./uni bake --nav`.
## Markers and decor are the author's, added to the scene as text: the tool owns only `Nav/Laid`, the floor tiles and
## walls it lays, and replaces that node whole on every run, keeping everything else in the scene. A scene that
## doesn't exist yet is made: its root, `Nav` (a NavigationRegion3D that `uni bake --nav` bakes from the static
## colliders), `Decor` and `Markers`. The map is kept in the scene root's metadata `lay_floor_map`, so a run without
## `--map` lays the scene's own map again (after a part changes).
##
## The map is a grid of 4 m cells drawn with their edges between them, north (-z) at the top, x to the right:
##
##   +-+-+-+
##   |. . .|      a cell is a character at an odd line and an odd column of the text (from 0)
##   + +-+D+      an edge is one between two cells: at an even line (a north or south edge) or an even column
##   |.|s L|      `+` (or anything) at the corners, where an even line meets an even column, is ignored
##   +-+-+-+
##
## Cells: `.` a stone tile, `r` stone with rocks, `g` a grate, `s` a spike tile (a trap marker goes on it), `d` dirt,
## `w` wood, `,` the graveyard's dirt, `L` a lift's shaft (the floor there left out: the lift marker goes on it), and a
## space for none. Edges: `-` or `|` a wall, `D` a doorway, `f` a fence, `b` a barrier (low cover, for a room's side
## toward the camera: at the floor's rim it also gets a `Rim`, an invisible wall to a wall's height above it, so a throw
## over it never leaves the level), `o` nothing even at the floor's rim (where a part the author places closes it, as the
## hub's crypt), and a space for open floor between two cells; an edge between a cell and none is a wall unless drawn as
## something else. The grid's lines are on multiples of 4 m, its middle line (rounded down) through the origin.

## The scene root's metadata holding the map the floor was laid from.
const MAP_META := &"lay_floor_map"
## The node under Nav the tool owns.
const LAID := "Laid"
## A cell's side, metres: the kit's grid.
const CELL := 4.0
## Each cell character's part.
const CELLS: Dictionary[String, String] = {
	".": "res://game/levels/parts/crypt/floor_tile_large.tscn",
	"r": "res://game/levels/parts/crypt/floor_tile_large_rocks.tscn",
	"g": "res://game/levels/parts/crypt/floor_tile_big_grate.tscn",
	"s": "res://game/levels/parts/crypt/floor_tile_big_spikes.tscn",
	"d": "res://game/levels/parts/crypt/floor_dirt_large.tscn",
	"w": "res://game/levels/parts/crypt/floor_wood_large.tscn",
	",": "res://game/levels/parts/hub/floor_dirt.tscn",
	"L": "res://game/levels/parts/crypt/lift_shaft.tscn",
}
## Each edge character's part (a wall's origin on its grid line, along its local x).
const EDGES: Dictionary[String, String] = {
	"-": "res://game/levels/parts/crypt/wall.tscn",
	"|": "res://game/levels/parts/crypt/wall.tscn",
	"D": "res://game/levels/parts/crypt/wall_doorway.tscn",
	"f": "res://game/levels/parts/hub/fence.tscn",
	"b": "res://game/levels/parts/crypt/barrier.tscn",
	"o": "",
}
## A barrier's edge at the floor's rim: its Rim's box (a wall's height above the barrier's collider, as thick as it).
const RIM_SIZE := Vector3(CELL, 2.9, 0.5)
const RIM_BOTTOM := 1.1

var _lines: PackedStringArray
var _parts: Dictionary[String, PackedScene] = {}
var _rim_shape: BoxShape3D


func _run() -> void:
	var path := arg("scene")
	if not path.begins_with("res://") or not path.ends_with(".tscn"):
		fail("--scene names the level scene to lay, res://game/levels/<name>.tscn")
		return
	var scene := _open(path)
	var map_path := arg("map")
	var map := ""
	if map_path != "":
		map = FileAccess.get_file_as_string(map_path).replace("\r", "")
		if map.strip_edges() == "":
			fail("no map read from " + map_path)
	elif scene.has_meta(MAP_META):
		map = str(scene.get_meta(MAP_META))
	else:
		fail("%s keeps no map: give one with --map <file>" % path)
	if not failed():
		_lay(scene, map)
	if not failed():
		scene.set_meta(MAP_META, map)
		var packed := PackedScene.new()
		expect(packed.pack(scene) == OK and ResourceSaver.save(packed, path) == OK, "saved " + path)
	scene.free()


## The scene at `path` as the editor opens it (an instanced part's own values stay its own), or a new level's skeleton.
func _open(path: String) -> Node3D:
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		return packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN) as Node3D
	var scene := Node3D.new()
	scene.name = path.get_file().get_basename().to_pascal_case()
	var region := NavigationRegion3D.new()
	region.navigation_mesh = NavigationMesh.new()
	region.navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	region.navigation_mesh.agent_height = 2.0
	region.navigation_mesh.agent_max_climb = 0.3
	region.set_meta(&"unified_nav_bake", true)
	_add(scene, scene, region, "Nav")
	_add(scene, scene, Node3D.new(), "Decor")
	_add(scene, scene, Node3D.new(), "Markers")
	return scene


## Replaces Nav/Laid with the map's tiles (row by row), then its north-south edges' walls, then its east-west ones'.
func _lay(scene: Node3D, map: String) -> void:
	var nav := scene.get_node_or_null(^"Nav") as NavigationRegion3D
	if nav == null:
		fail("the scene has no Nav (a NavigationRegion3D under its root)")
		return
	var old := nav.get_node_or_null(LAID)
	if old != null:
		nav.remove_child(old)
		old.free()
	var laid := Node3D.new()
	_add(scene, nav, laid, LAID)
	_lines = map.split("\n")
	while not _lines.is_empty() and _lines[-1].strip_edges() == "":
		_lines.remove_at(_lines.size() - 1)
	var width := 0
	for line: String in _lines:
		width = maxi(width, line.length())
	var columns := floori(width / 2.0)  # a last edge column left blank is no cell
	var rows := floori(_lines.size() / 2.0)
	if columns == 0 or rows == 0 or _lines.size() % 2 == 0:
		fail("the map is no grid of cells between edge lines (an odd number of lines, at least three)")
		return
	var west := -floori(columns / 2.0) * CELL  # the grid's lines on multiples of CELL, its middle one through the origin
	var north := -floori(rows / 2.0) * CELL
	var tiles := 0
	for row in rows:
		for column in columns:
			var cell := _at(2 * row + 1, 2 * column + 1)
			if cell == " ":
				continue
			if not CELLS.has(cell):
				fail("the map's cell %d,%d is `%s`, no cell kind" % [column, row, cell])
				return
			var centre := Vector3(west + (column + 0.5) * CELL, 0, north + (row + 0.5) * CELL)
			_place(scene, laid, CELLS[cell], "Tile_%d_%d" % [column, row], Transform3D(Basis.IDENTITY, centre))
			tiles += 1
	var walls := 0
	for row in rows + 1:  # the edges along x, at the grid's lines across z
		for column in columns:
			var at := Vector3(west + (column + 0.5) * CELL, 0, north + row * CELL)
			var drawn := _at(2 * row, 2 * column + 1)
			var part := _edge(drawn, _cell(row - 1, column), _cell(row, column))
			if part != "":
				_place(scene, laid, part, "Edge_%d_%d_x" % [column, row], Transform3D(Basis.IDENTITY, at))
				walls += 1
				if drawn == "b" and _cell(row - 1, column) != _cell(row, column):
					_rim(scene, laid, "Rim_%d_%d_x" % [column, row], Transform3D(Basis.IDENTITY, at))
	var across := Basis(Vector3(0, 0, -1), Vector3.UP, Vector3(1, 0, 0))  # a quarter turn about y: along z
	for row in rows:  # the edges along z, at the grid's lines across x
		for column in columns + 1:
			var at := Vector3(west + column * CELL, 0, north + (row + 0.5) * CELL)
			var drawn := _at(2 * row + 1, 2 * column)
			var part := _edge(drawn, _cell(row, column - 1), _cell(row, column))
			if part != "":
				_place(scene, laid, part, "Edge_%d_%d_z" % [column, row], Transform3D(across, at))
				walls += 1
				if drawn == "b" and _cell(row, column - 1) != _cell(row, column):
					_rim(scene, laid, "Rim_%d_%d_z" % [column, row], Transform3D(across, at))
	if failed():
		return
	if tiles == 0:
		fail("the map has no cell")
		return
	step("laid %d cells by %d: %d tiles, %d walls" % [columns, rows, tiles, walls])
	result = {"tiles": tiles, "walls": walls}


## The map's character at `line`, `column` (a space past a line's end).
func _at(line: int, column: int) -> String:
	if line < 0 or line >= _lines.size() or column < 0 or column >= _lines[line].length():
		return " "
	return _lines[line][column]


## Whether the cell at `row`, `column` has floor.
func _cell(row: int, column: int) -> bool:
	return _at(2 * row + 1, 2 * column + 1) != " "


## The part an edge drawn as `drawn` between two cells gets ("": none): open floor between two floors, a wall at a
## floor's rim unless drawn otherwise, nothing between two cells of none.
func _edge(drawn: String, one: bool, other: bool) -> String:
	if not one and not other:
		return ""
	if drawn == " ":
		return "" if one and other else EDGES["-"]
	if not EDGES.has(drawn):
		fail("an edge is `%s`, no edge kind" % drawn)
		return ""
	return EDGES[drawn]  # "" for `o`: nothing


## A Rim over a barrier at the floor's rim, at `at` (the barrier's): an invisible wall from the barrier's collider up to a
## wall's height (docs/review.md: a throw over low cover at a level's edge fell out of the level). Not a kit part: it has
## no model to hold a collider to.
func _rim(scene: Node3D, parent: Node3D, rim_name: String, at: Transform3D) -> void:
	if _rim_shape == null:
		_rim_shape = BoxShape3D.new()
		_rim_shape.size = RIM_SIZE
	var body := StaticBody3D.new()
	body.transform = at
	body.set_meta(&"unified_category", 2)  # a wall: blocks walking, sight and shots
	_add(scene, parent, body, rim_name)
	var shape := CollisionShape3D.new()
	shape.shape = _rim_shape
	shape.position = Vector3(0, RIM_BOTTOM + RIM_SIZE.y / 2, 0)
	_add(scene, body, shape, "Shape")


## An instance of the part at `path`, named and placed under `parent`.
func _place(scene: Node3D, parent: Node3D, path: String, part_name: String, at: Transform3D) -> void:
	if not _parts.has(path):
		_parts[path] = load(path) as PackedScene
	var part := _parts[path].instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	part.transform = at
	_add(scene, parent, part, part_name)


## Adds `child` under `parent`, owned by the scene's root: pack() saves only the nodes the root owns.
func _add(scene: Node3D, parent: Node, child: Node, child_name: String) -> void:
	child.name = child_name
	parent.add_child(child)
	child.owner = scene
