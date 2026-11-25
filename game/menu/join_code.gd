class_name JoinCodeScreen
extends MenuScreen
## Join a game online by its lobby code (CodeField: typed, pasted, or stepped on a pad). The field starts with the last
## code this machine joined, and keeps what was typed when a join fails (the menu comes back here, the dialog over it
## saying why). Join, accept on a whole code, or a paste of one joins; Paste says when the clipboard holds no code.

## The player asked to join `code` (hero select first).
signal join_requested(code: String)

@onready var _code: CodeField = %Code
@onready var _problem: Label = %Problem
@onready var _paste: Button = %Paste
@onready var _join: Button = %Join
@onready var _back: Button = %Back


func _ready() -> void:
	super()
	if Settings.last_join != "" and not Game.is_address(Settings.last_join):
		_code.paste(Settings.last_join)
	_code.changed.connect(func(code: String) -> void:
		_join.disabled = code == ""
		_problem.visible = false)
	_code.submitted.connect(join_requested.emit)
	_paste.pressed.connect(func() -> void:
		var pasted: bool = _code.paste(DisplayServer.clipboard_get())
		_problem.text = "" if pasted else "The clipboard holds no code."
		_problem.visible = not pasted)
	_join.pressed.connect(func() -> void: join_requested.emit(_code.code()))
	_back.pressed.connect(back_requested.emit)
	_join.disabled = _code.code() == ""
	_paste.visible = Game.has_clipboard()


## The code typed ("" while a cell is empty).
func code() -> String:
	return _code.code()
