class_name FocusRow
extends PanelContainer
## A row of the settings screen that lights up while the focus is anywhere in it: one way every row shows it has the
## focus, whatever its control (a choice, a slider, a binding slot), on top of the control's own frame.

## The theme's looks for a row, without and with the focus in it.
const LOOK: StringName = &"Row"
const LOOK_FOCUSED: StringName = &"RowFocused"


func _ready() -> void:
	theme_type_variation = LOOK
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func _on_focus_changed(control: Control) -> void:
	theme_type_variation = LOOK_FOCUSED if control != null and is_ancestor_of(control) else LOOK
