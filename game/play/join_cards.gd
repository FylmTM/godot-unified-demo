class_name JoinCards
extends HBoxContainer
## The HUD's cards for pads mid-game: one for a pad that pressed Start to join (it picks its hero there, as on hero
## select, then joins with accept, or gives up with back) and one for a guest that pressed Back to drop out (accept
## drops out, back stays). The game runs on underneath, and the cards take nothing while an overlay holds the game's
## input.
##
## A join card answers to its own pad and takes all of it, in _input, before the Couch and the session see it: that
## pad plays nobody yet, so its picking moves nobody. A drop card takes only its pad's accept and back presses: its
## guest still plays, and the session must see its stick come back to rest. Only accept confirms a drop (a Start
## there would be a join's habit). A card closes by itself when its pad disconnects (a join given up) or its guest is
## gone. The cards scale down together when the view is too small for them, so they always fit.

## Pad `device` picked `hero_class` and joins.
signal join_chosen(device: int, hero_class: int)
## Pad `device` gave up joining.
signal join_given_up(device: int)
## Guest `local` confirmed it drops out.
signal drop_chosen(local: int)

## The room the cards keep from the view's top and bottom, and the share of the view's width they may take.
const EDGE_MARGIN: float = 40.0
const WIDTH_SHARE: float = 0.5

## A card (game/ui/widgets/seat_card.tscn).
@export var card_scene: PackedScene

## Each open card, by its pad.
var _cards: Dictionary[int, SeatCard] = {}
## The guest each drop-out card is for, by its pad: its local index (x) and its player's key (y).
var _dropping: Dictionary[int, Vector2i] = {}
var _sticks := StickSteps.new()

@onready var _session: UnifiedSession = Unified.session


func _ready() -> void:
	_session.local_players_changed.connect(_close_stale)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	resized.connect(_fit)
	get_parent_control().resized.connect(_fit)


func _input(event: InputEvent) -> void:
	if not _session.game_input:
		return  # an overlay holds the game's input
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion) or not _cards.has(event.device):
		return
	var device: int = event.device
	var card: SeatCard = _cards[device]
	var accept: bool = event.is_action_pressed(&"ui_accept")
	var back: bool = event.is_action_pressed(&"ui_cancel")
	if _dropping.has(device):
		if not (accept or back):
			return  # the guest plays on: the session sees the rest
		get_viewport().set_input_as_handled()
		var local: int = _dropping[device].x
		_close(device)
		if accept:
			drop_chosen.emit(local)
		return
	get_viewport().set_input_as_handled()
	var by: int = _sticks.step_of(event)
	if by != 0:
		Sfx.play(&"select")
		card.step(by)
	elif accept or event.is_action_pressed(&"join"):
		_close(device)
		join_chosen.emit(device, card.pick)
	elif back:
		_close(device)
		join_given_up.emit(device)


## Opens a join card for pad `device`, preselecting `hero_class`.
func open_join(device: int, hero_class: int) -> void:
	var card: SeatCard = _open(device)
	card.accept_text = "Join"
	card.show_seat(device, "Guest", hero_class)


## Opens a drop-out card for guest `local` (its player's key `player`) on pad `device`.
func open_drop(local: int, player: int, device: int, player_name: String, hero_class: int) -> void:
	_open(device).show_dropping(device, player_name, hero_class)
	_dropping[device] = Vector2i(local, player)


## The card of pad `device` (null: none open): the walk reads it.
func card_of(device: int) -> SeatCard:
	return _cards.get(device)


func _open(device: int) -> SeatCard:
	_close(device)
	var card: SeatCard = card_scene.instantiate()
	card.on_hud = true
	add_child(card)
	_cards[device] = card
	return card


func _close(device: int) -> void:
	if _cards.has(device):
		_cards[device].queue_free()
		_cards.erase(device)
	_dropping.erase(device)


## A drop card whose guest is gone already (it left another way) closes.
func _close_stale() -> void:
	for device: int in _dropping.keys():
		var local: int = _dropping[device].x
		if _session.get_local_player_key(local) != _dropping[device].y:
			_close(device)


## A pad gone takes its card with it: a join card's pad gives up.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected or not _cards.has(device):
		return
	var joining: bool = not _dropping.has(device)
	_close(device)
	if joining:
		join_given_up.emit(device)


## Scales the cards down together when the view is too short, or too narrow, for them (pivot: their right middle).
func _fit() -> void:
	var view: Vector2 = get_parent_control().size
	var natural: Vector2 = get_combined_minimum_size()
	if natural.x <= 0.0 or natural.y <= 0.0:
		return
	var fit: float = minf(1.0, minf((view.y - 2.0 * EDGE_MARGIN) / natural.y, view.x * WIDTH_SHARE / natural.x))
	pivot_offset = Vector2(size.x, size.y / 2.0)
	scale = Vector2(fit, fit)
