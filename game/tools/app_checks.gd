class_name AppChecks
extends RefCounted
## The app layer's contract, checked: the godot suite's validate step runs it (game/tools/validate.gd) beside the art
## checks, so a broken promise between the app's parts fails the suite instead of a player's evening.
##
## - The autoloads stand in the order they need each other: LibraryCheck first (it must run without the library),
##   then Settings and Sfx, then Game, which uses both.
## - The project's theme is game/ui/theme.tres, and every type variation a scene names is in it: Godot silently draws a
##   missing one with the plain type's look.
## - Every control of the HUD lets clicks through and never takes the focus, so the mouse aims and a pad's A plays.
## - Every button of the menus and overlays takes the focus, so a pad reaches it.
## - Every sound a button names (its `sfx` metadata) is one of Sfx's.
##
## Each problem is reported through the validate run's log capture, named by the file it is in.

const AUTOLOADS: Array[StringName] = [&"LibraryCheck", &"Settings", &"Sfx", &"Game"]
const THEME: String = "res://game/ui/theme.tres"
const HUD: String = "res://game/play/hud.tscn"
const SFX: String = "res://game/app/sfx.tscn"
## The scenes whose buttons a pad must reach: the menus and the app's overlays and widgets.
const FOCUS_DIRS: Array[String] = ["res://game/menu/", "res://game/ui/"]
const GAME: String = "res://game/"

## How many problems the checks found.
var problems: int = 0

var _log: UnifiedLogCapture


## Checks report to `log_capture`.
func _init(log_capture: UnifiedLogCapture) -> void:
	_log = log_capture


## Runs every check.
func run() -> void:
	_check_autoloads()
	_check_theme()
	_check_hud()
	_check_focus()
	_check_sounds()


func _check_autoloads() -> void:
	var found: Array[StringName] = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var property_name: String = property["name"]
		if property_name.begins_with("autoload/"):
			found.append(StringName(property_name.trim_prefix("autoload/")))
	if found != AUTOLOADS:
		_problem("the autoloads are %s, want %s in that order" % [found, AUTOLOADS], "res://project.godot")


func _check_theme() -> void:
	var project_theme: String = ProjectSettings.get_setting("gui/theme/custom", "")
	if project_theme != THEME:
		_problem("the project's theme is '%s', want %s" % [project_theme, THEME], "res://project.godot")
		return
	var theme: Theme = load(THEME)
	var types: PackedStringArray = theme.get_type_list()
	for path: String in _scenes(GAME):
		var state: SceneState = (load(path) as PackedScene).get_state()
		for node: int in state.get_node_count():
			for property: int in state.get_node_property_count(node):
				if state.get_node_property_name(node, property) != &"theme_type_variation":
					continue
				var variation: String = state.get_node_property_value(node, property)
				if variation not in types:
					_problem("%s names theme type %s, which the theme lacks" % [state.get_node_path(node), variation],
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
		for path: String in _scenes(dir):
			var scene: Node = (load(path) as PackedScene).instantiate()
			for found: Node in scene.find_children("*", "BaseButton", true, false):
				var button := found as BaseButton
				if button.focus_mode != Control.FOCUS_ALL:
					_problem("%s can't take the focus: a pad can't reach it" % scene.get_path_to(button), path)
			scene.free()


func _check_sounds() -> void:
	var sfx: Node = (load(SFX) as PackedScene).instantiate()
	var sounds: Dictionary = sfx.get(&"sounds")
	sfx.free()
	for path: String in _scenes(GAME):
		var state: SceneState = (load(path) as PackedScene).get_state()
		for node: int in state.get_node_count():
			for property: int in state.get_node_property_count(node):
				if state.get_node_property_name(node, property) != &"metadata/sfx":
					continue
				var sound: StringName = state.get_node_property_value(node, property)
				if not sounds.has(sound):
					_problem("%s plays sound %s, which Sfx lacks (%s)" % [state.get_node_path(node), sound, SFX], path)


## Every scene under `dir`, its subfolders included.
func _scenes(dir: String) -> Array[String]:
	var out: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == "tscn":
			out.append(dir + file)
	for sub: String in DirAccess.get_directories_at(dir):
		out.append_array(_scenes(dir + sub + "/"))
	return out


func _problem(message: String, at: String) -> void:
	problems += 1
	_log.add(message, at)
