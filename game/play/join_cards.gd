class_name JoinCards
extends HBoxContainer
## The HUD's cards for pads mid-game: one for a pad that pressed Start to join (it picks its hero there, as on hero
## select, then joins with accept, or gives up with back) and one for a guest that pressed Back to drop out (accept
## drops out, back stays). The game runs on underneath. Each card answers to its own pad only: its presses are taken
## here, in _input, before the Couch and the session see them, so a pad picking its hero moves nobody.

## Pad `device` picked `hero_class` and joins.
signal join_chosen(device: int, hero_class: int)
## Pad `device` gave up joining.
signal join_given_up(device: int)
## Guest `local` confirmed it drops out.
signal drop_chosen(local: int)

## A card (game/ui/widgets/seat_card.tscn).
@export var card_scene: PackedScene

## Each open card, by its pad.
var _cards: Dictionary[int, SeatCard] = {}
## The guest each drop-out card is for, by its pad.
var _dropping: Dictionary[int, int] = {}


func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion) or not _cards.has(event.device):
		return
	get_viewport().set_input_as_handled()
	var device: int = event.device
	var card: SeatCard = _cards[device]
	if event.is_action_pressed(&"ui_left") and card.state == SeatCard.State.CHOOSING:
		card.step(-1)
	elif event.is_action_pressed(&"ui_right") and card.state == SeatCard.State.CHOOSING:
		card.step(1)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"join"):
		_close(device)
		if _dropping.has(device):
			drop_chosen.emit(_dropping[device])
			_dropping.erase(device)
		else:
			join_chosen.emit(device, card.pick)
	elif event.is_action_pressed(&"ui_cancel"):
		_close(device)
		if not _dropping.erase(device):
			join_given_up.emit(device)


## Opens a join card for pad `device`, preselecting `hero_class`.
func open_join(device: int, hero_class: int) -> void:
	var card: SeatCard = _open(device)
	card.accept_text = "Join"
	card.show_seat(device, "Guest", hero_class)


## Opens a drop-out card for guest `local` on pad `device`.
func open_drop(local: int, device: int, player_name: String, hero_class: int) -> void:
	_dropping[device] = local
	_open(device).show_dropping(player_name, hero_class)


## The card of pad `device` (null: none open): the walk reads it.
func card_of(device: int) -> SeatCard:
	return _cards.get(device)


func _open(device: int) -> SeatCard:
	_close(device)
	var card: SeatCard = card_scene.instantiate()
	add_child(card)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the HUD takes no click
	_cards[device] = card
	return card


func _close(device: int) -> void:
	if _cards.has(device):
		_cards[device].queue_free()
		_cards.erase(device)
