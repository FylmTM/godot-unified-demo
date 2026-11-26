@tool
extends Marker3D
## Level marker: the floor's hoard, the gold chest the party hauls to the lift by its two handles, at the marker's local
## -X and +X ends (hoard.odin). One a floor at most. In the editor it shows the chest at its place; in play the hoard's
## view draws it where the sim has it.

const UNIFIED_KIND := "hoard"
## The chest's model (the sim's box is HOARD_HALF, measured from it).
const MODEL: String = "res://assets/kaykit/dungeon/chest_gold.gltf"


func _ready() -> void:
	if not Engine.is_editor_hint() or get_child_count() > 0:
		return
	add_child((load(MODEL) as PackedScene).instantiate())
