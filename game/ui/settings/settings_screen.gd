class_name SettingsScreen
extends MenuScreen
## The settings screen, a parchment panel of tabs (video, audio, controls, gameplay), opened over the title (and, with
## the pause menu, over play), sized from the view so it fits any interface size: the tab scrolls in what is left.
## Every row applies as it changes; Back (or Esc, a pad's B) closes it. A pad's shoulder buttons, or Q and E, switch
## tabs, and the new tab's first control takes the focus and becomes the screen's first focus. While a binding slot
## listens, the prompt bar says how to cancel or clear it.

## The prompt bar's hints while a binding slot listens.
const LISTENING_PROMPTS: Dictionary[String, String] = {&"bind_cancel": "Cancel", &"bind_clear": "Clear"}

## The prompt bar's hints otherwise (the scene's `prompts`).
var _browsing_prompts: Dictionary[String, String] = {}

@onready var _tabs: TabContainer = %Tabs
@onready var _back: Button = %Back
@onready var _controls: ControlsTab = %Controls


func _ready() -> void:
	first_focus = _first_control(_tabs.get_current_tab_control())
	super()
	_browsing_prompts = prompts
	_back.pressed.connect(back_requested.emit)
	_tabs.tab_changed.connect(func(_tab: int) -> void:
		var control: Control = _first_control(_tabs.get_current_tab_control())
		if control != null:
			set_first_focus(control)
			control.grab_focus())
	_controls.listening_changed.connect(func(listening: bool) -> void:
		set_prompts(LISTENING_PROMPTS if listening else _browsing_prompts))


func _unhandled_input(event: InputEvent) -> void:
	if not has_focus_within():
		return
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
