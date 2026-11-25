class_name ControlsTab
extends ScrollContainer
## The settings screen's Controls tab: the rebindable actions in one scheme at a time (keyboard and mouse, or gamepad;
## it opens on the kind used last), two slots each, a reset of the scheme shown, and the controls' settings (the
## pads' glyphs, the move stick's dead zone).

## Each rebindable action as the player reads it.
const ACTION_NAMES: Dictionary[StringName, String] = {
	&"move_up": "Move up", &"move_down": "Move down", &"move_left": "Move left", &"move_right": "Move right",
	&"attack": "Attack", &"interact": "Interact",
}
const SCHEME_NAMES: Array[String] = ["Keyboard and mouse", "Gamepad"]

## A row of an action's slots (game/ui/settings/bind_row.tscn).
@export var bind_row_scene: PackedScene

## The scheme shown.
var kind: Bindings.Kind = Bindings.Kind.KEYBOARD

@onready var _scheme: Button = %Scheme
@onready var _rows: VBoxContainer = %Bindings
@onready var _reset: Button = %Reset


func _ready() -> void:
	for action: StringName in Bindings.ACTIONS:
		var row: BindRow = bind_row_scene.instantiate()
		_rows.add_child(row)
	_scheme.pressed.connect(_switch)
	_scheme.gui_input.connect(_on_scheme_input)
	_reset.pressed.connect(func() -> void: Settings.bindings = Bindings.reset(Settings.bindings, kind))
	show_scheme(Prompts.last_kind)


## Shows scheme `scheme`'s bindings.
func show_scheme(scheme: Bindings.Kind) -> void:
	kind = scheme
	_scheme.text = "<  %s  >" % SCHEME_NAMES[kind]
	for i: int in Bindings.ACTIONS.size():
		var action: StringName = Bindings.ACTIONS[i]
		var row: BindRow = _rows.get_child(i)
		row.visible = Bindings.rebindable(action, kind)
		row.show_action(action, ACTION_NAMES[action], kind)


## The row of `action` (the walk binds through it).
func row_of(action: StringName) -> BindRow:
	return _rows.get_child(Bindings.ACTIONS.find(action)) as BindRow


func _switch() -> void:
	show_scheme(Bindings.Kind.PAD if kind == Bindings.Kind.KEYBOARD else Bindings.Kind.KEYBOARD)


## Left and right switch the scheme where they would otherwise move the focus.
func _on_scheme_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right"):
		_switch()
		_scheme.accept_event()
