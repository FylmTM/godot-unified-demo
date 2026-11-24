class_name Focus
extends RefCounted
## Helpers for the pad's cursor, Godot's one focus: a modal's controls keep it among themselves.


## Makes `control` its own neighbour in every direction and in tab order, so the focus stays on it: an overlay's only
## button over a screen whose buttons would otherwise be the nearest neighbours.
static func trap(control: Control) -> void:
	var own: NodePath = control.get_path()
	control.focus_neighbor_left = own
	control.focus_neighbor_top = own
	control.focus_neighbor_right = own
	control.focus_neighbor_bottom = own
	control.focus_next = own
	control.focus_previous = own
