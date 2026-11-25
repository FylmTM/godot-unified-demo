class_name Couch
extends Node
## Who plays on which device, for couch co-op. Alone, the first player plays with every device: a solo player picks up
## the pad or the keyboard whenever, and the prompts follow the one used last (Prompts). A pad nobody plays joins as
## another local player when it presses Start; the pad the first player used last is theirs, so its Start pauses.
## While a couch guest is in, the first player is fixed to the device it used last (the keyboard and mouse, or that
## pad), so a guest's pad moves only the guest; once the last guest has left, or the session refused the join, the
## first player has every device again.

## The session whose local players this assigns devices to: the app's.
@onready var _session: UnifiedSession = Unified.session


func _ready() -> void:
	_session.local_player_refused.connect(func(_local: int, _reason: String) -> void: _place_first.call_deferred())
	_session.local_players_changed.connect(_place_first)


## An unclaimed pad's Start joins it; the event is handled whether the session takes it or not.
func _unhandled_input(event: InputEvent) -> void:
	if not _session.game_input or not event.is_action_pressed(&"join") or is_claimed(event.device):
		return
	get_viewport().set_input_as_handled()
	var profile := UnifiedProfile.new()
	profile.class = EnumClass.ANY  # the first class no hero plays (the sim resolves it on arrival)
	_fix_first()  # at once: until the session has the guest in, its pad must not move the first player
	if _session.add_local_player(event.device, "Pad %d" % (event.device + 1), profile) < 0:
		_place_first()


## Whether a local player plays on the pad `device`.
func is_claimed(device: int) -> bool:
	return Couch.claimed(_session, device)


## Whether a local player of `session` plays on the pad `device`: its own pad, or, for the first player alone, the
## pad it used last (the HUD's join hint asks too).
static func claimed(session: UnifiedSession, device: int) -> bool:
	for local: int in session.get_local_indices():
		if session.get_local_device(local) == device:
			return true
	var first_alone: bool = session.get_local_device(0) == UnifiedSession.DEVICE_ANY
	return first_alone and Prompts.last_kind == Bindings.Kind.PAD and Prompts.last_pad == device


## Fixes the first player to the device it used last (a guest is coming in).
func _fix_first() -> void:
	if _session.get_local_device(0) == UnifiedSession.DEVICE_ANY:
		var last: int = (UnifiedSession.DEVICE_KEYBOARD if Prompts.last_kind == Bindings.Kind.KEYBOARD
			else Prompts.last_pad)
		_session.set_local_device(0, last)


## The first player's device for who plays now: fixed while a guest is in, every device alone.
func _place_first() -> void:
	if _session.get_local_indices().size() > 1:
		_fix_first()
	elif _session.get_local_device(0) != UnifiedSession.DEVICE_ANY:
		_session.set_local_device(0, UnifiedSession.DEVICE_ANY)
