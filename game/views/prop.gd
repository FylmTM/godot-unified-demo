class_name PropView
extends Node3D
## A prop's view (View_Prop, simulation/extension/frame.odin): the host poses this root at the bottom of the prop's
## body, turned as the body is, and the script shows the kind's model (a child each, one visible) and, while a local
## hero's Interact would grab it, a warm highlight drawn over the model (game/fx/highlight.tres).
##
## Props are pooled (the UnifiedView's `pool`): a view a gone prop leaves is reused for the next one. The data setter
## takes null in between, then the new prop's data, which sets everything the view shows (its model and highlight).

## Drawn over the model's meshes while the prop is aimed at.
@export var highlight: Material

## Set by the host before _ready, anew each time the prop's view data changes, and null while the view is pooled.
var data: ViewProp:
	set(value):
		data = value
		if is_node_ready():
			_show()

var _meshes: Array[MeshInstance3D] = []

@onready var _barrel: Node3D = $Barrel
@onready var _crate: Node3D = $Crate
@onready var _heavy_crate: Node3D = $HeavyCrate


func _ready() -> void:
	for found: Node in find_children("*", "MeshInstance3D", true, false):
		_meshes.append(found as MeshInstance3D)
	_show()


## The kind's model, highlighted while aimed at.
func _show() -> void:
	if data == null:
		return
	_barrel.visible = data.kind == EnumPropKind.BARREL
	_crate.visible = data.kind == EnumPropKind.CRATE
	_heavy_crate.visible = data.kind == EnumPropKind.HEAVY_CRATE
	_set_highlight(data.aimed)


func _set_highlight(on: bool) -> void:
	for mesh: MeshInstance3D in _meshes:
		mesh.material_overlay = highlight if on else null
