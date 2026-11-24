extends Node
## The player's settings (the `Settings` autoload): one typed property per setting, applied by its setter the moment
## it is set, kept in `user://settings.cfg`.
##
## Each exported property is a setting and its `@export_category` its section in the file, so loading, saving and the
## settings screen walk one list, the property list, and a new setting is one property. A setting applies at once
## (there is no Apply button: a slider previews live) and is written 0.3 s after the last change, one write per drag.
##
## The file is a ConfigFile, not a Resource: a .tres under user:// could carry a script, and breaks when a property
## is renamed; a ConfigFile is text a player can read and fix, and a key that is missing or of the wrong type falls
## back to its default on its own. Tool and drive runs pass `--no-settings`: defaults, nothing read or written, and
## the window is left as the run opened it. The player's name is identity, not a setting: it comes with hero select.

## A setting changed (its property's name).
signal changed(setting: StringName)

enum WindowMode { WINDOWED, FULLSCREEN }

const PATH: String = "user://settings.cfg"
## How long after the last change the file is written, in seconds.
const SAVE_DELAY_S: float = 0.3

@export_category("video")
## Windowed, or fullscreen (borderless: switching needs no confirmation). An exported game starts fullscreen.
@export var window_mode: WindowMode = WindowMode.FULLSCREEN if OS.has_feature("template") else WindowMode.WINDOWED:
	set(value):
		window_mode = value
		if _applies_window:
			var mode: DisplayServer.WindowMode = (DisplayServer.WINDOW_MODE_FULLSCREEN
				if value == WindowMode.FULLSCREEN else DisplayServer.WINDOW_MODE_WINDOWED)
			if DisplayServer.window_get_mode() != mode:
				DisplayServer.window_set_mode(mode)
		_changed(&"window_mode")
@export var vsync: bool = true:
	set(value):
		vsync = value
		if _applies_window:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
		_changed(&"vsync")
## The most frames a second the game draws (0: no limit).
@export_range(0, 240, 1) var frame_limit: int = 0:
	set(value):
		frame_limit = value
		Engine.max_fps = value
		_changed(&"frame_limit")
## The share of the window's resolution the 3D world renders at (the interface always renders at full resolution).
@export_range(0.5, 1.0, 0.05) var render_scale: float = 1.0:
	set(value):
		render_scale = value
		get_tree().root.scaling_3d_scale = value
		_changed(&"render_scale")
@export var anti_aliasing: Viewport.MSAA = Viewport.MSAA_4X:
	set(value):
		anti_aliasing = value
		get_tree().root.msaa_3d = value
		_changed(&"anti_aliasing")
## The interface's size, over the canvas's 1920x1080 base (project.godot).
@export_range(0.8, 1.3, 0.05) var ui_scale: float = 1.0:
	set(value):
		ui_scale = value
		get_tree().root.content_scale_factor = value
		_changed(&"ui_scale")
@export var show_fps: bool = false:
	set(value):
		show_fps = value
		_changed(&"show_fps")

@export_category("audio")
## Linear, 0 to 1, as every volume.
@export_range(0.0, 1.0, 0.05) var master_volume: float = 0.8:
	set(value):
		master_volume = value
		_apply_master()
		_changed(&"master_volume")
## The menus' and the HUD's sounds (the Interface bus).
@export_range(0.0, 1.0, 0.05) var interface_volume: float = 0.8:
	set(value):
		interface_volume = value
		_set_bus_volume(&"Interface", value)
		_changed(&"interface_volume")
## Silence while the window is not in front.
@export var mute_in_background: bool = true:
	set(value):
		mute_in_background = value
		_apply_master()
		_changed(&"mute_in_background")

## Nothing is read or written (`--no-settings`).
var _isolated: bool = false
## The window is this process's to change: not isolated, not headless.
var _applies_window: bool = false
## The window is not in front (it lost the focus).
var _in_background: bool = false
## While the file loads: setting a value applies it, but is no change to save.
var _loading: bool = true
var _save_timer: Timer


func _ready() -> void:
	_isolated = "--no-settings" in OS.get_cmdline_user_args()
	_applies_window = not _isolated and DisplayServer.get_name() != "headless"
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY_S
	_save_timer.timeout.connect(save)
	add_child(_save_timer)
	var file := ConfigFile.new()
	if not _isolated:
		file.load(PATH)  # a missing file: every setting's default
	var sections: Dictionary[StringName, String] = _sections()
	for setting: StringName in sections:
		var value: Variant = get(setting)
		var saved: Variant = file.get_value(sections[setting], setting, value)
		set(setting, saved if typeof(saved) == typeof(value) else value)  # applies it
	_loading = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_in_background = what == NOTIFICATION_APPLICATION_FOCUS_OUT
		_apply_master()


## Writes every setting to the file now (a change does it by itself a moment later); the app's quit calls it.
func save() -> void:
	_save_timer.stop()
	if _isolated:
		return
	var file := ConfigFile.new()
	var sections: Dictionary[StringName, String] = _sections()
	for setting: StringName in sections:
		file.set_value(sections[setting], setting, get(setting))
	file.save(PATH)


## Every setting (an exported property) with the category it is under: its section in the file.
func _sections() -> Dictionary[StringName, String]:
	var out: Dictionary[StringName, String] = {}
	var section: String = ""
	for property: Dictionary in get_property_list():
		var usage: int = property["usage"]
		var property_name: String = property["name"]
		if usage & PROPERTY_USAGE_CATEGORY:
			section = property_name
		elif usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_EDITOR and section != "":
			out[StringName(property_name)] = section
	return out


func _changed(setting: StringName) -> void:
	if _loading:
		return
	changed.emit(setting)
	_save_timer.start()


## The Master bus: its volume, silent at zero, and while the window is behind others when the player asks for it.
## A run that may not change the window (a tool's, never in front) doesn't follow the focus either.
func _apply_master() -> void:
	_set_bus_volume(&"Master", master_volume)
	if mute_in_background and _in_background and _applies_window:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), true)


static func _set_bus_volume(bus: StringName, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(index, linear <= 0.001)
