class_name ControlsTab
extends ScrollContainer
## The settings screen's Controls tab: the rebindable actions in one scheme at a time (keyboard and mouse, or gamepad;
## it opens on the kind used last), two slots each, a reset of the scheme shown, and, under the gamepad scheme, the
## pads' settings (their glyphs, the move stick's dead zone). A refused change says why under the slots.

## A slot started or stopped listening (the screen's prompts follow).
signal listening_changed(listening: bool)

const SCHEME_NAMES: Array[String] = ["Keyboard and mouse", "Gamepad"]

## A row of an action's slots (game/ui/settings/bind_row.tscn).
@export var bind_row_scene: PackedScene

## The scheme shown.
var kind: Bindings.Kind = Bindings.Kind.KEYBOARD

@onready var _scheme: Button = %Scheme
@onready var _rows: VBoxContainer = %Bindings
@onready var _pad_rows: Array[Control] = [%PromptStyle as Control, %MoveDeadzone as Control]
@onready var _notice: Label = %Notice
@onready var _reset: Button = %Reset


func _ready() -> void:
	for action: StringName in Bindings.ACTIONS:
		var row: BindRow = bind_row_scene.instantiate()
		_rows.add_child(row)
		for slot: BindButton in row.slots():
			slot.listening_changed.connect(listening_changed.emit)
			slot.refused.connect(_on_refused)
			slot.pressed.connect(_notice.hide)
	_scheme.pressed.connect(_switch)
	_scheme.gui_input.connect(_on_scheme_input)
	_reset.pressed.connect(func() -> void:
		_notice.hide()
		Settings.bindings = Bindings.reset(Settings.bindings, kind))
	show_scheme(Prompts.last_kind)


## Shows scheme `scheme`'s bindings (and the pads' settings under the gamepad's).
func show_scheme(scheme: Bindings.Kind) -> void:
	kind = scheme
	_scheme.text = "<  %s  >" % SCHEME_NAMES[kind]
	_notice.hide()
	for i: int in Bindings.ACTIONS.size():
		var action: StringName = Bindings.ACTIONS[i]
		var row: BindRow = _rows.get_child(i)
		row.visible = Bindings.rebindable(action, kind)
		row.show_action(action, kind)
	for row: Control in _pad_rows:
		row.visible = kind == Bindings.Kind.PAD


## The row of `action` (the walk binds through it).
func row_of(action: StringName) -> BindRow:
	return _rows.get_child(Bindings.ACTIONS.find(action)) as BindRow


func _switch() -> void:
	show_scheme(Bindings.Kind.PAD if kind == Bindings.Kind.KEYBOARD else Bindings.Kind.KEYBOARD)


func _on_refused(why: String) -> void:
	_notice.text = why
	_notice.show()


## Left and right switch the scheme where they would otherwise move the focus, as a press (so they sound like one).
func _on_scheme_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right"):
		_scheme.accept_event()
		_scheme.pressed.emit()
