class_name AppChecks
extends RefCounted
## The app layer's contract, checked: the godot suite's validate step runs it (game/tools/validate.gd) beside the art
## checks, so a broken promise between the app's parts fails the suite instead of a player's evening.
##
## - The autoloads stand in the order they need each other: LibraryCheck first (it must run without the library),
##   then Settings, Sfx and Prompts, then Game, which uses them. The buses the code names exist.
## - A pad can press and back out: ui_accept and ui_cancel each carry a pad button.
## - The project's theme is game/ui/theme.tres, and every type variation a scene names is in it: Godot silently draws a
##   missing one with the plain type's look.
## - Every control of the HUD lets clicks through and never takes the focus, so the mouse aims and a pad's A plays.
## - Every button of the menus and overlays can take the focus (the d-pad reaches it only if it can), but those marked
##   `mouse_only` (a seat card's arrows: each seat answers to its own device, not to the one focus), which never may.
## - Every sound a button names (its `sfx` metadata) is one Sfx has. (That the buttons sound at all is the walk's.)
## - Bindings: every default binding's token reads back as itself; the one rule (a swap both ways alike, an action's
##   last binding kept), a mouse button, a trigger and a second slot bind; reserved keys and buttons, the wheel and
##   junk are refused, by a press or from the file, and an empty list in the file is no binding, not the defaults.
## - Prompts: each baked glyph map is its source's; real pad names read as their family; every glyph the prompts'
##   tables name, and every default binding's, is in its family's map.
## - Every class has a square portrait.
## - Settings round-trip a file: a first run picks one of the game's names and saves it; saved values read back (the
##   bindings, the pads' glyphs, the dead zone, the name and the picks among them); a name is cleaned and cut to what
##   the other players get, a blank one is a game's name again; the picks are always four valid choices; a value
##   missing, of the wrong type or out of range falls back or is clamped, a whole number is taken for a fraction; a
##   file that doesn't parse is kept as .bad, defaults used, and a fresh file written.
## - The save slot round-trips a file of its own (Saves): a save kept reads back as itself, with its line; a second
##   one replaces it; a write cut before its move reads from the .tmp; a write that fails says so and keeps the save
##   for the session; a damaged file and one another version made are moved aside, with the reason, the slot empty.
##
## Each problem is reported through the validate run's log capture, named by the file it is in.

const AUTOLOADS: Array[StringName] = [&"LibraryCheck", &"Settings", &"Sfx", &"Prompts", &"Game"]
const BUSES: Array[StringName] = [&"Master", &"Interface"]
const PAD_ACTIONS: Array[StringName] = [&"ui_accept", &"ui_cancel"]
const THEME: String = "res://game/ui/theme.tres"
const HUD: String = "res://game/play/hud.tscn"
const SFX: String = "res://game/app/sfx.tscn"
const SETTINGS: String = "res://game/app/settings.gd"
## The scenes whose buttons a pad must reach: the menus and the app's overlays and widgets.
const FOCUS_DIRS: Array[String] = ["res://game/menu/", "res://game/ui/", "res://game/app/"]
const GAME: String = "res://game/"
## The files the settings and saves checks write, under the run's own user data (uni gives every tool run its own):
## never the player's.
const SETTINGS_FILE: String = "user://settings_check.json"
const SAVE_FILE: String = "user://save_check.json"

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
	_check_bindings()
	_check_prompts()
	_check_portraits()
	_check_settings()
	_check_saves()


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
				var mouse_only: bool = button.get_meta(&"mouse_only", false)
				if button.focus_mode != Control.FOCUS_ALL and not mouse_only:
					_problem("%s can't take the focus: a pad can't reach it" % scene.get_path_to(button), path)
			scene.free()


func _check_bindings() -> void:
	const AT: String = "res://game/app/bindings.gd"
	var keyboard: Bindings.Kind = Bindings.Kind.KEYBOARD
	var pad: Bindings.Kind = Bindings.Kind.PAD
	Bindings.apply({})
	for action: StringName in Bindings.ACTIONS:
		for kind: Bindings.Kind in [keyboard, pad]:
			for event: InputEvent in Bindings.events(action, kind):
				var token: String = Bindings.to_token(event)
				var back: InputEvent = Bindings.from_token(token)
				if back == null or Bindings.to_token(back) != token:
					_problem("%s's binding %s doesn't read back from its token" % [action, token], AT)
	# A key from another action that has two: a swap.
	var change: Bindings.Change = Bindings.bind({}, &"attack", keyboard, 0, _key(KEY_F))
	change = Bindings.bind(change.bindings, &"interact", keyboard, 0, _key(KEY_F))
	_expect_tokens(change, &"interact", keyboard, ["key:F", "mouse:2"], "F binds to Grab")
	_expect_tokens(change, &"attack", keyboard, ["key:E", "key:Space"], "attack takes Grab's E in the swap")
	# Within one action, slot two to slot one's key and slot one to slot two's come out alike.
	var down: Bindings.Change = Bindings.bind({}, &"attack", keyboard, 1, Bindings.from_token("mouse:1"))
	var up: Bindings.Change = Bindings.bind({}, &"attack", keyboard, 0, Bindings.from_token("key:Space"))
	_expect_tokens(down, &"attack", keyboard, ["key:Space", "mouse:1"], "a swap between slots, downward")
	_expect_tokens(up, &"attack", keyboard, ["key:Space", "mouse:1"], "a swap between slots, upward")
	# The one rule: no action is left without a binding.
	if Bindings.clear({}, &"interact", pad, 0).refused == "":
		_problem("clearing Grab's only pad binding isn't refused", AT)
	var one_slot: Dictionary = Bindings.clear({}, &"attack", pad, 1).bindings
	if Bindings.bind(one_slot, &"attack", pad, 1, Bindings.from_token("button:0")).refused == "":
		_problem("taking Grab's only pad binding into attack's empty slot isn't refused", AT)
	_expect_tokens(Bindings.bind({}, &"attack", pad, 0, Bindings.from_token("button:0")), &"interact", pad,
		["axis:5+"], "into a full slot it swaps: Grab takes attack's trigger")
	if Bindings.clear({}, &"attack", keyboard, 1).refused != "":
		_problem("clearing one of attack's two keyboard bindings is refused", AT)
	# A mouse button, a trigger, a second slot.
	_expect_tokens(Bindings.bind({}, &"attack", keyboard, 1, Bindings.from_token("mouse:9")), &"attack", keyboard,
		["mouse:1", "mouse:9"], "a side mouse button binds to the second slot")
	_expect_tokens(Bindings.bind({}, &"attack", pad, 1, Bindings.from_token("axis:4+")), &"attack", pad,
		["axis:5+", "axis:4+"], "the left trigger binds to the second slot")
	# Reserved and junk, by a press or from the file.
	for token: String in ["key:Escape", "key:Enter", "key:F1", "mouse:4", "button:6", "button:11", "axis:0+"]:
		var event: InputEvent = Bindings.from_token(token)
		if Bindings.can_bind(event, Bindings.kind_of(event) as Bindings.Kind):
			_problem("%s may be bound" % token, AT)
	Bindings.apply({"attack": {"keyboard": ["key:Escape", "mouse:4", "junk", "key:G"]}})
	if _tokens(&"attack", keyboard) != ["key:G"]:
		_problem("the file's reserved and junk tokens aren't dropped: %s" % [_tokens(&"attack", keyboard)], AT)
	Bindings.apply({"attack": {"keyboard": []}})
	if not _tokens(&"attack", keyboard).is_empty():
		_problem("an empty list in the file is taken for the defaults", AT)
	if not Bindings.reset({"attack": {"keyboard": ["key:G"]}}, keyboard).is_empty():
		_problem("resetting the keyboard doesn't drop its changes", AT)
	var live: Dictionary = _tree_root.get_node(^"Settings").get(&"bindings")
	Bindings.apply(live)  # the run's own bindings again


func _key(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	return event


func _tokens(action: StringName, kind: Bindings.Kind) -> Array[String]:
	var out: Array[String] = []
	for event: InputEvent in Bindings.events(action, kind):
		out.append(Bindings.to_token(event))
	return out


func _expect_tokens(change: Bindings.Change, action: StringName, kind: Bindings.Kind, want: Array[String],
		what: String) -> void:
	Bindings.apply(change.bindings)
	var got: Array[String] = _tokens(action, kind)
	if change.refused != "" or got != want:
		_problem("%s: %s, want %s (%s)" % [what, got, want, change.refused], "res://game/app/bindings.gd")


func _check_prompts() -> void:
	const AT: String = "res://game/app/prompts.gd"
	var prompts: Node = _tree_root.get_node(^"Prompts")
	var script: Script = prompts.get_script()
	var tables: Dictionary = script.get_script_constant_map()
	var families: Dictionary = tables["Family"]
	var maps: Dictionary = prompts.get(&"maps")
	for family: int in families.values():
		var map: GlyphMap = maps.get(family)
		if map == null:
			_problem("no glyph map for %s" % families.find_key(family), AT)
			return
		if GlyphMap.parse(FileAccess.get_file_as_string(map.source)) != map.glyphs:
			_problem("%s differs from its source %s: run ./uni tool bake_glyphs" % [map.resource_path, map.source], AT)
		if map.font.resource_path.get_basename() + "_map.txt" != map.source:
			_problem("%s's font isn't its map's" % map.resource_path, AT)
	var names: Dictionary[String, String] = {
		"Xbox Series X Controller": "XBOX", "XInput Gamepad (GLFW)": "XBOX", "Xbox Elite Pro Controller": "XBOX",
		"PS5 Controller": "PLAYSTATION", "DualSense Wireless Controller": "PLAYSTATION",
		"Sony PLAYSTATION(R)3 Controller": "PLAYSTATION", "Nintendo Switch Pro Controller": "SWITCH",
		"Joy-Con (L)": "SWITCH", "Generic USB Gamepad": "XBOX", "": "XBOX",
	}
	for pad_name: String in names:
		var family: int = script.call(&"family_of_name", pad_name)
		if families.find_key(family) != names[pad_name]:
			_problem("a pad named '%s' reads as %s, want %s" % [pad_name, families.find_key(family),
				names[pad_name]], AT)
	var keyboard: int = families["KEYBOARD"]
	var wanted: Array[PackedStringArray] = []  # by family: the glyph names its map must hold
	wanted.resize(families.size())
	for table: String in ["PAD_BUTTONS", "PAD_AXES"]:
		var by_family: Dictionary = tables[table]
		for family: int in by_family:
			var glyph_names: Array = by_family[family]
			for glyph_name: String in glyph_names:
				wanted[family].append(glyph_name)
	for table: String in ["MOVE_STICK_GLYPHS", "AIM_STICK_GLYPHS"]:
		var by_family: Dictionary = tables[table]
		for family: int in by_family:
			var glyph_name: String = by_family[family]
			wanted[family].append(glyph_name)
	for table: String in ["KEY_GLYPHS", "MOUSE_GLYPHS"]:
		var glyphs: Dictionary = tables[table]
		for glyph_name: String in glyphs.values():
			wanted[keyboard].append(glyph_name)
	var mouse_aim: String = tables["MOUSE_AIM"]
	var arrows: String = tables["ARROWS_GLYPH"]
	wanted[keyboard].append_array([mouse_aim, arrows])
	for family: int in families.values():
		for action: StringName in InputMap.get_actions():
			var shown: bool = (not action.begins_with("ui_") or action in [&"ui_accept", &"ui_cancel"])
			for event: InputEvent in InputMap.action_get_events(action):
				if shown and (Bindings.kind_of(event) == Bindings.Kind.KEYBOARD) == (family == keyboard):
					var glyph_name: String = prompts.call(&"glyph_name", event, family)
					wanted[family].append(glyph_name)
	for family: int in families.values():
		var map: GlyphMap = maps[family]
		for glyph_name: String in wanted[family]:
			if glyph_name != "" and not map.glyphs.has(glyph_name):
				_problem("glyph %s isn't in family %s's map" % [glyph_name, families.find_key(family)], AT)


## Every class has its portrait (game/tools/render_portraits.gd renders them), square, as the cards and plates draw it.
func _check_portraits() -> void:
	for hero_class: int in Heroes.classes():
		var portrait: Texture2D = Heroes.portrait(hero_class)
		var at: String = Heroes.portrait_path(hero_class)
		if portrait == null:
			_problem("no portrait: run ./uni tool render_portraits --window", at)
		elif portrait.get_width() != portrait.get_height():
			_problem("a portrait isn't square (%s)" % portrait.get_size(), at)


func _check_settings() -> void:
	var engine: Dictionary = _engine_values()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE + ".bad"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	var settings: Node = _settings_from_file()
	var first_name: String = settings.get(&"player_name")
	_expect(first_name in Settings.NAMES and FileAccess.file_exists(SETTINGS_FILE),
		"a first run picks one of the game's names and saves it at once (%s)" % first_name)
	settings.free()
	settings = _settings_from_file()
	var kept_name: String = settings.get(&"player_name")
	_expect(kept_name == first_name, "the picked name is kept (%s, %s)" % [first_name, kept_name])
	_check_names(settings)
	var bindings: Dictionary = {"attack": {"keyboard": ["key:F", "key:Space"]}}
	settings.set(&"show_fps", true)
	settings.set(&"render_scale", 0.75)
	settings.set(&"bindings", bindings)
	settings.set(&"prompt_style", 2)
	settings.set(&"move_deadzone", 0.4)
	settings.set(&"player_name", "Ясень")
	settings.set(&"hero_picks", [EnumClass.MAGE, EnumClass.ANY, EnumClass.ROGUE, EnumClass.KNIGHT])
	settings.call(&"save")
	settings.free()
	settings = _settings_from_file()
	var shown: bool = settings.get(&"show_fps")
	var render_scale: float = settings.get(&"render_scale")
	var read_bindings: Dictionary = settings.get(&"bindings")
	var style: int = settings.get(&"prompt_style")
	var deadzone: float = settings.get(&"move_deadzone")
	_expect(shown and render_scale == 0.75, "saved settings read back (%s, %s)" % [shown, render_scale])
	_expect(read_bindings == bindings and style == 2 and is_equal_approx(deadzone, 0.4),
		"the controls read back (%s, %s, %s)" % [read_bindings, style, deadzone])
	_expect(Bindings.to_token(Bindings.events(&"attack", Bindings.Kind.KEYBOARD)[0]) == "key:F",
		"the bindings read back apply")
	var read_name: String = settings.get(&"player_name")
	var read_picks: Array = settings.get(&"hero_picks")
	_expect(read_name == "Ясень", "the player's name reads back (%s)" % read_name)
	_expect(read_picks == [EnumClass.MAGE, EnumClass.ANY, EnumClass.ROGUE, EnumClass.KNIGHT],
		"the picks read back (%s)" % [read_picks])
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
	_expect(problem.contains("line"), "a file that doesn't parse says where (%s)" % problem)
	_expect(FileAccess.file_exists(SETTINGS_FILE + ".bad"), "a file that doesn't parse is kept as .bad")
	_expect(JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_FILE)) is Dictionary,
		"a fresh file is written in its place, with the player's new name")
	settings.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE + ".bad"))
	_restore_engine_values(engine)
	var live: Dictionary = _tree_root.get_node(^"Settings").get(&"bindings")
	Bindings.apply(live)  # the run's own bindings again
	var live_deadzone: float = _tree_root.get_node(^"Settings").get(&"move_deadzone")
	for action: StringName in Bindings.MOVE_ACTIONS:
		InputMap.action_set_deadzone(action, live_deadzone)


## The name and the picks as Settings keeps them: a name cleaned and cut to what the other players get (on a
## character's boundary), nothing left the default again; the picks always four valid choices.
func _check_names(settings: Node) -> void:
	var cases: Array[Array] = [
		["  Bell	ringer
 ", "Bellringer"],
		["A".repeat(40), "A".repeat(UnifiedSession.NAME_MAX)],
		["Я".repeat(20), "Я".repeat(15)],  # two bytes each: 15 fit in UnifiedSession.NAME_MAX (31)
	]
	for case: Array in cases:
		settings.set(&"player_name", case[0])
		var kept: String = settings.get(&"player_name")
		var want: String = case[1]
		_expect(kept == want, "the name '%s' kept as '%s' (got '%s')" % [case[0], want, kept])
	settings.set(&"player_name", " 
 ")
	var blank: String = settings.get(&"player_name")
	_expect(blank in Settings.NAMES, "a blank name falls back to one of the game's (%s)" % blank)
	settings.set(&"hero_picks", [EnumClass.MAGE, 99, "Knight"])
	var picks: Array = settings.get(&"hero_picks")
	_expect(picks == [EnumClass.MAGE, EnumClass.ANY, EnumClass.ANY, EnumClass.ANY],
		"the picks normalised to four valid choices (%s)" % [picks])


func _check_saves() -> void:
	var slot := Saves.new(true, SAVE_FILE)
	for path: String in [slot.path, slot.path + ".tmp", slot.bad_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var save := UnifiedSetup.new()
	save.version = Unified.constants.save_version
	save.surges = 7
	save.kills = 312
	_expect_save(Saves.new(false, SAVE_FILE).keep(save), "a save is written")
	var read := Saves.new(false, SAVE_FILE)
	var ok: bool = read.setup != null and read.setup.to_json() == save.to_json() and read.problem == ""
	_expect_save(ok, "a kept save reads back as itself")
	_expect_save(read.summary() == "Floor 1 · Surge 7 · 312 felled", "its line: %s" % read.summary())
	var later: UnifiedSetup = UnifiedSetup.from_json(save.to_json())
	later.surges = 8
	_expect_save(read.keep(later), "a second save is written over the first")
	read = Saves.new(false, SAVE_FILE)
	_expect_save(read.setup != null and read.setup.surges == 8, "and reads back as the newer one")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_FILE), ProjectSettings.globalize_path(SAVE_FILE
		+ ".tmp"))
	read = Saves.new(false, SAVE_FILE)
	_expect_save(read.setup != null and read.setup.surges == 8, "a write cut before its move reads from the .tmp")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_FILE + ".tmp"))
	var unwritable := Saves.new(false, "user://no_such_folder/save.json")
	_expect_save(not unwritable.keep(save) and unwritable.setup == save,
		"a write that fails says so and keeps the save for the session")
	var other: UnifiedSetup = UnifiedSetup.from_json(save.to_json())
	other.version = save.version + 1
	for broken: String in ["{\"version\": 1, \"surges\": ", other.to_json()]:
		var file := FileAccess.open(SAVE_FILE, FileAccess.WRITE)
		file.store_string(broken)
		file.close()
		read = Saves.new(false, SAVE_FILE)
		_expect_save(read.setup == null and read.problem != "", "a save that can't continue is refused (%s)" % broken)
		_expect_save(FileAccess.file_exists(read.bad_path) and not FileAccess.file_exists(SAVE_FILE),
			"and kept aside as %s" % read.bad_path.get_file())
		DirAccess.remove_absolute(ProjectSettings.globalize_path(read.bad_path))


func _expect_save(cond: bool, what: String) -> void:
	if not cond:
		_problem("saves: expected " + what, "res://game/app/saves.gd")


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
