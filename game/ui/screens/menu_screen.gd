class_name MenuScreen
extends Control
## One screen of a menu (the title, hero select, the settings, the pause menu's): what MenuStack shows one at a time.
## A screen names the control that takes the focus when it opens (`first_focus`, also its default: the
## `default_focus` group a modal gives the focus back to), what the prompt bar says under it (`prompts`, which may
## change while it shows: `prompts_changed`), and asks to be closed with `back_requested` (its Back button). It takes
## input only while the focus is in it: never while it is covered or a modal is over it.

## The screen asks to close (MenuStack pops it).
signal back_requested
## The screen's prompt bar hints changed.
signal prompts_changed(prompts: Dictionary[String, String])

## The control focused when the screen opens with nothing else holding the focus.
@export var first_focus: Control
## The prompt bar's hints for this screen: an action (or a space-separated group of actions shown as one control) to
## what it does.
@export var prompts: Dictionary[String, String] = {&"ui_accept": "Select"}


func _ready() -> void:
	first_focus.add_to_group(Modal.DEFAULT_FOCUS)


## Shows `hints` on the prompt bar while this screen shows.
func set_prompts(hints: Dictionary[String, String]) -> void:
	prompts = hints
	prompts_changed.emit(hints)


## Makes `control` the screen's first focus (and its default).
func set_first_focus(control: Control) -> void:
	if first_focus != null:
		first_focus.remove_from_group(Modal.DEFAULT_FOCUS)
	first_focus = control
	first_focus.add_to_group(Modal.DEFAULT_FOCUS)


## Whether the focus is in this screen (it is the one the player is using).
func has_focus_within() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	return focus != null and is_ancestor_of(focus) and is_visible_in_tree()
