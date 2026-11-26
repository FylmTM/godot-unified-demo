class_name HoardView
extends Node3D
## The hoard's view (View_Hoard, simulation/extension/frame.odin): the host poses this root at the bottom of the chest's
## body, turned as the body is (it rocks and swings as it is hauled). While a local hero's Interact would take one of
## its handles (the rules' haul_target), the chest wears the warm highlight a prop in reach does
## (game/fx/highlight.tres), and the HUD's "[E] Haul" prompt hangs over the handle (handle_position).

## The handles, in the chest's frame at its bottom (the rules' HOARD_HANDLE, from the body's centre HOARD_HALF.y up):
## at its -X end (EnumHaulHandle.LEFT) and its +X end (RIGHT).
const HANDLE_LEFT: Vector3 = Vector3(-0.8, 0.65, 0)
const HANDLE_RIGHT: Vector3 = Vector3(0.8, 0.65, 0)

## Drawn over the chest's meshes while a local hero could take a handle.
@export var highlight: Material

## Set by the host before _ready and anew each time the hoard's view data changes.
var data: ViewHoard:
	set(value):
		data = value
		if is_node_ready():
			_show()

var _meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	for found: Node in find_children("*", "MeshInstance3D", true, false):
		_meshes.append(found as MeshInstance3D)
	_show()


## Where handle `handle` (EnumHaulHandle.LEFT or RIGHT) is in the world now.
func handle_position(handle: int) -> Vector3:
	return to_global(HANDLE_RIGHT if handle == EnumHaulHandle.RIGHT else HANDLE_LEFT)


func _show() -> void:
	if data == null:
		return
	for mesh: MeshInstance3D in _meshes:
		mesh.material_overlay = highlight if data.aimed else null
