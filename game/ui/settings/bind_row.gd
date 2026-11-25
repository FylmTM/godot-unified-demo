class_name BindRow
extends HBoxContainer
## One rebindable action on the controls screen: its name and its two slots in the scheme shown.

@onready var _label: Label = %Label
@onready var _slots: Array[BindButton] = [%First as BindButton, %Second as BindButton]


## Shows `action` (named `action_name`) in scheme `kind`.
func show_action(action: StringName, action_name: String, kind: Bindings.Kind) -> void:
	_label.text = action_name
	for slot: int in _slots.size():
		_slots[slot].action = action
		_slots[slot].kind = kind
		_slots[slot].slot = slot
		_slots[slot].refresh()


## The row's first slot (the focus goes here).
func first_slot() -> BindButton:
	return _slots[0]
