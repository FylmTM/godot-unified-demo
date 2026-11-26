class_name BoonPanel
extends VBoxContainer
## One local player's boon panel at the lift's bottom: three parchment cards, the boons its hero is offered (the HUD
## data's `offer`, the rules' boon_offer: the cards a pick's index names), each with its next rank and what it does,
## and the party's row. The player steps through the cards with left and right on its own device and takes one with
## Interact, which sends CommandPickBoon with the card's index for that local player.
##
## What it shows of a pick is certain: a card locks, and a name in the party's row ticks, only when the pick is
## CONFIRMED (Event_Boon_Picked on the verified timeline). A pick predicted on this machine (EMITTED) or taken back by a
## rollback (CANCELLED, which can't happen to an own pick but can to a remote one predicted wrong) changes nothing:
## the press shows only as the card pressed in (the request), so a pick the lift then didn't take (sent too late, the
## lift already gone) never showed as taken. on_pick is the whole rule, a function of the event's state and fields
## alone, with no session in it: the walk drives it with made-up EMITTED, CANCELLED and CONFIRMED picks
## (game/tools/ui_walk.gd), as a solo session confirms a pick in the frame it is emitted.

## What each boon is called and does, by EnumBoon (the rules' Boon, boons.odin; the numbers its tuning's).
const NAMES: Dictionary[int, String] = {
	EnumBoon.THICK_HIDE: "Thick Hide",
	EnumBoon.SWIFT_BOOTS: "Swift Boots",
	EnumBoon.KEEN_EDGE: "Keen Edge",
	EnumBoon.QUICK_HANDS: "Quick Hands",
	EnumBoon.STRONG_BACK: "Strong Back",
	EnumBoon.FIELD_MEDIC: "Field Medic",
}
const TEXTS: Dictionary[int, String] = {
	EnumBoon.THICK_HIDE: "20 more health",
	EnumBoon.SWIFT_BOOTS: "6% faster on your feet",
	EnumBoon.KEEN_EDGE: "15% more damage",
	EnumBoon.QUICK_HANDS: "Your ability is ready 12% sooner",
	EnumBoon.STRONG_BACK: "Carrying and hauling slow you less",
	EnumBoon.FIELD_MEDIC: "Revive allies 30% faster",
}
## How the cards look: the one the cursor is on, the others, the one taken (a green wash), and the rest once taken.
const CURSOR_TINT: Color = Color(1, 1, 1, 1)
const IDLE_TINT: Color = Color(0.72, 0.72, 0.72, 0.9)
const TAKEN_TINT: Color = Color(0.72, 1.0, 0.72, 1)
const PASSED_TINT: Color = Color(0.5, 0.5, 0.5, 0.6)

## The local player whose panel this is, and its player's key.
var local: int = 0
var player: int = 0

## The card the cursor is on (0 to the offer's count - 1).
var _cursor: int = 0
## The boons offered, as the cards show them.
var _offer: Array[int] = []
## The card pressed (-1: none): sent, waiting for its pick to be confirmed.
var _pressed: int = -1
## The confirmed picks: each player's key to the boon it took.
var _taken: Dictionary[int, int] = {}
## Each present player's key, in slot order, as the party's row lists them.
var _party: Array[int] = []
var _sticks := StickSteps.new()

@onready var _title: Label = %Title
@onready var _cards: HBoxContainer = %Cards
@onready var _row: Label = %Party
@onready var _prompts: HBoxContainer = %Prompts


## Opens the panel for local player `local_index`, showing the offer of its hero (`hero`, the HUD data's) and the
## party (`party`: every present player's key, in slot order).
func open(local_index: int, hero: DataHudHero, party: Array[int]) -> void:
	local = local_index
	player = hero.player
	_offer.clear()
	for i: int in hero.offer_count:
		_offer.append(hero.offer[i])
	_party = party
	_cursor = 0
	_pressed = -1
	_title.text = "%s: choose a boon" % Unified.session.get_player_name(player)
	for prompt: Node in _prompts.get_children():
		(prompt as ActionPrompt).local = local
		(prompt as ActionPrompt).refresh()
	for i: int in _cards.get_child_count():
		var card := _cards.get_child(i) as PanelContainer
		card.visible = i < _offer.size()
		if card.visible:
			var boon: int = _offer[i]
			(card.get_node(^"Rows/Name") as Label).text = NAMES.get(boon, "?")
			(card.get_node(^"Rows/Rank") as Label).text = "Rank %d" % (hero.boons[boon] + 1)
			(card.get_node(^"Rows/Text") as Label).text = TEXTS.get(boon, "")
	_show()


## A pick's event in `state` (UnifiedSession.EVENT_*): `picker` took `boon` (its key and an EnumBoon). On CONFIRMED
## alone the party's row ticks the picker, and the panel's own player's pick locks its card with a chime; EMITTED and
## CANCELLED change nothing.
func on_pick(state: UnifiedSession.EventState, picker: int, boon: int) -> void:
	if state != UnifiedSession.EVENT_CONFIRMED or _taken.has(picker):
		return
	_taken[picker] = boon
	if picker == player:
		Sfx.play(&"boon")
	_show()


## The party's row lists `party` (every present player's key, in slot order) from now: BoonPanels follows joins and
## leaves while the party chooses. A pick confirmed before a player left stays known, should it come back.
func set_party(party: Array[int]) -> void:
	if party == _party:
		return
	_party = party
	_show()


## Whether this panel's player's pick is confirmed (the HUD's banner asks).
func taken() -> bool:
	return _taken.has(player)


## The boon this panel's player took (-1: none confirmed yet): the walk reads it.
func taken_boon() -> int:
	return _taken.get(player, -1)


## The players of the party whose picks aren't confirmed yet, by key.
func waiting_for() -> Array[int]:
	return _party.filter(func(key: int) -> bool: return not _taken.has(key))


## Whether the party's row ticks `key` (the walk reads it).
func ticked(key: int) -> bool:
	return _taken.has(key)


func _input(event: InputEvent) -> void:
	if not visible or taken() or _offer.is_empty() or not _is_mine(event):
		return
	var by: int = _sticks.step_of(event)
	if by == 0 and event.is_action_pressed(&"move_left"):
		by = -1
	elif by == 0 and event.is_action_pressed(&"move_right"):
		by = 1
	if by != 0:
		_cursor = posmod(_cursor + by, _offer.size())
		Sfx.play(&"select")
		_show()
	elif event.is_action_pressed(&"interact") and not event.is_echo():
		_pressed = _cursor
		var pick := CommandPickBoon.new()
		pick.index = _cursor
		Unified.session.send_command(pick, local)
		Sfx.play(&"press")
		_show()


## Whether `event` comes from this panel's player's device: its pad's, the keyboard and mouse for the keyboard's
## player, any device for a player who plays with any.
func _is_mine(event: InputEvent) -> bool:
	var device: int = Unified.session.get_local_device(local)
	if device == UnifiedSession.DEVICE_ANY:
		return true
	var pad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
	if device == UnifiedSession.DEVICE_KEYBOARD:
		return not pad
	return pad and event.device == device


## The cards' tints (the cursor's, the pressed one held in, the taken one's wash) and the party's row.
func _show() -> void:
	var mine: int = _taken.get(player, -1)
	for i: int in _offer.size():
		var card := _cards.get_child(i) as PanelContainer
		if mine >= 0:
			card.modulate = TAKEN_TINT if _offer[i] == mine else PASSED_TINT
		else:
			card.modulate = CURSOR_TINT if i == _cursor else IDLE_TINT
		card.scale = Vector2.ONE * (0.96 if i == _pressed and mine < 0 else 1.0)
	var names: PackedStringArray = []
	for key: int in _party:
		names.append("%s: %s" % [Unified.session.get_player_name(key), "ready" if _taken.has(key) else "choosing"])
	_row.text = "    ".join(names)
