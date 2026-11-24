class_name Dialog
extends Modal
## A message the player acknowledges: why a game ended or could not start. A parchment panel with a heading (what
## happened), the reason as a sentence, the library's own words under it in small type when they say more, and OK.
##
## Game opens it and keeps the game's input off while it shows. Esc and a pad's B close it like OK: they are taken in
## _input, before the GUI and every _unhandled_input under it (the play scene's pause) see them.

## The player acknowledged it.
signal closed

@onready var _heading: Label = %Heading
@onready var _text: Label = %Text
@onready var _detail: Label = %Detail
@onready var _ok: Button = %Ok


func _ready() -> void:
	super()
	_ok.pressed.connect(close)


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
	open_modal()


## Closes the dialog (OK, Esc, a pad's B), gives the focus back, and says so.
func close() -> void:
	if not visible:
		return
	close_modal()
	closed.emit()


func _focus_control() -> Control:
	return _ok
