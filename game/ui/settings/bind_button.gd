class_name BindButton
extends Button
## One binding slot on the controls screen: an action's first or second binding in one scheme (keyboard and mouse, or
## gamepad), drawn as its glyph. Pressed, it listens: the next key (keyboard) or pad button or trigger (gamepad)
## becomes the binding, and a mouse button too when it is clicked on this slot; a click anywhere else cancels, so the
## left button is never bound by accident. Esc or a pad's Start (bind_cancel) cancels, Delete, Backspace or a pad's
## Back (bind_clear) clears the slot. Bindings' one rule may refuse a change (an action's last binding, another
## action's only one): `refused` says why, and the slot shakes. While it listens it takes every press, in _input,
## before the GUI and the menus' Back, so nothing else reacts to the press being bound.

## It started or stopped listening (the screen's prompts follow).
signal listening_changed(listening: bool)
## A change was refused, and why.
signal refused(why: String)

## How far and how long a refused slot shakes (pixels, seconds).
const SHAKE: float = 10.0
const SHAKE_S: float = 0.3

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
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if not click.pressed:
			return
		if not get_global_rect().has_point(click.position):
			_stop()
			return
	elif event.is_action_pressed(&"bind_cancel"):
		_stop()
		return
	elif event.is_action_pressed(&"bind_clear"):
		_stop()
		_change(Bindings.clear(Settings.bindings, action, kind, slot))
		return
	if Bindings.can_bind(event, kind) and (event.is_pressed() or event is InputEventJoypadMotion):
		_stop()
		_change(Bindings.bind(Settings.bindings, action, kind, slot, event))


## Shows the slot's binding: its glyph in its family's font, its name where the font has none, a dash when empty.
func refresh() -> void:
	if _listening or action == &"":
		return
	var events: Array[InputEvent] = Bindings.events(action, kind)
	_glyph.text = ""
	_glyph.theme_type_variation = &"BindGlyph"
	if slot >= events.size():
		text = "-"
		return
	var family: Prompts.Family = (Prompts.Family.KEYBOARD if kind == Bindings.Kind.KEYBOARD
		else Prompts.pad_family(Prompts.last_pad))
	var glyph: String = Prompts.glyph_of(events[slot], family)
	text = Prompts.name_of(events[slot]) if glyph == "" else ""
	_glyph.add_theme_font_override(&"font", Prompts.font(family))
	_glyph.text = glyph


## Whether it waits for a press to bind.
func is_listening() -> bool:
	return _listening


func _listen() -> void:
	_listening = true
	text = ""
	_glyph.theme_type_variation = &"InkDim"  # the button's own text would be clipped to its narrow middle
	_glyph.remove_theme_font_override(&"font")
	_glyph.text = "Press a key" if kind == Bindings.Kind.KEYBOARD else "Press a button"
	listening_changed.emit(true)


func _stop() -> void:
	_listening = false
	refresh()
	listening_changed.emit(false)


func _change(change: Bindings.Change) -> void:
	if change.refused != "":
		refused.emit(change.refused)
		var rest: float = position.x
		var tween: Tween = create_tween()
		for offset: float in [SHAKE, -SHAKE, SHAKE / 2.0, 0.0]:
			tween.tween_property(self, ^"position:x", rest + offset, SHAKE_S / 4.0)
		return
	Settings.bindings = change.bindings
