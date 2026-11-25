class_name Dialog
extends Modal
## A message the player acknowledges, or a question they answer: why a game ended or could not start, or "Leave to
## the title?". A parchment panel with a heading (what happened, or what is asked), the reason or what follows as a
## sentence, the library's own words under it in small type when they say more, and OK; a question has its two
## answers instead. The answer that does it has the focus, unless the question affects others ("End the game for
## everyone?"): then the one that stays does. Its own prompt bar shows its keys while the menus' hide (Esc is no).
##
## The dialog owns the answer: whoever asks hands it the callable to call with it, once. Showing anything else over a
## question still open answers that one no first, so no caller waits forever and no answer goes to the wrong question.
##
## Game opens it and keeps the game's input off while it shows. Esc and a pad's B close it like OK, or answer no: they
## are taken in _input, before the GUI and every _unhandled_input under it (the play scene's pause) see them.

## The dialog closed (the player acknowledged it or answered).
signal closed

## The group of the prompt bars that hide while a dialog shows (the menus'; PromptBar.covered_by_dialogs).
const PROMPT_BARS: StringName = &"menu_prompt_bars"

## What gets the answer (confirmed: bool) of what shows now: true for OK or the first answer.
var _answer: Callable = Callable()

@onready var _heading: Label = %Heading
@onready var _text: Label = %Text
@onready var _detail: Label = %Detail
@onready var _ok: Button = %Ok
@onready var _other: Button = %Other
@onready var _prompt_bar: PromptBar = %PromptBar


func _ready() -> void:
	super()
	_ok.pressed.connect(_finish.bind(true))
	_other.pressed.connect(_finish.bind(false))


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish(false)


## Shows `heading` and `text`, with `detail` (the library's words) under them when there is any, and OK; `then` gets
## true when the player acknowledged it (false when something else was shown over it).
func open(heading: String, text: String, detail: String = "", then: Callable = Callable()) -> void:
	_show(heading, text, detail, "OK", "", then, false)


## Asks `heading` (`text` saying what follows) with the answers `confirm_text` and `cancel_text`; `answer` gets true for
## the first, false for the other (Esc, a pad's B, or something else shown over it). `affects_others`: the answer that
## stays has the focus.
func ask(heading: String, text: String, confirm_text: String, cancel_text: String, answer: Callable,
		detail: String = "", affects_others: bool = false) -> void:
	_show(heading, text, detail, confirm_text, cancel_text, answer, affects_others)


## Whether it asks a question (two answers) rather than tells.
func asks() -> bool:
	return _other.visible


## Closes the dialog as no answer (OK for a message), gives the focus back, and says so.
func close() -> void:
	_finish(false)


func _show(heading: String, text: String, detail: String, confirm_text: String, cancel_text: String,
		answer: Callable, stay_focused: bool) -> void:
	_hand_over(false)  # a question still open is answered no: this replaces it
	_answer = answer
	_heading.text = heading
	_text.text = text
	_detail.text = detail
	_detail.visible = detail != ""
	_ok.text = confirm_text
	_other.text = cancel_text
	_other.visible = cancel_text != ""
	var prompts: Dictionary[String, String] = {&"ui_accept": confirm_text}
	if asks():
		prompts = {&"ui_accept": "Select", &"ui_cancel": cancel_text}
	_prompt_bar.show_prompts(prompts)
	get_tree().call_group(PROMPT_BARS, &"set_covered", true)
	open_modal()
	if stay_focused:
		_other.grab_focus()


func _finish(confirmed: bool) -> void:
	if not visible:
		return
	var asked: bool = asks()
	close_modal()
	get_tree().call_group(PROMPT_BARS, &"set_covered", false)
	closed.emit()
	_hand_over(confirmed or not asked)


## Gives the open dialog's answer to whoever asked, once.
func _hand_over(confirmed: bool) -> void:
	var answer: Callable = _answer
	_answer = Callable()
	if answer.is_valid():
		answer.call(confirmed)


func _focus_control() -> Control:
	return _ok
