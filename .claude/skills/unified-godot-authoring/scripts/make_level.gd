extends UnifiedTool
## Writes a 3D level scene: boxes and ramps (a ramp is a tilted box), each a StaticBody3D with its collision shape and
## its mesh, under a NavigationRegion3D that `uni bake --nav` bakes, and a spawn marker. Change PIECES and PATH, run
## it with `./uni tool <this file>`, then `./uni bake --nav`.

const PATH := "res://game/levels/yard.tscn"
## name, centre, size, tilt about x in degrees
const PIECES: Array[Array] = [
	["Ground", Vector3(0, -0.5, 0), Vector3(40, 1, 40), 0.0],
	["Deck", Vector3(8, 1.5, 0), Vector3(8, 1, 8), 0.0],
	["Ramp", Vector3(8, 0.9, 7.4), Vector3(4, 0.4, 7.5), 15.0],
]

var scene := Node3D.new()  # not `root`: a tool script is a SceneTree, which has one


func _run() -> void:
	scene.name = "Yard"
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.47, 0.5)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = NavigationMesh.new()
	region.navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	region.set_meta("unified_nav_bake", true)
	_add(scene, region, "Nav")
	for piece: Array in PIECES:
		var piece_name: String = piece[0]  # typed locals: `piece[1] as Vector3` is an unsafe cast
		var centre: Vector3 = piece[1]
		var size: Vector3 = piece[2]
		var tilt: float = piece[3]
		var body := StaticBody3D.new()
		body.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(tilt)), centre)
		_add(region, body, piece_name)  # under the region: its bake parses its children
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		_add(body, collision, "Shape")
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = stone
		var view := MeshInstance3D.new()
		view.mesh = mesh
		_add(body, view, "Mesh")
	var spawn := Marker3D.new()
	spawn.position = Vector3(0, 0, -6)
	spawn.set_meta("unified_kind", "spawn")
	_add(scene, spawn, "Spawn")
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	var packed := PackedScene.new()
	expect(packed.pack(scene) == OK and ResourceSaver.save(packed, PATH) == OK, "saved " + PATH)
	scene.free()


## Adds `child` under `parent`, owned by the scene's root: pack() saves only the nodes the root owns.
func _add(parent: Node, child: Node, child_name: String) -> void:
	child.name = child_name
	parent.add_child(child)
	child.owner = scene
