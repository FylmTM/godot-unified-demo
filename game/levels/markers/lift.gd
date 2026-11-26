@tool
extends Marker3D
## Level marker: the floor's lift, its exit, standing on the middle of the deck's top at floor level over its shaft (a
## LiftShaft part under it, the floor tile there left out). The deck goes down LIFT_DROP once the hoard and the party
## are aboard (lift.odin). One a floor at most. In the editor it shows the deck at its place; in play the lift's view
## draws it where the sim has it.

const UNIFIED_KIND := "lift"
## The deck's model (the sim's deck is LIFT_HALF, a hand short of it all round).
const MODEL: String = "res://assets/kaykit/dungeon/floor_wood_large.gltf"


func _ready() -> void:
	if not Engine.is_editor_hint() or get_child_count() > 0:
		return
	add_child((load(MODEL) as PackedScene).instantiate())
