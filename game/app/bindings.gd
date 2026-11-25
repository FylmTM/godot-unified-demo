class_name Bindings
extends RefCounted
## The rebindable controls: which actions a player may bind, how a binding is kept as text, and how the rebound set
## becomes the InputMap that the game reads.
##
## Two schemes, one for the machine (not one per couch player: unified's input helpers read the same actions for every
## local player, filtered by that player's device): the keyboard and mouse, and the gamepad. Each rebindable action
## has two slots in each scheme, its first and second binding of that kind. On a pad the move stick and the D-pad stay
## as they are; on the keyboard every move direction is rebindable. Pause, join and the menus' own actions never
## are: they are the way back into everything.
##
## One rule keeps the controls whole: every action keeps at least one binding in each scheme. Clearing an action's
## last binding is refused, and so is binding a key that is another action's only one; a key another action holds
## beside a second one swaps (that action takes the key it replaced, so binding slot one to slot two's key and the
## reverse come out alike).
##
## project.godot's `[input]` is the one home of the defaults. The player's changes are `Settings.bindings`: for each
## action and kind it changed, that kind's whole binding list as text tokens (`key:E`, `mouse:1`, `button:2`,
## `axis:5+`), readable in the settings file and never Godot's object serialisation (a settings file should never
## make the game construct objects). A scheme absent from the file is project.godot's; a token from the file is held
## to can_bind like a press (one that doesn't parse, or is reserved, is dropped). unified's per-device tracking asks
## InputEvent.is_action when an event arrives, so a new map is followed at once; apply() lets go of every action it
## changes, so none stays held from its old binding.

## A binding's device kind: the keyboard and mouse, or a gamepad.
enum Kind { KEYBOARD, PAD }

## Every rebindable action, in the order the controls screen lists them. (`interact` is the player's Grab.)
const ACTIONS: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right", &"attack", &"interact"]
## Each rebindable action as the player reads it (the controls screen, a refusal's reason).
const NAMES: Dictionary[StringName, String] = {
	&"move_up": "Move up", &"move_down": "Move down", &"move_left": "Move left", &"move_right": "Move right",
	&"attack": "Attack", &"interact": "Grab",
}
## The move actions (the pad's are its stick and D-pad, never rebound).
const MOVE_ACTIONS: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right"]
## How many bindings of each kind an action has on the controls screen.
const SLOTS: int = 2
## The kinds' names in Settings.bindings.
const KIND_NAMES: Array[String] = ["keyboard", "pad"]
## Keys no action takes: Esc (pause, and backing out of everything), Enter (the menus' accept), F1 and F3 (the dev UI,
## the F3 note).
const RESERVED_KEYS: Array[Key] = [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_F1, KEY_F3]
## Pad buttons no action takes: Start (pause and join), Back and Guide, and the D-pad (it moves).
const RESERVED_BUTTONS: Array[JoyButton] = [JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_GUIDE, JOY_BUTTON_DPAD_UP,
	JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]
## The pad axes a binding may be: the triggers, pressed past half.
const TRIGGER_AXES: Array[JoyAxis] = [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]
## The mouse buttons a binding may be (not the wheel).
const MOUSE_BUTTONS: Array[MouseButton] = [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE,
	MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]


## What a change to the bindings came to: the new bindings, or why it was refused (then `bindings` is unchanged).
class Change:
	## The bindings after the change.
	var bindings: Dictionary
	## Why the change was refused ("" when it wasn't).
	var refused: String

	func _init(change_bindings: Dictionary, change_refused: String = "") -> void:
		bindings = change_bindings
		refused = change_refused


## Whether `action` is rebindable in scheme `kind`.
static func rebindable(action: StringName, kind: Kind) -> bool:
	return action in ACTIONS and (kind == Kind.KEYBOARD or action not in MOVE_ACTIONS)


## The kind of device `event` comes from: PAD for a joypad's, KEYBOARD for a key's or the mouse's, -1 for any other.
static func kind_of(event: InputEvent) -> int:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return Kind.PAD
	if event is InputEventKey or event is InputEventMouseButton:
		return Kind.KEYBOARD
	return -1


## `action`'s bindings of `kind`, in order (the InputMap's, as applied).
static func events(action: StringName, kind: Kind) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if kind_of(event) == kind:
			out.append(event)
	return out


## Whether a player may bind `event` in scheme `kind`: a key or mouse button (not the wheel) for the keyboard, a pad
## button or a trigger past half for the pad, none of them reserved.
static func can_bind(event: InputEvent, kind: Kind) -> bool:
	if kind == Kind.KEYBOARD and event is InputEventKey:
		var key: Key = key_of(event as InputEventKey)
		return key != KEY_NONE and key not in RESERVED_KEYS
	if kind == Kind.KEYBOARD and event is InputEventMouseButton:
		return (event as InputEventMouseButton).button_index in MOUSE_BUTTONS
	if kind == Kind.PAD and event is InputEventJoypadButton:
		var pad_button: JoyButton = (event as InputEventJoypadButton).button_index
		return pad_button >= 0 and pad_button < JOY_BUTTON_SDL_MAX and pad_button not in RESERVED_BUTTONS
	if kind == Kind.PAD and event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return motion.axis in TRIGGER_AXES and motion.axis_value > 0.5
	return false


## Puts `event` in slot `slot` of `action`'s `kind` under `bindings` (Settings.bindings). An action that held `event`
## takes the binding replaced (a swap), or loses `event` when the slot was empty and it has another; refused when that
## would leave it with none.
static func bind(bindings: Dictionary, action: StringName, kind: Kind, slot: int, event: InputEvent) -> Change:
	var lists: Dictionary[StringName, Array] = _lists(bindings, kind)
	var mine: Array = lists[action]
	var token: String = to_token(event)
	var replaced: String = mine[slot] if slot < mine.size() else ""
	if replaced == token:
		return Change.new(bindings)
	for other: StringName in lists:
		var theirs: Array = lists[other]
		var at: int = theirs.find(token)
		if at < 0:
			continue
		if other == action:
			theirs.remove_at(at)  # it moves to `slot`; the slot it leaves takes the binding replaced
			if replaced != "":
				theirs.insert(at, replaced)
		elif replaced != "" and replaced not in theirs:
			theirs[at] = replaced
		elif theirs.size() > 1:
			theirs.remove_at(at)
		else:
			return Change.new(bindings, "That is %s's only binding." % NAMES[other])
	if slot < mine.size():
		mine[slot] = token
	else:
		mine.append(token)
	return Change.new(_with(bindings, kind, lists))


## Clears slot `slot` of `action`'s `kind` under `bindings`; refused when it is the action's last binding there.
static func clear(bindings: Dictionary, action: StringName, kind: Kind, slot: int) -> Change:
	var lists: Dictionary[StringName, Array] = _lists(bindings, kind)
	var mine: Array = lists[action]
	if slot >= mine.size():
		return Change.new(bindings)
	if mine.size() == 1:
		return Change.new(bindings, "%s needs a binding." % NAMES[action])
	mine.remove_at(slot)
	return Change.new(_with(bindings, kind, lists))


## `bindings` with every action of `kind` back to project.godot's.
static func reset(bindings: Dictionary, kind: Kind) -> Dictionary:
	var out: Dictionary = bindings.duplicate(true)
	for action: String in out.keys():
		var kinds: Dictionary = out[action] if out[action] is Dictionary else {}
		kinds.erase(KIND_NAMES[kind])
		if kinds.is_empty():
			out.erase(action)
	return out


## Makes every rebindable action's InputMap project.godot's bindings with `bindings` (Settings.bindings) over them,
## and lets go of each action whose bindings changed (it may be held through a binding it no longer has).
static func apply(bindings: Dictionary) -> void:
	for action: StringName in ACTIONS:
		var before: Array[String] = []
		for event: InputEvent in InputMap.action_get_events(action):
			before.append(to_token(event))
		var after: Array[String] = []
		for kind: Kind in [Kind.KEYBOARD, Kind.PAD]:
			after.append_array(_tokens(bindings, action, kind))
		if after == before:
			continue
		InputMap.action_erase_events(action)
		for token: String in after:
			InputMap.action_add_event(action, from_token(token))
		Input.action_release(action)


## `event` as a token: `key:<physical key>`, `mouse:<button>`, `button:<pad button>`, `axis:<axis><+ or ->`.
static func to_token(event: InputEvent) -> String:
	if event is InputEventKey:
		return "key:" + OS.get_keycode_string(key_of(event as InputEventKey))
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	if event is InputEventJoypadButton:
		return "button:%d" % (event as InputEventJoypadButton).button_index
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return "axis:%d%s" % [motion.axis, "+" if motion.axis_value > 0.0 else "-"]
	return ""


## The binding a token names, for every device (null: it doesn't parse).
static func from_token(token: String) -> InputEvent:
	var kind: String = token.get_slice(":", 0)
	var value: String = token.get_slice(":", 1)
	if token.get_slice_count(":") != 2 or value == "":
		return null
	match kind:
		"key":
			var key: Key = OS.find_keycode_from_string(value)
			if key == KEY_NONE:
				return null
			var event := InputEventKey.new()
			event.physical_keycode = key
			event.device = -1
			return event
		"mouse":
			if not value.is_valid_int():
				return null
			var event := InputEventMouseButton.new()
			event.button_index = value.to_int() as MouseButton
			event.device = -1
			return event
		"button":
			if not value.is_valid_int():
				return null
			var event := InputEventJoypadButton.new()
			event.button_index = value.to_int() as JoyButton
			event.device = -1
			return event
		"axis":
			var direction: String = value.right(1)
			if direction not in ["+", "-"] or not value.left(-1).is_valid_int():
				return null
			var event := InputEventJoypadMotion.new()
			event.axis = value.left(-1).to_int() as JoyAxis
			event.axis_value = 1.0 if direction == "+" else -1.0
			event.device = -1
			return event
	return null


## The key an event names: its physical key, else its key (the menus' actions bind by key).
static func key_of(event: InputEventKey) -> Key:
	return event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode


## `action`'s tokens of `kind` under `bindings`: the file's, each held to can_bind, when the file has that scheme for
## the action (even empty); project.godot's when it hasn't.
static func _tokens(bindings: Dictionary, action: StringName, kind: Kind) -> Array[String]:
	var changed: Variant = bindings.get(String(action))
	var kinds: Dictionary = changed if changed is Dictionary else {}
	var tokens: Variant = kinds.get(KIND_NAMES[kind])
	if not tokens is Array or not rebindable(action, kind):
		return _defaults(action, kind)
	var out: Array[String] = []
	var list: Array = tokens
	for token: Variant in list:
		var event: InputEvent = from_token(str(token))
		if event != null and can_bind(event, kind) and to_token(event) not in out:
			out.append(to_token(event))
	return out


## `action`'s tokens of `kind` in project.godot.
static func _defaults(action: StringName, kind: Kind) -> Array[String]:
	var out: Array[String] = []
	var project: Dictionary = ProjectSettings.get_setting("input/" + action, {})
	var list: Array = project.get("events", [])
	for item: Variant in list:
		var event: InputEvent = item
		if kind_of(event) == kind:
			out.append(to_token(event))
	return out


## Each rebindable action's tokens of `kind` under `bindings`, to edit.
static func _lists(bindings: Dictionary, kind: Kind) -> Dictionary[StringName, Array]:
	var out: Dictionary[StringName, Array] = {}
	for action: StringName in ACTIONS:
		if rebindable(action, kind):
			out[action] = Array(_tokens(bindings, action, kind))
	return out


## `bindings` with `kind`'s lists replaced by `lists`: an action whose list is its default again is dropped.
static func _with(bindings: Dictionary, kind: Kind, lists: Dictionary[StringName, Array]) -> Dictionary:
	var out: Dictionary = reset(bindings, kind)
	for action: StringName in lists:
		if lists[action] != Array(_defaults(action, kind)):
			var kinds: Dictionary = out.get_or_add(String(action), {})
			kinds[KIND_NAMES[kind]] = lists[action]
	return out
