class_name JoinCodeScreen
extends MenuScreen
## Join a game online by its lobby code (CodeField: typed, pasted, or stepped on a pad). The field opens empty (Rejoin
## last game is the way back to the last one) and keeps what was typed when a join fails (the menu comes back here, the
## dialog over it saying why). Join, or accept on a whole code, joins; Paste fills the field from the clipboard
## (Game.clipboard_get) and says when that holds no code. The prompt bar follows the focus: the field's own keys while
## it has it, Select and Back on the buttons.

## The player asked to join `code` (hero select first).
signal join_requested(code: String)

## The prompt bar's hints while the code field has the focus (the scene's `prompts`), and on the buttons.
const BUTTON_PROMPTS: Dictionary[String, String] = {&"ui_accept": "Select", &"ui_cancel": "Back"}

var _field_prompts: Dictionary[String, String] = {}

@onready var _code: CodeField = %Code
@onready var _problem: Label = %Problem
@onready var _paste: Button = %Paste
@onready var _join: Button = %Join
@onready var _back: Button = %Back


func _ready() -> void:
	super()
	_field_prompts = prompts
	_code.changed.connect(func(code: String) -> void:
		_join.disabled = code == ""
		_problem.visible = false)
	_code.submitted.connect(join_requested.emit)
	_code.focus_entered.connect(set_prompts.bind(_field_prompts))
	_code.focus_exited.connect(set_prompts.bind(BUTTON_PROMPTS))
	_paste.pressed.connect(func() -> void:
		var pasted: bool = _code.paste(Game.clipboard_get())
		_problem.text = "" if pasted else "The clipboard holds no code."
		_problem.visible = not pasted)
	_join.pressed.connect(func() -> void: join_requested.emit(_code.code()))
	_back.pressed.connect(back_requested.emit)
	_join.disabled = true


## The code typed ("" while a cell is empty).
func code() -> String:
	return _code.code()
