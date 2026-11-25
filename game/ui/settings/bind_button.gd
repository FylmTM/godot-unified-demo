class_name BindButton
extends Button
## One binding slot on the controls screen: an action's first or second binding in one scheme (keyboard and mouse, or
## gamepad), drawn as its glyph. Pressed, it listens: the next key or mouse button (keyboard), or pad button or
## trigger (gamepad), becomes the binding, and an action that held it takes the one replaced (Bindings.bind). Esc or a
## pad's Start cancels, Delete, Backspace or a pad's Back clears the slot. While it listens it takes every press
## (in _input, before the GUI and the menus' Back), so nothing else reacts to the press being bound.

## The action, scheme and slot this binds (set before it enters the tree).
var action: StringName
var kind: Bindings.Kind = Bindings.Kind.KEYBOARD
var slot: int = 0

## Waiting for the press to bind.
var _listening: bool = false

## The glyph, drawn by a label over the button: a prompt font's line is twice its glyph's height, and as the button's
## own text it would make the button that tall.
@onready var _glyph: Label = $Glyph


func _ready() -> void:
	pressed.connect(_listen)
	Prompts.changed.connect(refresh)
	refresh()


func _input(event: InputEvent) -> void:
	if not _listening or event is InputEventMouseMotion:
		return
	get_viewport().set_input_as_handled()
	var press: bool = event.is_pressed() and not event.is_echo()
	if event is InputEventJoypadMotion:
		press = Bindings.can_bind(event, kind)
	if not press:
		return
	var key: Key = Bindings.key_of(event as InputEventKey) if event is InputEventKey else KEY_NONE
	var button: int = (event as InputEventJoypadButton).button_index if event is InputEventJoypadButton else -1
	if key == KEY_ESCAPE or button == JOY_BUTTON_START:
		_stop()
	elif key in [KEY_DELETE, KEY_BACKSPACE] or button == JOY_BUTTON_BACK:
		_stop()
		Settings.bindings = Bindings.clear(Settings.bindings, action, kind, slot)
	elif Bindings.can_bind(event, kind):
		_stop()
		Settings.bindings = Bindings.bind(Settings.bindings, action, kind, slot, event)


## Shows the slot's binding: its glyph in its family's font, its name where the font has none, a dash when empty.
func refresh() -> void:
	if _listening or action == &"":
		return
	var events: Array[InputEvent] = Bindings.events(action, kind)
	_glyph.text = ""
	if slot >= events.size():
		text = "-"
		return
	var family: Prompts.Family = (Prompts.Family.KEYBOARD if kind == Bindings.Kind.KEYBOARD
		else Prompts.pad_family(Prompts.last_pad))
	var glyph: String = Prompts.glyph_of(events[slot], family)
	text = events[slot].as_text().get_slice(" (", 0) if glyph == "" else ""
	_glyph.add_theme_font_override(&"font", Prompts.font(family))
	_glyph.text = glyph


## Whether it waits for a press to bind.
func is_listening() -> bool:
	return _listening


func _listen() -> void:
	_listening = true
	_glyph.text = ""
	text = "Press a key" if kind == Bindings.Kind.KEYBOARD else "Press a button"


func _stop() -> void:
	_listening = false
	refresh()
