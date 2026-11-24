class_name AppChecks
extends RefCounted
## The app layer's contract, checked: the godot suite's validate step runs it (game/tools/validate.gd) beside the art
## checks, so a broken promise between the app's parts fails the suite instead of a player's evening.
##
## - The autoloads stand in the order they need each other: LibraryCheck first (it must run without the library),
##   then Settings and Sfx, then Game, which uses both. The buses the code names exist.
## - A pad can press and back out: ui_accept and ui_cancel each carry a pad button.
## - The project's theme is game/ui/theme.tres, and every type variation a scene names is in it: Godot silently draws a
##   missing one with the plain type's look.
## - Every control of the HUD lets clicks through and never takes the focus, so the mouse aims and a pad's A plays.
## - Every button of the menus and overlays can take the focus (the d-pad reaches it only if it can).
## - Every sound a button names (its `sfx` metadata) is one Sfx has. (That the buttons sound at all is the walk's.)
## - Settings round-trip a file: saved values read back; a value missing, of the wrong type or out of range falls back
##   or is clamped, a whole number is taken for a fraction; a file that doesn't parse is kept as .bad, defaults used.
##
## Each problem is reported through the validate run's log capture, named by the file it is in.

const AUTOLOADS: Array[StringName] = [&"LibraryCheck", &"Settings", &"Sfx", &"Game"]
const BUSES: Array[StringName] = [&"Master", &"Interface"]
const PAD_ACTIONS: Array[StringName] = [&"ui_accept", &"ui_cancel"]
const THEME: String = "res://game/ui/theme.tres"
const HUD: String = "res://game/play/hud.tscn"
const SFX: String = "res://game/app/sfx.tscn"
const SETTINGS: String = "res://game/app/settings.gd"
## The scenes whose buttons a pad must reach: the menus and the app's overlays and widgets.
const FOCUS_DIRS: Array[String] = ["res://game/menu/", "res://game/ui/", "res://game/app/"]
const GAME: String = "res://game/"
## The file the settings check writes, under the run's own user data (uni gives every tool run its own).
const SETTINGS_FILE: String = "user://settings_check.json"

## How many problems the checks found.
var problems: int = 0

var _log: UnifiedLogCapture
var _tree_root: Window


## Checks report to `log_capture`; `tree_root` is where a Settings under test runs.
func _init(log_capture: UnifiedLogCapture, tree_root: Window) -> void:
	_log = log_capture
	_tree_root = tree_root


## Runs every check.
func run() -> void:
	_check_project()
	_check_scenes()
	_check_hud()
	_check_focus()
	_check_settings()


func _check_project() -> void:
	var found: Array[StringName] = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var property_name: String = property["name"]
		if property_name.begins_with("autoload/"):
			found.append(StringName(property_name.trim_prefix("autoload/")))
	if found != AUTOLOADS:
		_problem("the autoloads are %s, want %s in that order" % [found, AUTOLOADS], "res://project.godot")
	for bus: StringName in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			_problem("no audio bus %s, which the code plays on" % bus, "res://game/app/bus_layout.tres")
	for action: StringName in PAD_ACTIONS:
		var pad: bool = InputMap.action_get_events(action).any(func(e: InputEvent) -> bool:
			return e is InputEventJoypadButton and e.device == -1)
		if not pad:
			_problem("%s has no pad button (for every pad: device -1)" % action, "res://project.godot")
	var project_theme: String = ProjectSettings.get_setting("gui/theme/custom", "")
	if project_theme != THEME:
		_problem("the project's theme is '%s', want %s" % [project_theme, THEME], "res://project.godot")


## One pass over every scene's properties: the theme variations they name, and the sounds their buttons name.
func _check_scenes() -> void:
	var types: PackedStringArray = (load(THEME) as Theme).get_type_list()
	var sfx: Node = (load(SFX) as PackedScene).instantiate()
	var sounds: Dictionary = sfx.get(&"sounds")
	sfx.free()
	for path: String in ArtChecks.scenes(GAME):
		var state: SceneState = (load(path) as PackedScene).get_state()
		for node: int in state.get_node_count():
			for property: int in state.get_node_property_count(node):
				var property_name: StringName = state.get_node_property_name(node, property)
				if property_name == &"theme_type_variation":
					var variation: String = state.get_node_property_value(node, property)
					if variation not in types:
						_problem("%s names theme type %s, which the theme lacks" % [state.get_node_path(node),
							variation], path)
				elif property_name == &"metadata/sfx":
					var sound: StringName = state.get_node_property_value(node, property)
					if not sounds.has(sound):
						_problem("%s plays sound %s, which Sfx lacks (%s)" % [state.get_node_path(node), sound, SFX],
							path)


func _check_hud() -> void:
	var hud: Node = (load(HUD) as PackedScene).instantiate()
	for control: Node in [hud] + hud.find_children("*", "Control", true, false):
		var c := control as Control
		if c.mouse_filter != Control.MOUSE_FILTER_IGNORE or c.focus_mode != Control.FOCUS_NONE:
			_problem("%s takes clicks or the focus: the HUD's controls let both through" % hud.get_path_to(c), HUD)
	hud.free()


func _check_focus() -> void:
	for dir: String in FOCUS_DIRS:
		for path: String in ArtChecks.scenes(dir):
			var scene: Node = (load(path) as PackedScene).instantiate()
			for found: Node in scene.find_children("*", "BaseButton", true, false):
				var button := found as BaseButton
				if button.focus_mode != Control.FOCUS_ALL:
					_problem("%s can't take the focus: a pad can't reach it" % scene.get_path_to(button), path)
			scene.free()


func _check_settings() -> void:
	var engine: Dictionary = _engine_values()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE + ".bad"))
	var settings: Node = _settings_from_file()
	settings.set(&"show_fps", true)
	settings.set(&"render_scale", 0.75)
	settings.call(&"save")
	settings.free()
	settings = _settings_from_file()
	var shown: bool = settings.get(&"show_fps")
	var render_scale: float = settings.get(&"render_scale")
	_expect(shown and render_scale == 0.75, "saved settings read back (%s, %s)" % [shown, render_scale])
	settings.free()
	_write_settings_file(JSON.stringify({"video": {"show_fps": "yes", "render_scale": 5, "frame_limit": 60.0},
		"audio": {"master_volume": 1}}))
	settings = _settings_from_file()
	shown = settings.get(&"show_fps")
	render_scale = settings.get(&"render_scale")
	var frame_limit: int = settings.get(&"frame_limit")
	var master_volume: float = settings.get(&"master_volume")
	var vsync: bool = settings.get(&"vsync")
	_expect(not shown, "a value of the wrong type falls back to its default")
	_expect(render_scale == 1.0, "a value out of range is clamped (%s)" % render_scale)
	_expect(frame_limit == 60, "a whole fraction is taken for a whole number (%s)" % frame_limit)
	_expect(master_volume == 1.0, "a whole number is taken for a fraction (%s)" % master_volume)
	_expect(vsync, "a missing value keeps its default")
	settings.free()
	_write_settings_file("{\"video\": {not json")
	settings = _settings_from_file()
	render_scale = settings.get(&"render_scale")
	var problem: String = settings.get(&"read_problem")
	_expect(render_scale == 1.0, "a file that doesn't parse leaves the defaults")
	_expect(problem.contains(".bad"), "a file that doesn't parse says so (%s)" % problem)
	_expect(FileAccess.file_exists(SETTINGS_FILE + ".bad") and not FileAccess.file_exists(SETTINGS_FILE),
		"a file that doesn't parse is kept as .bad")
	settings.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE + ".bad"))
	_restore_engine_values(engine)


## A Settings that reads and writes SETTINGS_FILE, loaded (it is in the tree).
func _settings_from_file() -> Node:
	var settings: Node = (load(SETTINGS) as GDScript).new()
	settings.set(&"isolated", false)
	settings.set(&"path", SETTINGS_FILE)
	_tree_root.add_child(settings)
	return settings


func _write_settings_file(text: String) -> void:
	var file := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## What a Settings applies to the engine, to put back after the check's ones did.
func _engine_values() -> Dictionary:
	var buses: Dictionary = {}
	for bus: StringName in BUSES:
		var index: int = AudioServer.get_bus_index(bus)
		buses[bus] = [AudioServer.get_bus_volume_db(index), AudioServer.is_bus_mute(index)]
	return {"max_fps": Engine.max_fps, "scale_3d": _tree_root.scaling_3d_scale, "msaa": _tree_root.msaa_3d,
		"content_scale": _tree_root.content_scale_factor, "buses": buses}


func _restore_engine_values(values: Dictionary) -> void:
	Engine.max_fps = values["max_fps"]
	_tree_root.scaling_3d_scale = values["scale_3d"]
	_tree_root.msaa_3d = values["msaa"]
	_tree_root.content_scale_factor = values["content_scale"]
	var buses: Dictionary = values["buses"]
	for bus: StringName in BUSES:
		var index: int = AudioServer.get_bus_index(bus)
		var state: Array = buses[bus]
		var volume_db: float = state[0]
		var mute: bool = state[1]
		AudioServer.set_bus_volume_db(index, volume_db)
		AudioServer.set_bus_mute(index, mute)


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_problem("settings: expected " + what, SETTINGS)


func _problem(message: String, at: String) -> void:
	problems += 1
	_log.add(message, at)
