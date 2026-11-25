class_name Dialog
extends Modal
## A message the player acknowledges, or a question they answer: why a game ended or could not start, or "Leave to
## the title?". A parchment panel with a heading (what happened, or what is asked), the reason or what follows as a
## sentence, the library's own words under it in small type when they say more, and OK; a question has its two
## answers instead, the one that does it first (it has the focus).
##
## Game opens it and keeps the game's input off while it shows. Esc and a pad's B close it like OK, or answer no: they
## are taken in _input, before the GUI and every _unhandled_input under it (the play scene's pause) see them.

## The player acknowledged it, or answered (after `answered`).
signal closed
## The player answered a question: `confirmed` for the first answer, false for the other (Esc, a pad's B too).
signal answered(confirmed: bool)

@onready var _heading: Label = %Heading
@onready var _text: Label = %Text
@onready var _detail: Label = %Detail
@onready var _ok: Button = %Ok
@onready var _other: Button = %Other


func _ready() -> void:
	super()
	_ok.pressed.connect(_answer.bind(true))
	_other.pressed.connect(_answer.bind(false))


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_answer(false)


## Shows `heading` and `text`, with `detail` (the library's words) under them when there is any, and OK.
func open(heading: String, text: String, detail: String = "") -> void:
	_show(heading, text, detail, "OK", "")


## Asks `heading` (`text` saying what follows), with the answers `confirm_text` and `cancel_text`.
func ask(heading: String, text: String, confirm_text: String, cancel_text: String, detail: String = "") -> void:
	_show(heading, text, detail, confirm_text, cancel_text)


## Whether it asks a question (two answers) rather than tells.
func asks() -> bool:
	return _other.visible


## Closes the dialog (OK, Esc, a pad's B) as no answer, gives the focus back, and says so.
func close() -> void:
	_answer(false)


func _show(heading: String, text: String, detail: String, confirm_text: String, cancel_text: String) -> void:
	_heading.text = heading
	_text.text = text
	_detail.text = detail
	_detail.visible = detail != ""
	_ok.text = confirm_text
	_other.text = cancel_text
	_other.visible = cancel_text != ""
	open_modal()


func _answer(confirmed: bool) -> void:
	if not visible:
		return
	var asked: bool = asks()
	close_modal()
	closed.emit()
	if asked:
		answered.emit(confirmed)


func _focus_control() -> Control:
	return _ok
