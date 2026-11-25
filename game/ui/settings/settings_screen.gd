class_name SettingsScreen
extends MenuScreen
## The settings screen, a parchment panel of tabs (video, audio, controls, gameplay), opened over the title (and, with
## the pause menu, over play). Every row applies as it changes; Back (or Esc, a pad's B) closes it. A pad's shoulder
## buttons, or Q and E, switch tabs, and the new tab's first control takes the focus.

@onready var _tabs: TabContainer = %Tabs
@onready var _back: Button = %Back


func _ready() -> void:
	first_focus = _first_control(_tabs.get_current_tab_control())
	super()
	_back.pressed.connect(back_requested.emit)
	_tabs.tab_changed.connect(func(_tab: int) -> void:
		var control: Control = _first_control(_tabs.get_current_tab_control())
		if control != null:
			control.grab_focus())


func _unhandled_input(event: InputEvent) -> void:
	for step: Array in [[&"menu_tab_prev", -1], [&"menu_tab_next", 1]]:
		var action: StringName = step[0]
		if event.is_action_pressed(action):
			var by: int = step[1]
			get_viewport().set_input_as_handled()
			_tabs.current_tab = posmod(_tabs.current_tab + by, _tabs.get_tab_count())


## The tab named `tab_name` (Video, Audio, Controls, Gameplay), shown.
func show_tab(tab_name: String) -> Control:
	for i: int in _tabs.get_tab_count():
		if _tabs.get_tab_control(i).name == tab_name:
			_tabs.current_tab = i
	return _tabs.get_current_tab_control()


## The first control under `node` that takes the focus (a row's control, a binding slot).
static func _first_control(node: Node) -> Control:
	for child: Node in node.get_children():
		var control := child as Control
		if control == null or not control.visible:
			continue
		if control.focus_mode == Control.FOCUS_ALL:
			return control
		var inner: Control = _first_control(control)
		if inner != null:
			return inner
	return null
