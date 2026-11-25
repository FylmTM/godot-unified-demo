class_name MenuScreen
extends Control
## One screen of a menu (the title, the settings; later the pause menu's): what MenuStack shows one at a time. A screen
## names the control that takes the focus when it opens (`first_focus`, also its default: the `default_focus` group a
## modal gives the focus back to) and what the prompt bar says under it (`prompts`), and asks to be closed with
## `back_requested` (its Back button).

## The screen asks to close (MenuStack pops it).
signal back_requested

## The control focused when the screen opens with nothing else holding the focus.
@export var first_focus: Control
## The prompt bar's hints for this screen: an action (or a space-separated group of actions shown as one control) to
## what it does.
@export var prompts: Dictionary[String, String] = {&"ui_accept": "Select"}


func _ready() -> void:
	first_focus.add_to_group(Modal.DEFAULT_FOCUS)
