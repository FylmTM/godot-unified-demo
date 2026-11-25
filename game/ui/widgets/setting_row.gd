class_name SettingRow
extends HBoxContainer
## One player setting on the settings screen, bound by name to the Settings property it shows: its label, and the
## control its type calls for, read from the property itself (Settings' property list), so a new setting is a
## property and a row naming it. A toggle for a bool; a slider for a ranged number, shown as a percentage (every
## ranged setting is a share); a choice stepped with left and right, or pressed, for an enum. The row's scene holds
## all three, and shows the one it needs. A change applies at once (Settings saves it a moment later); the row follows
## Settings.changed, so a change made elsewhere shows.

## The Settings property this row shows.
@export var setting: StringName
## What the player reads.
@export var label: String = ""

## The property's names of its enum's values, and the values, in order (a choice).
var _choice_names: PackedStringArray = []
var _choice_values: Array[int] = []
## While the row writes its control from the setting: the control's signal is not a change.
var _showing: bool = false

@onready var _label: Label = %Label
@onready var _toggle: CheckButton = %Toggle
@onready var _slider: HSlider = %Slider
@onready var _amount: Label = %Amount
@onready var _choice: Button = %Choice


func _ready() -> void:
	_label.text = label
	var property: Dictionary = _property()
	var hint: int = property.get("hint", PROPERTY_HINT_NONE)
	var hint_string: String = property.get("hint_string", "")
	var type: int = property.get("type", TYPE_NIL)
	_toggle.visible = type == TYPE_BOOL
	_slider.visible = hint == PROPERTY_HINT_RANGE
	_amount.visible = _slider.visible
	_choice.visible = hint == PROPERTY_HINT_ENUM
	if _slider.visible:
		var bounds: PackedStringArray = hint_string.split(",")
		_slider.min_value = bounds[0].to_float()
		_slider.max_value = bounds[1].to_float()
		_slider.step = bounds[2].to_float() if bounds.size() > 2 else 0.01
	if _choice.visible:
		var entries: PackedStringArray = hint_string.split(",")
		for i: int in entries.size():
			_choice_names.append(entries[i].get_slice(":", 0))
			_choice_values.append(entries[i].get_slice(":", 1).to_int() if entries[i].contains(":") else i)
	_toggle.toggled.connect(func(on: bool) -> void: _apply(on))
	_slider.value_changed.connect(func(value: float) -> void: _apply(value))
	_choice.pressed.connect(_step.bind(1))
	_choice.gui_input.connect(_on_choice_input)
	Settings.changed.connect(func(changed: StringName) -> void:
		if changed == setting:
			_show())
	_show()


## The control the player changes (the focus goes here).
func control() -> Control:
	for candidate: Control in [_toggle, _slider, _choice]:
		if candidate.visible:
			return candidate
	return null


func _show() -> void:
	_showing = true
	var value: Variant = Settings.get(setting)
	if _toggle.visible:
		_toggle.button_pressed = value
	if _slider.visible:
		_slider.value = value
		var share: float = value
		_amount.text = "%d%%" % roundi(share * 100.0)
	if _choice.visible:
		var current: int = value
		var at: int = maxi(_choice_values.find(current), 0)
		_choice.text = "<  %s  >" % _choice_names[at]
	_showing = false


func _apply(value: Variant) -> void:
	if not _showing:
		Settings.set(setting, value)


## Steps the choice `by` values (wrapping).
func _step(by: int) -> void:
	var current: int = Settings.get(setting)
	var at: int = maxi(_choice_values.find(current), 0)
	_apply(_choice_values[posmod(at + by, _choice_values.size())])


## Left and right step the choice where they would otherwise move the focus.
func _on_choice_input(event: InputEvent) -> void:
	for direction: Array in [[&"ui_left", -1], [&"ui_right", 1]]:
		var action: StringName = direction[0]
		if event.is_action_pressed(action):
			var by: int = direction[1]
			_step(by)
			_choice.accept_event()


func _property() -> Dictionary:
	for property: Dictionary in Settings.get_property_list():
		if property["name"] == String(setting):
			return property
	push_error("SettingRow: Settings has no setting %s" % setting)
	return {}
