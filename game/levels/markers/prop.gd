@tool
extends Marker3D
## Level marker: a prop the sim makes a body of (a barrel, a crate), which heroes carry and throw. In the editor it
## shows the prop's model at its place; in play the prop's view draws it where the sim has it.

const UNIFIED_KIND := "prop"
## The model each kind shows in the editor (the sim's Prop_Kind, by name).
const MODELS: Dictionary[String, String] = {
	"barrel": "res://assets/kaykit/dungeon/barrel_small.gltf",
	"crate": "res://assets/kaykit/dungeon/box_small.gltf",
	"heavy_crate": "res://assets/kaykit/dungeon/box_large.gltf",
}

## What the prop is: its size, mass and how it flies are the sim's (PROP_SPECS).
@export_enum("barrel", "crate", "heavy_crate") var kind: String = "barrel":
	set(value):
		kind = value
		_show()


func _ready() -> void:
	_show()


func _show() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	for child: Node in get_children():
		child.free()
	var model: Node3D = (load(MODELS[kind]) as PackedScene).instantiate()
	add_child(model)
