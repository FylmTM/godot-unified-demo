extends Node
## The player's settings (the `Settings` autoload): one typed property per setting, applied by its setter the moment
## it is set, kept in `user://settings.json`.
##
## Each exported property is a setting and its `@export_category` its section in the file, so loading and saving walk
## one list, the property list, and a settings screen row reads its control from the property it names: a new
## setting is a property and a row. A setting applies at once (there is no Apply button: a slider previews live) and
## is written 0.3 s after the last change, one write per drag.
##
## The file is JSON a player can read and fix, and loading it runs nothing (a .tres under user:// could carry a script,
## and breaks when a property is renamed). Each value is taken on its own: one that is missing, of another type or
## outside its property's range or enum falls back to its default or is clamped, a whole number is taken for a
## fraction, and a file that doesn't parse is kept beside as settings.json.bad, never overwritten (`read_problem`).
## (JSON, not a ConfigFile: Godot reports a damaged ConfigFile as an engine error, JSON as a value.) Tool and drive
## runs pass `--no-settings`: nothing is read, written or applied, so the engine stays as the run opened it;
## `--settings-path=` names another file (the app checks round-trip one under the run's own user data).
##
## The player's name goes to every other player, so it is never read from the system: a new player gets one of the
## game's own names (NAMES), saved with the first run's file; a tool run's is always TOOL_NAME, so shots and logs read
## the same on every machine.

## A setting changed (its property's name).
signal changed(setting: StringName)

enum WindowMode { WINDOWED, FULLSCREEN }
## Which pad's glyphs the prompts draw: the pad's own (AUTO, from its name), or one family for every pad.
enum PromptStyle { AUTO, XBOX, PLAYSTATION, SWITCH }
## When the HUD shows each local hero's controls: for a few seconds after the player joins or changes device, always,
## or never.
enum Hints { BRIEFLY, ALWAYS, NEVER }

## The settings file, unless `--settings-path=` names another.
const PATH: String = "user://settings.json"
## A new player's name, one picked at random, until they choose their own.
const NAMES: Array[String] = ["Sexton", "Lantern", "Gravedigger", "Bellringer", "Mourner", "Lamplighter", "Ferryman",
	"Torchbearer", "Candlewick", "Bonepicker"]
## Every tool run's name (`--no-settings`).
const TOOL_NAME: String = "Adventurer"
## Hero select's seats, each with its last pick.
const SEATS: int = 4
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
@export_enum("Off:0", "60:60", "120:120", "144:144", "240:240") var frame_limit: int = 0:
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
## Multisample anti-aliasing of the 3D world (a Viewport.MSAA value).
@export_enum("Off:0", "2x:1", "4x:2") var anti_aliasing: int = Viewport.MSAA_4X:
	set(value):
		anti_aliasing = value
		get_tree().root.msaa_3d = value as Viewport.MSAA
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

@export_category("controls")
## The rebound actions, as Bindings stores them (text tokens by action and scheme); a scheme absent for an action keeps
## project.godot's bindings. Bindings holds every token to what a press may bind as it applies them.
@export var bindings: Dictionary = {}:
	set(value):
		bindings = value
		Bindings.apply(value)
		_changed(&"bindings")
## Which glyphs the prompts draw for a pad.
@export_enum("Auto:0", "Xbox:1", "PlayStation:2", "Switch:3") var prompt_style: int = PromptStyle.AUTO:
	set(value):
		prompt_style = value
		_changed(&"prompt_style")
## How far the move stick must lean before it moves the hero (the aim stick keeps project.godot's).
@export_range(0.1, 0.5, 0.05) var move_deadzone: float = 0.25:
	set(value):
		move_deadzone = value
		for action: StringName in Bindings.MOVE_ACTIONS:
			InputMap.action_set_deadzone(action, value)
		_changed(&"move_deadzone")

@export_category("player")
## The name the other players see (the session's local_name): control characters dropped, the edges' spaces trimmed,
## cut to UnifiedSession.NAME_MAX bytes (what the other players get); nothing left is the default name again.
@export var player_name: String = "":
	set(value):
		var clean: String = clean_name(value)
		player_name = clean if clean != "" else _default_name
		_changed(&"player_name")
## Each party place's last pick (EnumClass, Any included), by local index: hero select's first seat is place 0 and each
## taken seat after it the next place; a pad joining mid-game takes the place of the local index it gets. Always
## SEATS picks, each one of Heroes.choices() (a whole number read as a fraction is taken; anything else is Any).
@export var hero_picks: Array = [0, 0, 0, 0]:
	set(value):
		var picks: Array = []
		for place: int in SEATS:
			var pick: Variant = value[place] if place < value.size() else EnumClass.ANY
			if pick is float:  # as JSON reads a number
				var number: float = pick
				pick = roundi(number) if is_equal_approx(number, roundf(number)) else EnumClass.ANY
			picks.append(pick if pick is int and pick in Heroes.choices() else EnumClass.ANY)
		hero_picks = picks
		_changed(&"hero_picks")

@export_category("gameplay")
## How hard the camera shakes when a local hero is hurt, 0 (never) to 1 (full).
@export_range(0.0, 1.0, 0.05) var screen_shake: float = 1.0:
	set(value):
		screen_shake = value
		_changed(&"screen_shake")
## When the HUD shows each local hero's controls, as glyphs for its player's device.
@export_enum("Briefly:0", "Always:1", "Off:2") var hints: int = Hints.BRIEFLY:
	set(value):
		hints = value
		_changed(&"hints")

## The file read and written: PATH, or `--settings-path=`. Set before the node enters the tree to use another.
var path: String = PATH
## Nothing is read, written or applied at load (`--no-settings`). Set before the node enters the tree to change it.
var isolated: bool = false
## Why the file didn't read at load, the parser's words ("" when it did, or there was none): the menu tells the player
## once (Game).
var read_problem: String = ""

## The window is this process's to change: not isolated, not headless.
var _applies_window: bool = false
## The window is not in front (it lost the focus).
var _in_background: bool = false
## While the file loads: setting a value applies it, but is no change to save.
var _loading: bool = true
## The name an empty one falls back to: this run's pick from NAMES, or TOOL_NAME.
var _default_name: String = ""
var _save_timer: Timer


func _init() -> void:
	isolated = "--no-settings" in OS.get_cmdline_user_args()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--settings-path="):
			path = arg.trim_prefix("--settings-path=")
	_default_name = TOOL_NAME if isolated else NAMES.pick_random()
	player_name = _default_name  # a file's name replaces it; a tool script may name its player before _ready


func _ready() -> void:
	_applies_window = not isolated and DisplayServer.get_name() != "headless"
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY_S
	_save_timer.timeout.connect(save)
	add_child(_save_timer)
	var picked: String = TOOL_NAME if isolated else NAMES.pick_random()  # `isolated` may have changed since _init
	if player_name == _default_name:
		player_name = picked  # unless a tool script named its player already
	_default_name = picked
	var named: bool = false
	if not isolated:
		var saved: Dictionary = _read()
		for setting: Dictionary in _settings():
			var setting_name: StringName = setting["name"]
			var section: Variant = saved.get(setting["section"])
			var values: Dictionary = section if section is Dictionary else {}
			named = named or (setting_name == &"player_name" and values.get(setting_name) is String)
			set(setting_name, _valid(setting, values.get(setting_name)))  # applies it
	_loading = false
	if not isolated and not named:
		save()  # the first run: the name picked for this player is theirs from now on


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_in_background = what == NOTIFICATION_APPLICATION_FOCUS_OUT
		_apply_master()


## Writes every setting to the file now (a change does it by itself a moment later); the app's quit calls it. It is
## written beside and moved over the old one, so a crash mid-write never leaves half a file.
func save() -> void:
	_save_timer.stop()
	if isolated:
		return
	var out: Dictionary = {}
	for setting: Dictionary in _settings():
		var setting_name: StringName = setting["name"]
		var section: Dictionary = out.get_or_add(setting["section"], {})
		section[setting_name] = get(setting_name)
	var temp: String = path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_warning("Settings: can't write %s (%s)" % [temp, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(out, "	", true) + "
")
	file.close()
	DirAccess.rename_absolute(temp, path)


## The file's sections; empty when there is none. One that doesn't parse is moved to <path>.bad, so the next save
## starts a fresh file without losing what the player wrote, and says why in `read_problem` and the log. (Printed,
## not a warning: uni fails a run on any warning of the game's, and the app checks make this happen on purpose.)
func _read() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary:
		return json.data
	read_problem = "%s, line %d" % [json.get_error_message(), json.get_error_line() + 1]
	print("Settings: %s doesn't read (%s): kept as %s.bad, the defaults used" % [path, read_problem, path.get_file()])
	DirAccess.rename_absolute(path, path + ".bad")
	return {}


## Every setting, as its property's entry (name, type, hint, hint_string) with its `section`: the category it is
## under.
func _settings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var section: String = ""
	for property: Dictionary in get_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_CATEGORY:
			section = property["name"]
		elif usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_EDITOR and section != "":
			var setting: Dictionary = property.duplicate()
			setting["section"] = section
			out.append(setting)
	return out


## `saved` as a value of `setting`: of its type (a whole number taken for a fraction, and the other way when it is
## whole), within its range (clamped) or one of its enum's values; else the setting's current value, its default.
func _valid(setting: Dictionary, saved: Variant) -> Variant:
	var setting_name: StringName = setting["name"]
	var current: Variant = get(setting_name)
	var value: Variant = saved
	if current is float and saved is int:
		var whole: int = saved
		value = float(whole)
	elif current is int and saved is float:
		var fraction: float = saved
		if is_equal_approx(fraction, roundf(fraction)):
			value = roundi(fraction)
	if typeof(value) != typeof(current):
		return current
	var hint: int = setting["hint"]
	var hint_string: String = setting["hint_string"]
	var bounds: PackedStringArray = hint_string.split(",")
	if hint == PROPERTY_HINT_RANGE and value is float:
		var number: float = value
		return clampf(number, bounds[0].to_float(), bounds[1].to_float())
	if hint == PROPERTY_HINT_RANGE and value is int:
		var count: int = value
		return clampi(count, bounds[0].to_int(), bounds[1].to_int())
	if hint == PROPERTY_HINT_ENUM:
		var member: int = value
		return value if member in _enum_values(bounds) else current
	return value


## The values an enum property's hint lists (its hint string's entries, "Windowed" or "Disabled:0"): each entry's own
## value, else its place.
static func _enum_values(names: PackedStringArray) -> Array[int]:
	var out: Array[int] = []
	for i: int in names.size():
		out.append(names[i].get_slice(":", 1).to_int() if names[i].contains(":") else i)
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


## `text` as a player's name: control characters dropped, the edges' spaces trimmed, cut to UnifiedSession.NAME_MAX
## bytes of UTF-8 on a character's boundary ("" when nothing is left).
static func clean_name(text: String) -> String:
	var kept: String = ""
	for i: int in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x20 and not (code >= 0x7f and code < 0xa0):
			kept += text[i]
	kept = kept.strip_edges()
	while kept.to_utf8_buffer().size() > UnifiedSession.NAME_MAX:
		kept = kept.left(-1)
	return kept.strip_edges()


static func _set_bus_volume(bus: StringName, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(index, linear <= 0.001)
