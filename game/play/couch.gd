class_name Couch
extends Node
## Who plays on which device, for couch co-op. The first player reads every device until their first game input
## (a move, an aim, an attack or an interact) claims its device: a pad's, or the keyboard and mouse. A pad nobody has
## claimed joins as another local player when it presses Start; a claimed pad's Start is left to the play scene (it
## pauses). When a pad joins while the first player still reads every device, the first player takes the keyboard and
## mouse, and gets every device back if the session refuses the joiner.
##
## It stands after the session in the tree (the session is in the Game autoload, before every scene): Godot hands an
## input event to later nodes first, so a device is claimed before the session tracks the event that claimed it, and
## that first press reaches the sim.

## The actions whose input claims a device for the first player.
const PLAY_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"aim_left", &"aim_right", &"aim_up", &"aim_down",
	&"attack", &"interact",
]

## The joiner whose join moved the first player onto the keyboard, until the session takes or refuses it (-1: none).
var _joiner: int = -1

## The session whose local players this assigns devices to: the app's.
@onready var _session: UnifiedSession = Unified.session


func _ready() -> void:
	_session.local_player_refused.connect(_on_local_player_refused)
	_session.local_players_changed.connect(_on_local_players_changed)


func _input(event: InputEvent) -> void:
	if not _session.game_input:
		return  # an overlay holds the game's input: a press there claims nothing
	var device: int = _device_of(event)
	if device == UnifiedSession.DEVICE_ANY or _session.get_local_device(0) != UnifiedSession.DEVICE_ANY:
		return
	for action: StringName in PLAY_ACTIONS:
		if event.is_action_pressed(action):
			_session.set_local_device(0, device)
			return


## An unclaimed pad's Start joins it; the event is handled whether the session takes it or not.
func _unhandled_input(event: InputEvent) -> void:
	if not _session.game_input or not event.is_action_pressed(&"join") or is_claimed(event.device):
		return
	get_viewport().set_input_as_handled()
	var profile := UnifiedProfile.new()
	profile.class = EnumClass.ANY  # the first class no hero plays (the sim resolves it on arrival)
	var local: int = _session.add_local_player(event.device, "Pad %d" % (event.device + 1), profile)
	if local >= 0 and _session.get_local_device(0) == UnifiedSession.DEVICE_ANY:
		_session.set_local_device(0, UnifiedSession.DEVICE_KEYBOARD)
		_joiner = local


## Whether a local player plays on the pad `device`.
func is_claimed(device: int) -> bool:
	for local: int in _session.get_local_indices():
		if _session.get_local_device(local) == device:
			return true
	return false


## The device an event comes from: a joypad event's pad, the keyboard for a key or a mouse button, none (DEVICE_ANY)
## for anything else, such as an action a driver presses (`uni drive press`), which no device sends.
func _device_of(event: InputEvent) -> int:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return event.device
	if event is InputEventKey or event is InputEventMouseButton:
		return UnifiedSession.DEVICE_KEYBOARD
	return UnifiedSession.DEVICE_ANY


func _on_local_player_refused(local: int, _reason: String) -> void:
	if local == _joiner:
		_session.set_local_device(0, UnifiedSession.DEVICE_ANY)
		_joiner = -1


func _on_local_players_changed() -> void:
	if _joiner >= 0 and _session.get_local_player_key(_joiner) != 0:
		_joiner = -1
