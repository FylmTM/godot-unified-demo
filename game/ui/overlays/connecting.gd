class_name Connecting
extends Control
## The overlay while a session is on its way: starting (hosting or joining), reconnecting after a lost link, or
## catching up with the host. The game shows frozen behind it (a reconnect keeps the player's place), and Cancel
## gives up: Game leaves the session.
##
## What it says is Game's to choose (it knows why it is shown); this only shows it, its heading's dots ticking so a
## wait never looks like a hang. Cancel keeps the pad's focus while it shows, and Esc and a pad's B cancel too, taken
## in _input before anything under it handles them; closing gives the focus back to what had it before.

## The player gave up waiting.
signal cancelled

## How many times a second the heading's dots step.
const DOT_RATE: float = 3.0

## The heading without its dots.
var _heading_text: String = ""
var _time: float = 0.0
## What had the focus before the overlay took it (null: nothing).
var _return_focus: Control = null

@onready var _heading: Label = %Heading
@onready var _text: Label = %Text
@onready var _cancel: Button = %Cancel


func _ready() -> void:
	_cancel.pressed.connect(cancelled.emit)
	Focus.trap(_cancel)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_heading.text = _heading_text + ".".repeat(int(_time * DOT_RATE) % 4)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()


## Shows `heading` (it gets ticking dots) and `text` under it, and takes the focus for Cancel.
func open(heading: String, text: String) -> void:
	_heading_text = heading
	_text.text = text
	_text.visible = text != ""
	if not visible:
		_time = 0.0
		_return_focus = get_viewport().gui_get_focus_owner()
		show()
		_cancel.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()
	_return_focus = null
