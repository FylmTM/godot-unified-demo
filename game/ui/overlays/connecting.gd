class_name Connecting
extends Modal
## The overlay while a game starts and is not yet up: hosting or joining. The title waits under it, and Cancel gives
## up (Game hides it at once and leaves the session; the title takes the player back once the session said goodbye).
## Esc and a pad's B cancel too: they are taken in _input, before the GUI and every _unhandled_input under it see them.
## A link lost or repaired in play is not this: it is LinkStatus, which never takes the player's input.
##
## What it says is Game's to choose (it knows why it is shown); this shows it, the heading's dots ticking so a wait
## never looks like a hang. The dots are always in the text and only revealed one by one, so the centred heading
## never shifts as they tick.

## The player gave up waiting.
signal cancelled

## How many times a second the heading's dots step.
const DOT_RATE: float = 3.0
## The dots, revealed one by one.
const DOTS: String = "..."

var _time: float = 0.0

@onready var _heading: Label = %Heading
@onready var _text: Label = %Text
@onready var _cancel: Button = %Cancel


func _ready() -> void:
	super()
	_cancel.pressed.connect(cancelled.emit)
	set_process(false)


func _process(delta: float) -> void:
	_time += delta
	_heading.visible_characters = _heading.text.length() - DOTS.length() + int(_time * DOT_RATE) % (DOTS.length() + 1)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()


## Shows `heading` (it gets ticking dots) and `text` under it, and gives Cancel the focus.
func open(heading: String, text: String) -> void:
	_heading.text = heading + DOTS
	_text.text = text
	_text.visible = text != ""
	if not visible:
		_time = 0.0
		set_process(true)
	open_modal()


## Hides the overlay and gives the focus back.
func close() -> void:
	set_process(false)
	close_modal()


func _focus_control() -> Control:
	return _cancel
