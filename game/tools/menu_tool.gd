class_name MenuTool
extends UnifiedTool
## The base of the tool scripts that drive Crypt Crew's own menus (ui_walk): its screens and their controls by unique
## name, the app's overlays and flow, real key and mouse events, and the sounds the interface played. A tool script
## compiles before the autoloads exist, so it reaches them through the tree, untyped (`game`), and reads what it needs
## into typed values here.

## Every sound the interface played since record_sounds(), in order (Sfx's `played`).
var sounds: Array[StringName] = []
## The interface size the run looks at (look_at_scale(): `--ui-scale=`), which a part that changes it goes back to.
var ui_scale: float = 1.0


## A look pass at another interface size, from the script's arguments: `--ui-scale=0.8` sets it (ui_scale; 1.0
## without). The window's size is uni's (`uni tool --window --size WxH`).
func look_at_scale() -> void:
	ui_scale = arg("ui-scale", "1.0").to_float()
	set_setting(&"ui_scale", ui_scale)
	await frames(3)


## A real click on `c` (UnifiedTool.click), scrolled into view first as a player would scroll to it (a big interface
## size scrolls a settings tab). In a window the cursor is then parked outside it: a cursor left where the click was
## would hover whatever the next screen puts there, and the game gives the hovered button the focus.
func click(c: Control, button := MOUSE_BUTTON_LEFT) -> void:
	var scroll: ScrollContainer = null
	var up: Node = c.get_parent() if c != null else null
	while up != null and scroll == null:
		scroll = up as ScrollContainer
		up = up.get_parent()
	if scroll != null:
		var was: int = scroll.scroll_vertical
		scroll.ensure_control_visible(c)
		if scroll.scroll_vertical != was:
			await frames(2)
	await super(c, button)
	if DisplayServer.get_name() != "headless":
		Input.warp_mouse(Vector2(-16.0, -16.0))


## Starts recording the interface's sounds into `sounds`.
func record_sounds() -> void:
	root.get_node(^"Sfx").connect(&"played", func(sound: StringName) -> void: sounds.append(sound))


## How many times `sound` played since `from` (an index into `sounds`).
func played(sound: StringName, from: int) -> int:
	return sounds.slice(from).count(sound)


## The title screen, while the menu is the current scene (else null).
func title() -> Control:
	return current_scene.get_node_or_null(^"UI/Stack/TitleScreen") as Control if scene_is("Menu") else null


## The menu's screen on top (the title, the settings), while the menu is the current scene (else null).
func top_screen() -> Control:
	var stack: Node = current_scene.get_node_or_null(^"UI/Stack") if scene_is("Menu") else null
	if stack == null:
		return null
	var top: Control = stack.call(&"top")
	return top


## The interface's last device kind (Prompts.last_kind): Bindings.Kind.KEYBOARD or PAD.
func last_kind() -> int:
	return root.get_node(^"Prompts").get(&"last_kind")


## The control the title's focus starts on: Continue when there is a save, else New game.
func title_focus() -> Control:
	var focus: Control = title().get(&"first_focus")
	return focus


## The title screen's control `unique_name` (null, failing the run, when it isn't there).
func title_control(unique_name: String) -> Control:
	return find(title(), "%" + unique_name) as Control


## One of the app's overlays (game/app/game.tscn): Connecting, LinkStatus, Dialog, Toasts (on its own layer, under the
## play scene's menus).
func overlay(overlay_name: String) -> Control:
	return find(game, ("Notices/" if overlay_name == "Toasts" else "Overlays/") + overlay_name) as Control


## The app's flow (Game.flow) by its name: MENU, STARTING, PLAYING, QUITTING.
func flow_name() -> String:
	var script: Script = game.get_script()
	var flows: Dictionary = script.get_script_constant_map()[&"Flow"]
	var flow: int = game.get(&"flow")
	return str(flows.find_key(flow))


## Sets a player setting, as the settings screen does.
func set_setting(setting_name: StringName, value: Variant) -> void:
	root.get_node(^"Settings").set(setting_name, value)


## A member of one of Settings' enums by name (`&"Hints"`, `&"ALWAYS"`), read from its script: a tool script compiles
## before the autoloads exist.
func setting_value(enum_name: StringName, member: StringName) -> int:
	var script: Script = root.get_node(^"Settings").get_script()
	var members: Dictionary = script.get_script_constant_map()[enum_name]
	var value: int = members[member]
	return value


## A player setting's value.
func setting(setting_name: StringName) -> Variant:
	return root.get_node(^"Settings").get(setting_name)


## The local player's hero view (null until it has one).
func local_hero() -> Node3D:
	if session == null:
		return null
	return session.get_player_view(EnumView.HERO, session.local_player) as Node3D


## Presses and releases a key, as the keyboard sends it (its keycode and its physical keycode, so actions bound either
## way see it, and on the press the character it types, a letter in lower case), a frame apart.
func press_key(key: Key) -> void:
	if failed():
		return
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		if pressed:
			event.unicode = _typed(key)
		Input.parse_input_event(event)
		await process_frame
	await process_frame


## The character a key types without a modifier (0: none): a letter in lower case, a digit, a space.
static func _typed(key: Key) -> int:
	if key >= KEY_A and key <= KEY_Z:
		return key - KEY_A + "a".unicode_at(0)
	if (key >= KEY_0 and key <= KEY_9) or key == KEY_SPACE:
		return key
	return 0


## Holds a key down, or lets it go (press_key does both), as the keyboard sends it.
func key(key_code: Key, pressed: bool) -> void:
	if failed():
		return
	var event := InputEventKey.new()
	event.keycode = key_code
	event.physical_keycode = key_code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame


## Nudges the mouse by `relative` pixels where it is, as a hand on the desk does.
func nudge_mouse(relative: Vector2) -> void:
	if failed():
		return
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_mouse_position()
	motion.global_position = motion.position
	motion.relative = relative
	Input.parse_input_event(motion)
	await process_frame


## What the menu's prompt bar says now, its hints' words in order.
func prompt_words() -> PackedStringArray:
	var out: PackedStringArray = []
	var bar: Node = current_scene.get_node_or_null(^"UI/PromptBar") if scene_is("Menu") else null
	if bar != null:
		for prompt: Node in bar.get_children():
			out.append((prompt.get_node(^"%Text") as Label).text)
	return out


## Moves the mouse over the control's centre, as a player's hand does, without clicking.
func hover(c: Control) -> void:
	if c == null or failed():
		return
	var pos: Vector2 = c.get_viewport().get_final_transform() * (c.get_global_transform_with_canvas() * (c.size / 2.0))
	Input.warp_mouse(pos)
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await process_frame
	await process_frame
