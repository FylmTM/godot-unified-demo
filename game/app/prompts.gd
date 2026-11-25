extends Node
## The input prompts (the `Prompts` autoload): which glyph shows an action, for which device, in which family's look.
##
## The glyphs are Kenney's Input Prompts fonts, one per family (keyboard and mouse, Xbox, PlayStation, Switch), each
## with its glyph map baked into a GlyphMap (game/ui/prompts/). Fonts rather than the pack's PNGs: four files draw
## every key a player can bind, scale crisply with the interface, and take a label's colour. A key's glyph is its
## label on the player's layout (an AZERTY keyboard shows Z where a QWERTY one shows W), while bindings stay
## physical keys. A binding a map lacks shows as its name in text.
##
## A prompt follows a device. A local player fixed to one (a couch guest's pad, player 0's while a guest is in: the
## session's local devices) shows that device's; player 0 playing alone, and the menus, show the kind of device used
## last: a key, a mouse button or a real mouse move means the keyboard; a pad's button, its stick pushed past half or
## a trigger pressed past half means that pad (a stick's noise and a mouse's nudge don't count). A pad's family is the
## player's choice (Settings.prompt_style) or, on Auto, the pad's own, read from its name (family_of_name). The mouse
## cursor hides while a pad leads, and shows again with the keyboard or a real move of the mouse.
## `changed` says a prompt may show differently: the device kind or pad used last, a pad connected, the style, the
## bindings. A prompt redraws only when what it would show differs.

## A prompt may show differently now.
signal changed

## The glyph families: a font each.
enum Family { KEYBOARD, XBOX, PLAYSTATION, SWITCH }

## How far the mouse must move at once (pixels) to count as the player turning to it.
const MOUSE_MOVE: float = 6.0
## How far a stick or trigger must move to count as the player turning to its pad.
const PAD_PUSH: float = 0.5
## A pad's buttons (by JoyButton) as each pad family names their glyph; the D-pad and the sticks' presses too.
const PAD_BUTTONS: Dictionary[Family, Array] = {
	Family.XBOX: ["xbox_button_a", "xbox_button_b", "xbox_button_x", "xbox_button_y", "xbox_button_view",
		"xbox_guide", "xbox_button_menu", "xbox_ls", "xbox_rs", "xbox_lb", "xbox_rb", "xbox_dpad_up",
		"xbox_dpad_down", "xbox_dpad_left", "xbox_dpad_right"],
	Family.PLAYSTATION: ["playstation_button_cross", "playstation_button_circle", "playstation_button_square",
		"playstation_button_triangle", "playstation5_button_create", "", "playstation5_button_options",
		"playstation_button_l3", "playstation_button_r3", "playstation_trigger_l1", "playstation_trigger_r1",
		"playstation_dpad_up", "playstation_dpad_down", "playstation_dpad_left", "playstation_dpad_right"],
	# Godot names the buttons by position (A is the bottom one), and Switch pads letter them the other way round.
	Family.SWITCH: ["switch_button_b", "switch_button_a", "switch_button_y", "switch_button_x",
		"switch_button_minus", "switch_button_home", "switch_button_plus", "switch_stick_l_press",
		"switch_stick_r_press", "switch_button_l", "switch_button_r", "switch_dpad_up", "switch_dpad_down",
		"switch_dpad_left", "switch_dpad_right"],
}
## A pad's axes (by JoyAxis): left stick x and y, right stick x and y, left and right trigger.
const PAD_AXES: Dictionary[Family, Array] = {
	Family.XBOX: ["xbox_stick_l", "xbox_stick_l", "xbox_stick_r", "xbox_stick_r", "xbox_lt", "xbox_rt"],
	Family.PLAYSTATION: ["playstation_stick_l", "playstation_stick_l", "playstation_stick_r",
		"playstation_stick_r", "playstation_trigger_l2", "playstation_trigger_r2"],
	Family.SWITCH: ["switch_stick_l", "switch_stick_l", "switch_stick_r", "switch_stick_r", "switch_button_zl",
		"switch_button_zr"],
}
## Keys whose glyph isn't `keyboard_` and their name lowercased.
const KEY_GLYPHS: Dictionary[Key, String] = {
	KEY_UP: "keyboard_arrow_up", KEY_DOWN: "keyboard_arrow_down", KEY_LEFT: "keyboard_arrow_left",
	KEY_RIGHT: "keyboard_arrow_right", KEY_BRACKETLEFT: "keyboard_bracket_open",
	KEY_BRACKETRIGHT: "keyboard_bracket_close", KEY_SLASH: "keyboard_slash_forward",
	KEY_BACKSLASH: "keyboard_slash_back", KEY_QUOTELEFT: "keyboard_tilde", KEY_EQUAL: "keyboard_equals",
	KEY_PAGEUP: "keyboard_page_up", KEY_PAGEDOWN: "keyboard_page_down", KEY_CAPSLOCK: "keyboard_capslock",
	KEY_KP_ENTER: "keyboard_numpad_enter", KEY_PRINT: "keyboard_printscreen", KEY_SCROLLLOCK: "keyboard_scroll_lock",
	KEY_META: "keyboard_win", KEY_KP_0: "keyboard_0", KEY_KP_1: "keyboard_1", KEY_KP_2: "keyboard_2",
	KEY_KP_3: "keyboard_3", KEY_KP_4: "keyboard_4", KEY_KP_5: "keyboard_5", KEY_KP_6: "keyboard_6",
	KEY_KP_7: "keyboard_7", KEY_KP_8: "keyboard_8", KEY_KP_9: "keyboard_9", KEY_KP_ADD: "keyboard_numpad_plus",
	KEY_KP_SUBTRACT: "keyboard_minus", KEY_KP_MULTIPLY: "keyboard_asterisk", KEY_KP_DIVIDE: "keyboard_slash_forward",
	KEY_KP_PERIOD: "keyboard_period",
}
## Mouse buttons (by MouseButton) and their glyphs.
const MOUSE_GLYPHS: Dictionary[MouseButton, String] = {
	MOUSE_BUTTON_LEFT: "mouse_left", MOUSE_BUTTON_RIGHT: "mouse_right", MOUSE_BUTTON_MIDDLE: "mouse_scroll",
	MOUSE_BUTTON_XBUTTON1: "mouse_side_back", MOUSE_BUTTON_XBUTTON2: "mouse_side_forward",
}
## The moves on a pad: its left stick, one glyph.
const MOVE_STICK_GLYPHS: Dictionary[Family, String] = {
	Family.XBOX: "xbox_stick_l", Family.PLAYSTATION: "playstation_stick_l", Family.SWITCH: "switch_stick_l",
}
## The arrow keys, all four bound to the moves: one glyph.
const ARROWS_GLYPH: String = "keyboard_arrows_all"
## The mouse moving: how the keyboard player aims.
const MOUSE_AIM: String = "mouse_move"
## The right stick: how a pad player aims.
const AIM_STICK_GLYPHS: Dictionary[Family, String] = {
	Family.XBOX: "xbox_stick_r", Family.PLAYSTATION: "playstation_stick_r", Family.SWITCH: "switch_stick_r",
}
## Words in a pad's name that say its family, checked in this order (an "Xbox ... Pro Controller" is an Xbox pad).
const FAMILY_WORDS: Array[Array] = [
	[Family.XBOX, ["xbox", "xinput"]],
	[Family.PLAYSTATION, ["playstation", "dualsense", "dualshock", "ps3", "ps4", "ps5", "sony"]],
	[Family.SWITCH, ["nintendo", "switch", "joy-con", "joycon"]],
]

## Each family's font and glyph map (game/ui/prompts/, baked by game/tools/bake_glyphs.gd).
@export var maps: Dictionary[Family, GlyphMap] = {}

## The kind of device used last: Bindings.Kind.KEYBOARD, or PAD.
var last_kind: Bindings.Kind = Bindings.Kind.KEYBOARD
## The pad used last (its device id), whichever kind was used last.
var last_pad: int = 0


func _ready() -> void:
	for family: Family in Family.values():
		if not maps.has(family) or maps[family] == null or maps[family].glyphs.is_empty():
			push_error("Prompts: no glyph map for %s (game/tools/bake_glyphs.gd makes them)" % Family.find_key(family))
	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void: changed.emit())
	Settings.changed.connect(func(setting: StringName) -> void:
		if setting in [&"prompt_style", &"bindings"]:
			changed.emit())


func _input(event: InputEvent) -> void:
	var kind: int = Bindings.kind_of(event)
	var motion := event as InputEventMouseMotion
	if motion != null and motion.relative.length() >= MOUSE_MOVE:
		kind = Bindings.Kind.KEYBOARD
	var stick := event as InputEventJoypadMotion
	if stick != null and absf(stick.axis_value) < PAD_PUSH:
		kind = -1
	if kind == Bindings.Kind.PAD and event.device != last_pad:
		var family_before: Family = pad_family(last_pad)
		last_pad = event.device
		if last_kind == Bindings.Kind.PAD and pad_family(last_pad) != family_before:
			changed.emit()
	if kind >= 0 and kind != last_kind:
		last_kind = kind as Bindings.Kind
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if last_kind == Bindings.Kind.PAD else Input.MOUSE_MODE_VISIBLE
		changed.emit()


## The device kind local player `local` plays with: its own device's, else (no session, or a player reading every
## device) the kind used last.
func kind_of_local(local: int) -> Bindings.Kind:
	var device: int = _device_of_local(local)
	if device == UnifiedSession.DEVICE_KEYBOARD:
		return Bindings.Kind.KEYBOARD
	return Bindings.Kind.PAD if device >= 0 or last_kind == Bindings.Kind.PAD else Bindings.Kind.KEYBOARD


## The family local player `local`'s prompts draw in.
func family_of_local(local: int) -> Family:
	if kind_of_local(local) == Bindings.Kind.KEYBOARD:
		return Family.KEYBOARD
	var device: int = _device_of_local(local)
	return pad_family(device if device >= 0 else last_pad)


## The family a pad's glyphs come from: the player's choice, else the pad's own, read from its name.
func pad_family(device: int) -> Family:
	match Settings.prompt_style:
		Settings.PromptStyle.XBOX:
			return Family.XBOX
		Settings.PromptStyle.PLAYSTATION:
			return Family.PLAYSTATION
		Settings.PromptStyle.SWITCH:
			return Family.SWITCH
	return family_of_name(Input.get_joy_name(device))


## The family a pad of name `pad_name` (Input.get_joy_name) belongs to; an unknown pad's is Xbox.
static func family_of_name(pad_name: String) -> Family:
	var lowered: String = pad_name.to_lower()
	for entry: Array in FAMILY_WORDS:
		var words: Array = entry[1]
		for word: String in words:
			if lowered.contains(word):
				return entry[0]
	return Family.XBOX


## The font `family`'s glyphs draw in.
func font(family: Family) -> FontFile:
	return maps[family].font


## The glyphs of `actions` (one action, or the actions that make one control, like the four moves) in `family`
## (a local player's: family_of_local()): each action's first binding of that family's kind, in turn; the moves are
## one glyph on a pad (its left stick), and the four arrow keys one. The aim (no action: the mouse, or the right stick)
## is `&"aim"`. Empty when an action has no binding there or the font no glyph for it: text_of() says it in words.
func glyphs(actions: Array[StringName], family: Family) -> String:
	var out: String = ""
	for glyph_name: String in glyph_names(actions, family):
		var glyph: String = maps[family].glyphs.get(glyph_name, "")
		if glyph == "":
			return ""
		out += glyph
	return out


## The glyph names that show `actions` in `family` (see glyphs()).
func glyph_names(actions: Array[StringName], family: Family) -> PackedStringArray:
	if actions == [&"aim"]:
		return [MOUSE_AIM] if family == Family.KEYBOARD else [AIM_STICK_GLYPHS[family]]
	var kind: Bindings.Kind = Bindings.Kind.KEYBOARD if family == Family.KEYBOARD else Bindings.Kind.PAD
	var moves: bool = actions.all(func(action: StringName) -> bool: return action in Bindings.MOVE_ACTIONS)
	if kind == Bindings.Kind.PAD and moves:
		return [MOVE_STICK_GLYPHS[family]]
	var keys: Array[Key] = []
	var out: PackedStringArray = []
	for action: StringName in actions:
		var events: Array[InputEvent] = Bindings.events(action, kind)
		if events.is_empty():
			return []
		out.append(glyph_name(events[0], family))
		if events[0] is InputEventKey:
			keys.append(Bindings.key_of(events[0] as InputEventKey))
	var arrows: Array[Key] = [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
	if moves and keys.size() == 4 and keys.all(func(key: Key) -> bool: return key in arrows):
		return [ARROWS_GLYPH]
	return out


## One binding's glyph in `family` ("" where the font has none).
func glyph_of(event: InputEvent, family: Family) -> String:
	return maps[family].glyphs.get(glyph_name(event, family), "")


## The glyph name of one binding in `family`; a key's by its label on the player's layout.
func glyph_name(event: InputEvent, family: Family) -> String:
	if event is InputEventKey:
		var key: Key = _label_of(Bindings.key_of(event as InputEventKey))
		return KEY_GLYPHS.get(key, "keyboard_" + OS.get_keycode_string(key).to_lower().replace(" ", "_"))
	if event is InputEventMouseButton:
		return MOUSE_GLYPHS.get((event as InputEventMouseButton).button_index, "mouse")
	if event is InputEventJoypadButton and family != Family.KEYBOARD:
		var index: int = (event as InputEventJoypadButton).button_index
		var buttons: Array = PAD_BUTTONS[family]
		return buttons[index] if index >= 0 and index < buttons.size() else ""
	if event is InputEventJoypadMotion and family != Family.KEYBOARD:
		var axis: int = (event as InputEventJoypadMotion).axis
		var axes: Array = PAD_AXES[family]
		return axes[axis] if axis >= 0 and axis < axes.size() else ""
	return ""


## `actions`' first bindings (of `family`'s device kind) in words, one after another: what a prompt shows where its
## font has no glyph.
func text_of(actions: Array[StringName], family: Family) -> String:
	var kind: Bindings.Kind = Bindings.Kind.KEYBOARD if family == Family.KEYBOARD else Bindings.Kind.PAD
	var words: PackedStringArray = []
	for action: StringName in actions:
		var events: Array[InputEvent] = Bindings.events(action, kind)
		if events.is_empty():
			continue
		words.append(name_of(events[0]))
	return " ".join(words)


## One binding in words: a key by its label on the player's layout, anything else as Godot names it.
func name_of(event: InputEvent) -> String:
	if event is InputEventKey:
		return OS.get_keycode_string(_label_of(Bindings.key_of(event as InputEventKey)))
	return event.as_text().get_slice(" (", 0)


func _device_of_local(local: int) -> int:
	var session: UnifiedSession = Unified.session
	if session == null or not session.running or local not in session.get_local_indices():
		return UnifiedSession.DEVICE_ANY
	return session.get_local_device(local)


## The key a physical key types on the player's layout, when that is a Latin letter or a digit (an AZERTY keyboard's Z
## where a QWERTY one has W); else the key itself: a key that types nothing, a layout of another script (whose keys
## carry the Latin letters too, and the glyph fonts draw only those), or no layout to ask (a headless run).
static func _label_of(physical: Key) -> Key:
	if physical >= KEY_SPECIAL or DisplayServer.get_name() == "headless":
		return physical
	var label: Key = DisplayServer.keyboard_get_label_from_physical(physical)
	var latin: bool = (label >= KEY_A and label <= KEY_Z) or (label >= KEY_0 and label <= KEY_9)
	return label if latin else physical
