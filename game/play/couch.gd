class_name Couch
extends Node
## Who plays on which device, for couch co-op. Alone, the first player plays with every device: a solo player picks up
## the pad or the keyboard whenever. A pad nobody plays joins as another local player when it presses Start; the
## device the first player last played with (moved, aimed, attacked or grabbed with: the menus and a mouse's nudge
## don't count) is theirs, so its Start pauses instead. While a couch guest is in, the first player is fixed to that
## device, so a guest's pad moves only the guest; once the last guest has left, or the session refused the join, the
## first player has every device again.
##
## The join is read in _input, which reaches the scene before the autoloads: what the first player last played with is
## decided from before the press, never from the Start being pressed (Prompts, an autoload, sees it after).

## The first connected pad nobody plays changed (-1: none): the HUD's join hint speaks to it.
signal idle_pad_changed(device: int)

## The actions whose input says which device the first player plays with.
const PLAY_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"aim_left", &"aim_right", &"aim_up", &"aim_down",
	&"attack", &"interact",
]

## The device the first player last played with: DEVICE_KEYBOARD or a pad's id. It starts as the menus' last.
var first_device: int = UnifiedSession.DEVICE_KEYBOARD
## The idle pad last announced.
var _idle_pad: int = -2

## The session whose local players this assigns devices to: the app's.
@onready var _session: UnifiedSession = Unified.session


func _ready() -> void:
	first_device = (UnifiedSession.DEVICE_KEYBOARD if Prompts.last_kind == Bindings.Kind.KEYBOARD
		else Prompts.last_pad)
	_session.local_player_refused.connect(func(_local: int, _reason: String) -> void: _place_first.call_deferred())
	_session.local_players_changed.connect(_place_first)
	Input.joy_connection_changed.connect(_announce_idle_pad.unbind(2))
	_place_first()


func _input(event: InputEvent) -> void:
	if not _session.game_input:
		return  # an overlay holds the game's input: its keys aren't the game's
	if event.is_action_pressed(&"join") and not claimed(event.device):
		get_viewport().set_input_as_handled()
		_join(event.device)
		return
	var device: int = _device_of(event)
	if device == UnifiedSession.DEVICE_ANY or _session.get_local_device(0) != UnifiedSession.DEVICE_ANY:
		return
	for action: StringName in PLAY_ACTIONS:
		if event.is_action_pressed(action) and device != first_device:
			first_device = device
			_announce_idle_pad()
			return


## Whether a local player plays on the pad `device`: its own pad, or, for the first player alone, the device it last
## played with.
func claimed(device: int) -> bool:
	for local: int in _session.get_local_indices():
		if _session.get_local_device(local) == device:
			return true
	return _session.get_local_device(0) == UnifiedSession.DEVICE_ANY and first_device == device


## The first connected pad nobody plays (-1: none).
func idle_pad() -> int:
	for device: int in Input.get_connected_joypads():
		if not claimed(device):
			return device
	return -1


func _join(device: int) -> void:
	var profile := UnifiedProfile.new()
	profile.class = EnumClass.ANY  # the first class no hero plays (the sim resolves it on arrival)
	_fix_first()  # at once: until the session has the guest in, its pad must not move the first player
	var local: int = _session.add_local_player(device, "Pad %d" % (device + 1), profile)
	# A UnifiedProfile is an Object, not reference-counted: freed here once the session has read it (docs/plan.md,
	# Needed from unified: a RefCounted Profile).
	profile.free()
	if local < 0:
		_place_first()


## Fixes the first player to the device it last played with (a guest is coming in).
func _fix_first() -> void:
	if _session.get_local_device(0) == UnifiedSession.DEVICE_ANY:
		_session.set_local_device(0, first_device)
	_announce_idle_pad()


## The first player's device for who plays now: fixed while a guest is in, every device alone.
func _place_first() -> void:
	if _session.get_local_indices().size() > 1:
		_fix_first()
		return
	if _session.get_local_device(0) != UnifiedSession.DEVICE_ANY:
		_session.set_local_device(0, UnifiedSession.DEVICE_ANY)
	_announce_idle_pad()


func _announce_idle_pad() -> void:
	var pad: int = idle_pad()
	if pad != _idle_pad:
		_idle_pad = pad
		idle_pad_changed.emit(pad)


## The device an event comes from: a joypad event's pad (a stick only once pushed past half), the keyboard for a key
## or a mouse button, none (DEVICE_ANY) for anything else.
static func _device_of(event: InputEvent) -> int:
	if event is InputEventJoypadButton:
		return event.device
	if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) >= Prompts.PAD_PUSH:
		return event.device
	if event is InputEventKey or event is InputEventMouseButton:
		return UnifiedSession.DEVICE_KEYBOARD
	return UnifiedSession.DEVICE_ANY
