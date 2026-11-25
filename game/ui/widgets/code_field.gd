class_name CodeField
extends HBoxContainer
## A lobby code, typed into one cell per character: as many cells as the lobby service's codes have
## (UnifiedSession.join_code_length), each one of its alphabet (join_code_alphabet). One control to the focus: typing
## puts a letter in the cell under the cursor and moves on (lower case taken as upper, anything outside the alphabet
## refused), Backspace takes the one before; a paste (Ctrl+V, or paste() from a Paste button) takes the whole code
## as the library reads it (clean_join_code: case, spaces and dashes forgiven). On a pad, left and right move the
## cursor and up and down step its cell through the alphabet; accept submits a whole code. The cells are the game's
## look (the portrait frame, the focused row's light under the cursor while it has the focus).

## The code changed: the whole code, or "" while a cell is empty.
signal changed(code: String)
## Accept (Enter, a pad's A) on a whole code.
signal submitted(code: String)

## Each cell's character ("" while empty), and the cell the next letter goes to.
var _chars: PackedStringArray = []
var _cursor: int = 0
## The cells' lights and letters, in order.
var _lights: Array[PanelContainer] = []
var _letters: Array[Label] = []

@onready var _session: UnifiedSession = Unified.session


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	alignment = BoxContainer.ALIGNMENT_CENTER
	for i: int in _session.join_code_length:
		var frame := PanelContainer.new()
		frame.theme_type_variation = &"PortraitFrame"
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var light := PanelContainer.new()
		light.theme_type_variation = &"Row"
		light.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var letter := Label.new()
		letter.theme_type_variation = &"InkHeading"
		letter.custom_minimum_size = Vector2(56, 64)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		light.add_child(letter)
		frame.add_child(light)
		add_child(frame)
		_lights.append(light)
		_letters.append(letter)
		_chars.append("")
	focus_entered.connect(_show)
	focus_exited.connect(_show)
	_show()


func _gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if event.is_action_pressed(&"ui_paste") and Game.has_clipboard():
		paste(DisplayServer.clipboard_get())
	elif key != null and key.pressed and key.keycode == KEY_BACKSPACE:
		_cursor = maxi(_cursor - 1, 0) if _chars[_cursor] == "" else _cursor
		_put("")
	elif event.is_action_pressed(&"ui_accept"):
		if code() != "":
			submitted.emit(code())
	elif key != null and key.pressed and key.unicode > 0:
		var typed: String = String.chr(key.unicode).to_upper()
		if not typed in _session.join_code_alphabet:
			return  # not a code's: the key does what it does elsewhere
		_put(typed)
		_cursor = mini(_cursor + 1, _chars.size() - 1)
		_show()
	elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right"):
		var by: int = -1 if event.is_action_pressed(&"ui_left") else 1
		if _cursor + by < 0 or _cursor + by >= _chars.size():
			return  # past the first or last cell: the focus moves on
		_cursor += by
		_show()
	elif event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"ui_down"):
		var alphabet: String = _session.join_code_alphabet
		var at: int = alphabet.find(_chars[_cursor])
		var step: int = 1 if event.is_action_pressed(&"ui_up") else -1
		at = posmod(at + step, alphabet.length()) if at >= 0 else (0 if step > 0 else alphabet.length() - 1)
		_put(alphabet[at])
	else:
		return
	accept_event()


## The whole code, or "" while a cell is empty.
func code() -> String:
	return "".join(_chars) if not _chars.has("") else ""


## Fills the cells with `text` as the library reads a code (nothing changes when it isn't one); true when it was.
func paste(text: String) -> bool:
	var cleaned: String = _session.clean_join_code(text)
	if cleaned == "":
		return false
	for i: int in _chars.size():
		_chars[i] = cleaned[i]
	_cursor = _chars.size() - 1
	_show()
	changed.emit(code())
	return true


func _put(character: String) -> void:
	_chars[_cursor] = character
	_show()
	changed.emit(code())


func _show() -> void:
	for i: int in _chars.size():
		_letters[i].text = _chars[i]
		_lights[i].theme_type_variation = &"RowFocused" if has_focus() and i == _cursor else &"Row"
