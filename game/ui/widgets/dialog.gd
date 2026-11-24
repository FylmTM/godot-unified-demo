class_name Dialog
extends Control
## A message the player must acknowledge, over everything: why a game ended or could not start. A parchment panel
## with a heading, the app's sentence, the library's own words under it in small type, and OK.
##
## It is modal by hand: the dim behind it takes every click, and OK is its own neighbour in every direction, so a
## pad's focus can't wander to the screen underneath. Closing it gives the focus back to whatever had it before.
## Game opens it and keeps game input off while it shows. Esc and a pad's B close it like OK, taken in _input, before
## anything under it handles them (the play scene's pause is an unhandled Esc).

## The player acknowledged it.
signal closed

## What had the focus before the dialog took it (null: nothing).
var _return_focus: Control = null

@onready var _heading: Label = %Heading
@onready var _text: Label = %Text
@onready var _detail: Label = %Detail
@onready var _ok: Button = %Ok


func _ready() -> void:
	_ok.pressed.connect(close)
	Focus.trap(_ok)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## Shows `heading` and `text`, with `detail` (the library's words) under them when there is any.
func open(heading: String, text: String, detail: String = "") -> void:
	_heading.text = heading
	_text.text = text
	_detail.text = detail
	_detail.visible = detail != ""
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if not visible:
		_return_focus = focus_owner
	show()
	_ok.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()
	_return_focus = null
	closed.emit()
