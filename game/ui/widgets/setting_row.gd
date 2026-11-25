class_name SettingRow
extends FocusRow
## One player setting on the settings screen, bound by name to the Settings property it shows: its label, and the
## control its type calls for, read from the property itself (Settings' property list), so a new setting is a
## property and a row naming it. A ranged number is a slider shown as a percentage (every ranged setting is a share);
## a bool (On, Off) and an enum are a choice, stepped with left and right, a press, or a click on either half; a text
## (the player's name) is a field, applied when it is entered or left. The row's scene holds every control and shows
## the one it needs. A change applies at once (Settings saves it a moment
## later), except a slider with `on_release` while it is dragged (the interface's size, which would move the slider
## under the mouse); the row follows Settings.changed, so a change made elsewhere shows.

## The Settings property this row shows.
@export var setting: StringName
## What the player reads.
@export var label: String = ""
## A dragged slider applies when it is let go (keys and a pad's steps apply at once).
@export var on_release: bool = false

## The choice's names and values, in order (On and Off for a bool).
var _choice_names: PackedStringArray = []
var _choice_values: Array = []
## The step the choice's next press takes: +1, or -1 for a left press or a click on its left half.
var _direction: int = 1
## While the row writes its control from the setting: the control's signal is not a change.
var _showing: bool = false
var _dragging: bool = false

@onready var _label: Label = %Label
@onready var _slider: HSlider = %Slider
@onready var _amount: Label = %Amount
@onready var _choice: Button = %Choice
@onready var _field: LineEdit = %Field


func _ready() -> void:
	super()
	_label.text = label
	var property: Dictionary = _property()
	var hint: int = property.get("hint", PROPERTY_HINT_NONE)
	var hint_string: String = property.get("hint_string", "")
	var type: int = property.get("type", TYPE_NIL)
	_slider.visible = hint == PROPERTY_HINT_RANGE
	_amount.visible = _slider.visible
	_field.visible = type == TYPE_STRING
	_choice.visible = not _slider.visible and not _field.visible
	if _slider.visible:
		var bounds: PackedStringArray = hint_string.split(",")
		_slider.min_value = bounds[0].to_float()
		_slider.max_value = bounds[1].to_float()
		_slider.step = bounds[2].to_float() if bounds.size() > 2 else 0.01
	elif type == TYPE_BOOL:
		_choice_names = ["On", "Off"]
		_choice_values = [true, false]
	else:
		var entries: PackedStringArray = hint_string.split(",")
		for i: int in entries.size():
			_choice_names.append(entries[i].get_slice(":", 0))
			_choice_values.append(entries[i].get_slice(":", 1).to_int() if entries[i].contains(":") else i)
	_slider.value_changed.connect(_on_slider_changed)
	_slider.drag_started.connect(func() -> void: _dragging = true)
	_slider.drag_ended.connect(func(_changed: bool) -> void:
		_dragging = false
		_apply(_slider.value))
	_choice.pressed.connect(_on_choice_pressed)
	_field.text_submitted.connect(func(text: String) -> void: _apply(text))
	_field.focus_exited.connect(func() -> void: _apply(_field.text))
	_choice.gui_input.connect(_on_choice_input)
	Settings.changed.connect(func(changed: StringName) -> void:
		if changed == setting:
			_show())
	_show()


func _show() -> void:
	_showing = true
	var value: Variant = Settings.get(setting)
	if _field.visible:
		var text: String = value
		if _field.text != text:
			_field.text = text
	elif _slider.visible:
		var share: float = value
		_slider.value = share
		_show_amount(share)
	else:
		var at: int = maxi(_choice_values.find(value), 0)
		_choice.text = "<  %s  >" % _choice_names[at]
	_showing = false


func _show_amount(share: float) -> void:
	_amount.text = "%d%%" % roundi(share * 100.0)


func _apply(value: Variant) -> void:
	if not _showing:
		Settings.set(setting, value)


func _on_slider_changed(value: float) -> void:
	_show_amount(value)
	if not (on_release and _dragging):
		_apply(value)


func _on_choice_pressed() -> void:
	var at: int = maxi(_choice_values.find(Settings.get(setting)), 0)
	_apply(_choice_values[posmod(at + _direction, _choice_values.size())])
	_direction = 1


## Left and right step the choice where they would move the focus, and a click steps it toward the half clicked: each
## by a press of the choice, so it sounds like one.
func _on_choice_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
		_direction = -1 if button.position.x < _choice.size.x / 2.0 else 1
		return
	for step: Array in [[&"ui_left", -1], [&"ui_right", 1]]:
		var action: StringName = step[0]
		if event.is_action_pressed(action):
			_direction = step[1]
			_choice.accept_event()
			_choice.pressed.emit()


func _property() -> Dictionary:
	for property: Dictionary in Settings.get_property_list():
		if property["name"] == String(setting):
			return property
	push_error("SettingRow: Settings has no setting %s" % setting)
	return {}
