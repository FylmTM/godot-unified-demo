class_name HeroSelect
extends MenuScreen
## Hero select, the screen every new game passes through: four seats along the bottom, the crew on the backdrop
## behind them. The device that came here has the first seat; any other device takes the next free one with its
## join press (a pad's Start or A, Enter on the keyboard). In a seat, left and right step the pick through Any and the
## four classes (two seats may pick the same class), accept readies it, back takes the ready back, and back again
## gives the seat up (the first seat's goes back to the title). Once every taken seat is ready, the first seat's
## accept starts the game (or a click on Start).
##
## Each seat answers to its own device: this routes every key and pad press, in _input, to the seat of the device it
## came from (Godot's one focus can't serve four players at once). The mouse works the keyboard's seat through its
## card's buttons, which never take the focus. Each seat's last pick is kept (Settings.hero_picks) and preselected.

## The game asks to start with `party` (the menu starts it).
signal start_requested(party: Party)
## The seated picks changed (EnumClass, one per taken seat, in seat order): the backdrop shows them.
signal picks_changed(picks: Array[int])

## Each seat's device (DEVICE_ANY: the seat is free).
var _devices: Array[int] = [UnifiedSession.DEVICE_ANY, UnifiedSession.DEVICE_ANY, UnifiedSession.DEVICE_ANY,
	UnifiedSession.DEVICE_ANY]

## Every seat's card, first seat first.
@onready var _cards: Array[SeatCard] = [%Seat1 as SeatCard, %Seat2 as SeatCard, %Seat3 as SeatCard,
	%Seat4 as SeatCard]
@onready var _start: Button = %Start


func _ready() -> void:
	first_focus = _start
	super()
	for seat: int in _cards.size():
		_cards[seat].step_requested.connect(func(by: int) -> void: _mouse(seat, func() -> void: _step(seat, by)))
		_cards[seat].ready_requested.connect(func() -> void: _mouse(seat, func() -> void: _toggle_ready(seat)))
	_start.pressed.connect(_try_start)
	var first: int = (UnifiedSession.DEVICE_KEYBOARD if Prompts.last_kind == Bindings.Kind.KEYBOARD
		else Prompts.last_pad)
	_sit(0, first)
	for seat: int in range(1, _cards.size()):
		_cards[seat].show_empty([&"ui_accept"], -1)
	_show_start()


func _input(event: InputEvent) -> void:
	if not has_focus_within():
		return  # covered, or a modal is over it
	var device: int = _device_of(event)
	if device == UnifiedSession.DEVICE_ANY:
		return
	var left: bool = event.is_action_pressed(&"ui_left")
	var right: bool = event.is_action_pressed(&"ui_right")
	var accept: bool = event.is_action_pressed(&"join") or event.is_action_pressed(&"ui_accept")
	var back: bool = event.is_action_pressed(&"ui_cancel")
	var seat: int = _devices.find(device)
	if seat < 0:
		if accept and _devices.has(UnifiedSession.DEVICE_ANY):
			_sit(_devices.find(UnifiedSession.DEVICE_ANY), device)
		if event.is_pressed() or left or right:
			get_viewport().set_input_as_handled()  # a device without a seat moves nothing here
		return
	if not (left or right or accept or back):
		if event.is_pressed() or event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	if left or right:
		_step(seat, -1 if left else 1)
	elif accept:
		if _cards[seat].state == SeatCard.State.CHOOSING:
			_toggle_ready(seat)
		elif seat == 0:
			_try_start()
	elif _cards[seat].state == SeatCard.State.READY:
		_toggle_ready(seat)
	elif seat == 0:
		back_requested.emit()
	else:
		_stand(seat)


## The seat a device sits in (-1: none): the walk asks.
func seat_of(device: int) -> int:
	return _devices.find(device)


## The seated picks (EnumClass, one per taken seat, in seat order).
func picks() -> Array[int]:
	var out: Array[int] = []
	for seat: int in _cards.size():
		if _devices[seat] != UnifiedSession.DEVICE_ANY:
			out.append(_cards[seat].pick)
	return out


## Seat `seat`'s card.
func card(seat: int) -> SeatCard:
	return _cards[seat]


func _sit(seat: int, device: int) -> void:
	_devices[seat] = device
	var picks: Array = Settings.hero_picks
	var last: int = picks[seat] if seat < picks.size() and picks[seat] is int else EnumClass.ANY
	var pick: int = last if last in Heroes.choices() else EnumClass.ANY
	_cards[seat].show_seat(device, Settings.player_name if seat == 0 else "Guest", pick)
	_changed()


func _stand(seat: int) -> void:
	_devices[seat] = UnifiedSession.DEVICE_ANY
	_cards[seat].show_empty([&"ui_accept"], -1)
	_changed()


func _step(seat: int, by: int) -> void:
	if _cards[seat].state == SeatCard.State.CHOOSING:
		_cards[seat].step(by)
		_changed()


func _toggle_ready(seat: int) -> void:
	_cards[seat].set_ready(_cards[seat].state == SeatCard.State.CHOOSING)
	_changed()


## The mouse works only the keyboard's seat.
func _mouse(seat: int, act: Callable) -> void:
	if _devices[seat] == UnifiedSession.DEVICE_KEYBOARD:
		act.call()


func _changed() -> void:
	picks_changed.emit(picks())
	_show_start()


func _all_ready() -> bool:
	for seat: int in _cards.size():
		if _devices[seat] != UnifiedSession.DEVICE_ANY and _cards[seat].state != SeatCard.State.READY:
			return false
	return true


func _show_start() -> void:
	_start.disabled = not _all_ready()
	set_prompts({&"ui_left ui_right": "Hero", &"ui_accept": "Start" if _all_ready() else "Ready",
		&"ui_cancel": "Back"})


func _try_start() -> void:
	if not _all_ready():
		return
	var party := Party.new()
	var picks: Array = Settings.hero_picks.duplicate()
	for seat: int in _cards.size():
		if _devices[seat] != UnifiedSession.DEVICE_ANY:
			var player_name: String = _name_of(party.seats.size())
			party.seats.append(Party.Seat.new(_devices[seat], _cards[seat].pick, player_name))
			if seat < picks.size():
				picks[seat] = _cards[seat].pick
	Settings.hero_picks = picks
	start_requested.emit(party)


## The name of the party's `place`-th player (from 0): the player's own for the first, "Guest 2" and on for the
## others, in the order they sit.
func _name_of(place: int) -> String:
	return Settings.player_name if place == 0 else "Guest %d" % (place + 1)


## The device an event comes from: a pad's id, the keyboard for a key (DEVICE_ANY for the mouse and anything else).
static func _device_of(event: InputEvent) -> int:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return event.device
	if event is InputEventKey:
		return UnifiedSession.DEVICE_KEYBOARD
	return UnifiedSession.DEVICE_ANY
