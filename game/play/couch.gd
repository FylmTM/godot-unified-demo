class_name Couch
extends Node
## Who plays on which device, for couch co-op. It seats hero select's party when the crypt is up (each guest on its
## device, with its pick). Alone, the first player plays with every device: a solo player picks up the pad or the
## keyboard whenever. A pad nobody plays asks to join when it presses Start (`join_requested`: the HUD shows it a card
## to pick its hero on, and join() brings it in); the device the first player last played with (moved, aimed,
## attacked or grabbed with: the menus and a mouse's nudge don't count) is theirs, so its Start pauses instead. A
## guest's Back asks to drop out (`drop_requested`; drop() lets it go). While a guest is in, or a pad is picking its
## hero, the first player is fixed to that device, so another pad moves only its own player; once the last guest has
## left, or a join was refused or given up, the first player has every device again. Once the players and the pads
## picking reach UnifiedSession.LOCAL_MAX the couch is full: no hint, and a Start gets a toast instead of a card.
##
## The join is read in _input, which reaches the scene before the autoloads: what the first player last played with is
## decided from before the press, never from the Start being pressed (Prompts, an autoload, sees it after).

## The first connected pad nobody plays changed (-1: none): the HUD's join hint speaks to it.
signal idle_pad_changed(device: int)
## Pad `device` nobody plays pressed Start: it wants to pick a hero and join.
signal join_requested(device: int)
## Local player `local` (a guest) pressed Back: it wants to drop out.
signal drop_requested(local: int)

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
## The pads picking their hero on a join card.
var _picking: Array[int] = []

## The session whose local players this assigns devices to: the app's.
@onready var _session: UnifiedSession = Unified.session


func _ready() -> void:
	var party: Party = Game.take_party()
	if party != null:
		first_device = party.seats[0].device
	else:
		first_device = (UnifiedSession.DEVICE_KEYBOARD if Prompts.last_kind == Bindings.Kind.KEYBOARD
			else Prompts.last_pad)
	_session.local_player_refused.connect(func(_local: int, _reason: String) -> void: _place_first.call_deferred())
	_session.local_players_changed.connect(_place_first)
	Input.joy_connection_changed.connect(_announce_idle_pad.unbind(2))
	if party != null and party.seats.size() > 1:
		_fix_first()
		for seat: Party.Seat in party.seats.slice(1):
			var local: int = _session.add_local_player(seat.device, seat.player_name, Heroes.profile(seat.hero_class))
			if local > 0:
				Game.party_seated(local)
	_place_first()


func _input(event: InputEvent) -> void:
	if not _session.game_input:
		return  # an overlay holds the game's input: its keys aren't the game's
	if event.is_action_pressed(&"join") and not claimed(event.device):
		get_viewport().set_input_as_handled()
		if event.device in _picking:
			return
		if _room() <= 0:
			Game.toast("The couch is full")
			return
		_picking.append(event.device)
		_fix_first()  # at once: while it picks, its pad must not move the first player
		join_requested.emit(event.device)
		return
	if event.is_action_pressed(&"drop_out"):
		var guest: int = _guest_of(event.device)
		if guest > 0:
			get_viewport().set_input_as_handled()
			drop_requested.emit(guest)
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
	for local: int in _session.local_indices:
		if _session.get_local_device(local) == device:
			return true
	return _session.get_local_device(0) == UnifiedSession.DEVICE_ANY and first_device == device


## The first connected pad nobody plays and that isn't picking its hero (-1: none, or the couch is full).
func idle_pad() -> int:
	if _room() <= 0:
		return -1
	for device: int in Input.get_connected_joypads():
		if not claimed(device) and device not in _picking:
			return device
	return -1


## The party place (local index) the next guest takes: the lowest free one.
func next_place() -> int:
	return Party.free_place(_session.local_indices)


## Brings pad `device` in as a guest playing `hero_class` (its join card's pick), named by the place it takes.
func join(device: int, hero_class: int) -> void:
	_picking.erase(device)
	if _session.add_local_player(device, Party.name_of(next_place()), Heroes.profile(hero_class)) < 0:
		_place_first()


## Pad `device` gave up joining (its card closed).
func give_up(device: int) -> void:
	_picking.erase(device)
	_place_first()


## Guest `local` drops out: its player leaves the session, the others play on.
func drop(local: int) -> void:
	_session.remove_local_player(local)
	_place_first()


## How many more players the couch takes: LOCAL_MAX less the players and the pads picking their hero.
func _room() -> int:
	return UnifiedSession.LOCAL_MAX - _session.local_indices.size() - _picking.size()


## The guest playing on pad `device` (0: none).
func _guest_of(device: int) -> int:
	for local: int in _session.local_indices:
		if local > 0 and _session.get_local_device(local) == device:
			return local
	return 0


## Fixes the first player to the device it last played with (a guest is coming in).
func _fix_first() -> void:
	if _session.get_local_device(0) == UnifiedSession.DEVICE_ANY:
		_session.set_local_device(0, first_device)
	_announce_idle_pad()


## The first player's device for who plays now: fixed while a guest is in, every device alone.
func _place_first() -> void:
	if _session.local_indices.size() > 1 or not _picking.is_empty():
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
