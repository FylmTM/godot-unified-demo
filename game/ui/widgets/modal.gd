class_name Modal
extends Control
## The base of the overlays that hold the player until they answer (Dialog, Connecting): over everything, a dim behind
## them that takes every click, and the pad's focus kept inside.
##
## Opening gives the focus to the modal's own control (`_focus_control()`) and remembers what had it. While it shows,
## the focus moving to a control outside it (a screen grabbing it as it loads under the modal, a stray hover) is taken
## back, and that control becomes the one to give the focus back to. Closing gives the focus back to it, else to the
## current screen's default (the visible control in the `default_focus` group), so a pad is never left without one.
## A modal's control is also its own neighbour in every direction (its scene sets them to "."), so the d-pad never
## leaves it in the first place.

## The group of the control that takes the focus on a screen when nothing else has it (the title's New game).
const DEFAULT_FOCUS: StringName = &"default_focus"

## What gets the focus back when the modal closes (null: the screen's default).
var _return_focus: Control = null


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


## Shows the modal and gives its control the focus.
func open_modal() -> void:
	if not visible:
		var focus_owner: Control = get_viewport().gui_get_focus_owner()
		_return_focus = focus_owner if focus_owner != null and not is_ancestor_of(focus_owner) else null
		show()
	_focus_control().grab_focus()


## Hides the modal and gives the focus back: to what had it, else to the current screen's default.
func close_modal() -> void:
	if not visible:
		return
	hide()
	var target: Control = _return_focus
	_return_focus = null
	if not is_instance_valid(target) or not target.is_visible_in_tree():
		target = default_focus(get_tree())
	if target != null:
		target.grab_focus()


## The control on screen that takes the focus when nothing else has it (null: none shows).
static func default_focus(tree: SceneTree) -> Control:
	for node: Node in tree.get_nodes_in_group(DEFAULT_FOCUS):
		var control := node as Control
		if control != null and control.is_visible_in_tree():
			return control
	return null


## The control that holds the focus while the modal shows (each modal names its own).
func _focus_control() -> Control:
	return null


func _on_focus_changed(control: Control) -> void:
	if not visible or control == null or is_ancestor_of(control):
		return
	_return_focus = control
	_focus_control().grab_focus.call_deferred()
