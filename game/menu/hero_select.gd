class_name HeroSelect
extends MenuScreen
## Hero select, the screen every new game passes through: four seats along the bottom, the crew on the backdrop
## behind them. The device that came here has the first seat; a pad takes the next free one with its Start or A. The
## keyboard and mouse sit only in the first seat (they are the first player's, as in the crypt, where no keyboard
## guest could drop out or come back), so an unseated keyboard's Esc goes back to the title, as the mouse's Back does.
## In a seat, left and right step the pick through Any and the four classes (two seats may pick the same class; a
## stick steps once per push), accept readies it, back takes the ready back, and back again gives the seat up (the
## first seat's goes back to the title). Once every taken seat is ready, the first seat's accept starts the game (or a
## click on Start). A pad that disconnects gives its seat up; the first seat passes to the next taken seat, or the
## screen goes back to the title when nobody else sits.
##
## Each seat answers to its own device: this routes every key and pad press, in _input, to the seat of the device it
## came from (Godot's one focus can't serve four players at once), and plays their sounds (the mouse's clicks sound as
## every button does). The mouse works the keyboard's seat through its card's arrows and action line. Each taken seat
## is a place in the party (Party): its name and its preselected pick (Settings.hero_picks) are that place's. The
## seats scale down together when the view is too small for them (a large interface size), so they always fit.

## The game asks to start with `party` (the menu starts it).
signal start_requested(party: Party)
## The seated picks changed (EnumClass, one per taken seat, in seat order): the backdrop shows them.
signal picks_changed(picks: Array[int])

## The room kept around the seats: at the view's sides, and above them for the banner.
const SIDE_MARGIN: float = 32.0
const TOP_ROOM: float = 150.0

## Each seat's device (DEVICE_ANY: the seat is free).
var _devices: Array[int] = [UnifiedSession.DEVICE_ANY, UnifiedSession.DEVICE_ANY, UnifiedSession.DEVICE_ANY,
	UnifiedSession.DEVICE_ANY]
var _sticks := StickSteps.new()

## Every seat's card, first seat first.
@onready var _cards: Array[SeatCard] = [%Seat1 as SeatCard, %Seat2 as SeatCard, %Seat3 as SeatCard,
	%Seat4 as SeatCard]
@onready var _seats: Control = %Seats
@onready var _start: Button = %Start
@onready var _back: Button = %Back
@onready var _heading: Label = %Heading


func _ready() -> void:
	first_focus = _start
	super()
	for seat: int in _cards.size():
		_cards[seat].step_requested.connect(func(by: int) -> void: _mouse(seat, _step.bind(seat, by)))
		_cards[seat].act_requested.connect(func() -> void: _mouse(seat, _toggle_ready.bind(seat)))
	_start.pressed.connect(_try_start)
	_back.pressed.connect(back_requested.emit)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	resized.connect(_fit)
	_seats.resized.connect(_fit)
	_sit(0, UnifiedSession.DEVICE_KEYBOARD if Prompts.last_kind == Bindings.Kind.KEYBOARD else Prompts.last_pad)
	_fit()


func _input(event: InputEvent) -> void:
	if not has_focus_within():
		return  # covered, or a modal is over it
	var device: int = _device_of(event)
	if device == UnifiedSession.DEVICE_ANY:
		return
	if event.is_pressed() or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()  # every device's presses are its seat's, never the focus's
	var by: int = _sticks.step_of(event)
	var accept: bool = event.is_action_pressed(&"join") or event.is_action_pressed(&"ui_accept")
	var back: bool = event.is_action_pressed(&"ui_cancel")
	var seat: int = _devices.find(device)
	if seat < 0:
		if accept and device != UnifiedSession.DEVICE_KEYBOARD and _devices.has(UnifiedSession.DEVICE_ANY):
			Sfx.play(&"joined")
			_sit(_devices.find(UnifiedSession.DEVICE_ANY), device)
		elif back and device == UnifiedSession.DEVICE_KEYBOARD:
			back_requested.emit()
		return
	if by != 0:
		if _step(seat, by):
			Sfx.play(&"select")
	elif accept:
		if _cards[seat].state == SeatCard.State.CHOOSING:
			Sfx.play(&"press")
			_toggle_ready(seat)
		elif seat == 0 and _all_ready():
			_start.pressed.emit()  # as a click: its sound, and the start
	elif back:
		if _cards[seat].state == SeatCard.State.READY:
			Sfx.play(&"press")
			_toggle_ready(seat)
		elif seat == 0:
			back_requested.emit()
		else:
			Sfx.play(&"left")
			_stand(seat)


## Shows `text` on the banner ("Continue your crypt").
func set_heading(text: String) -> void:
	_heading.text = text


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


## Seats `device` in `seat`, preselecting the pick its place had last time.
func _sit(seat: int, device: int) -> void:
	_devices[seat] = device
	var place: int = _place_of(seat)
	var pick: int = Settings.hero_picks[place]
	_cards[seat].show_seat(device, Party.name_of(place), pick)
	_changed()


func _stand(seat: int) -> void:
	_devices[seat] = UnifiedSession.DEVICE_ANY
	_changed()


## Steps a choosing seat's pick (whether it did: a ready seat's pick stands).
func _step(seat: int, by: int) -> bool:
	if _cards[seat].state != SeatCard.State.CHOOSING:
		return false
	_cards[seat].step(by)
	_changed()
	return true


func _toggle_ready(seat: int) -> void:
	_cards[seat].set_ready(_cards[seat].state == SeatCard.State.CHOOSING)
	_changed()


## The mouse works only the keyboard's seat.
func _mouse(seat: int, act: Callable) -> void:
	if _devices[seat] == UnifiedSession.DEVICE_KEYBOARD:
		act.call()


## A seat changed: every taken seat's name by its place, the free seats' invitation, the backdrop and Start.
func _changed() -> void:
	var idle: int = _idle_pad()
	for seat: int in _cards.size():
		if _devices[seat] == UnifiedSession.DEVICE_ANY:
			_cards[seat].show_empty(idle)
		else:
			_cards[seat].show_name(Party.name_of(_place_of(seat)))
	picks_changed.emit(picks())
	_start.disabled = not _all_ready()
	set_prompts({&"ui_left ui_right": "Hero", &"ui_accept": "Start" if _all_ready() else "Ready",
		&"ui_cancel": "Back"})


## A seat's place in the party: how many taken seats are before it.
func _place_of(seat: int) -> int:
	var place: int = 0
	for before: int in seat:
		if _devices[before] != UnifiedSession.DEVICE_ANY:
			place += 1
	return place


## The first connected pad without a seat (-1: none): the free seats' Start speaks to it.
func _idle_pad() -> int:
	for device: int in Input.get_connected_joypads():
		if device not in _devices:
			return device
	return -1


func _all_ready() -> bool:
	for seat: int in _cards.size():
		if _devices[seat] != UnifiedSession.DEVICE_ANY and _cards[seat].state != SeatCard.State.READY:
			return false
	return true


func _try_start() -> void:
	if not _all_ready():
		return
	var party := Party.new()
	var picks: Array = Settings.hero_picks.duplicate()
	for seat: int in _cards.size():
		if _devices[seat] != UnifiedSession.DEVICE_ANY:
			var place: int = party.seats.size()
			party.seats.append(Party.Seat.new(_devices[seat], _cards[seat].pick, Party.name_of(place)))
			picks[place] = _cards[seat].pick
	Settings.hero_picks = picks
	start_requested.emit(party)


## A pad gone: its seat is given up; the first seat passes to the next taken seat (its pick and its ready kept), or
## the screen goes back to the title when nobody else sits. A pad come, or one without a seat gone, changes only the
## free seats' invitation.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	var seat: int = _devices.find(device)
	if connected or seat < 0:
		_changed()
		return
	if seat > 0:
		_stand(seat)
		return
	var next: int = -1
	for other: int in range(1, _cards.size()):
		if next < 0 and _devices[other] != UnifiedSession.DEVICE_ANY:
			next = other
	if next < 0:
		back_requested.emit()
		return
	var moving: SeatCard = _cards[next]
	_devices[0] = _devices[next]
	_cards[0].show_seat(_devices[0], Party.name_of(0), moving.pick)
	_cards[0].set_ready(moving.state == SeatCard.State.READY)
	_stand(next)


## Scales the seats down together when the view is too narrow or too short for them (pivot: their bottom middle).
func _fit() -> void:
	var natural: Vector2 = _seats.get_combined_minimum_size()
	var room := Vector2(size.x - 2.0 * SIDE_MARGIN, size.y + _seats.offset_bottom - TOP_ROOM)
	var fit: float = minf(1.0, minf(room.x / natural.x, room.y / natural.y))
	_seats.pivot_offset = Vector2(_seats.size.x / 2.0, _seats.size.y)
	_seats.scale = Vector2(fit, fit)


## The device an event comes from: a pad's id, the keyboard for a key (DEVICE_ANY for the mouse and anything else).
static func _device_of(event: InputEvent) -> int:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return event.device
	if event is InputEventKey:
		return UnifiedSession.DEVICE_KEYBOARD
	return UnifiedSession.DEVICE_ANY
