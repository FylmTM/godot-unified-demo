class_name SeatCard
extends PanelContainer
## One seat's card: who sits there (their name, and their device on its own line) and the hero they pick, stepped
## through Any and the four classes, its portrait and a line of what it does; then ready. Hero select shows four, one
## per seat; in play the HUD shows one for a pad that asks to join (`on_hud`: it shows its own left, right and back,
## as no prompt bar is there), or for a guest that asks to drop out.
##
## The card only shows: whoever holds it routes its device's presses (Godot's one focus can't serve four players at
## once). Its glyphs are its device's, whatever was used last. Its size never changes with its state: the portrait's
## "Ready!" is drawn over it, a free seat keeps its layout with nothing in it, and the arrows hide in place. For the
## keyboard's seat the mouse works it too: the arrows step the pick, and the action line is a button (`act_requested`),
## "[Enter] Ready" one control; both are `mouse_only`, never taking the focus.

## The mouse asked to step the pick (by -1 or +1), or pressed the action line (ready, or change).
signal step_requested(by: int)
signal act_requested

enum State { EMPTY, CHOOSING, READY, DROPPING }

## What the card shows now.
var state: State = State.EMPTY
## The pick (EnumClass, Any included).
var pick: int = EnumClass.ANY
## The seat's device (UnifiedSession.DEVICE_KEYBOARD or a pad's id; DEVICE_ANY while free).
var device: int = UnifiedSession.DEVICE_ANY
## What accept does while choosing: "Ready" on hero select, "Join" on a join card.
var accept_text: String = "Ready"
## A card on the HUD: it shows its own hints (left and right, and back).
var on_hud: bool = false

@onready var _who: Label = %Who
@onready var _device: Label = %Device
@onready var _body: Control = %Body
@onready var _portrait: TextureRect = %Portrait
@onready var _anyone: Label = %Anyone
@onready var _ready_mark: Label = %ReadyMark
@onready var _hero: Label = %Hero
@onready var _line: Label = %Line
@onready var _arrows: Array[Button] = [%Previous as Button, %Next as Button]
@onready var _act: Button = %Act
@onready var _accept: ActionPrompt = %Accept
@onready var _more: Control = %More
@onready var _steps: ActionPrompt = %Steps
@onready var _back: ActionPrompt = %Back


func _ready() -> void:
	_arrows[0].pressed.connect(step_requested.emit.bind(-1))
	_arrows[1].pressed.connect(step_requested.emit.bind(1))
	_act.pressed.connect(act_requested.emit)
	show_empty(-1)


## A free seat: "[Start] Join" in the glyphs of `pad`, a connected pad nobody seated (-1: none, so it asks for one).
func show_empty(pad: int) -> void:
	state = State.EMPTY
	device = UnifiedSession.DEVICE_ANY
	theme_type_variation = &"CardEmpty"
	_who.text = "A free seat"
	_device.text = "" if pad >= 0 else "Connect a pad to join"
	_body.modulate = Color.TRANSPARENT
	_accept.visible = pad >= 0
	_accept.actions = [&"join"]
	_accept.device = pad
	_accept.text = "Join"
	_show_state()


## A seat taken by `device` (UnifiedSession.DEVICE_KEYBOARD or a pad's id), named `player_name`, picking `hero_class`.
func show_seat(seat_device: int, player_name: String, hero_class: int) -> void:
	state = State.CHOOSING
	device = seat_device
	_who.text = player_name
	_device.text = "Keyboard" if device == UnifiedSession.DEVICE_KEYBOARD else "Pad %d" % (device + 1)
	_body.modulate = Color.WHITE
	_accept.visible = true
	show_pick(hero_class)


## Names the seat's player `player_name` (its place in the party changed).
func show_name(player_name: String) -> void:
	_who.text = player_name


## Shows pick `hero_class` (EnumClass).
func show_pick(hero_class: int) -> void:
	pick = hero_class
	var portrait: Texture2D = Heroes.portrait(hero_class)
	_portrait.texture = portrait
	_anyone.visible = portrait == null
	_hero.text = Heroes.name_of(hero_class)
	_line.text = "Drop out?" if state == State.DROPPING else Heroes.line_of(hero_class)
	_show_state()


## Steps the pick by `by` through Heroes.choices(), wrapping.
func step(by: int) -> void:
	var choices: Array[int] = Heroes.choices()
	show_pick(choices[posmod(choices.find(pick) + by, choices.size())])


## Readies the seat, or takes it back to choosing.
func set_ready(is_ready: bool) -> void:
	state = State.READY if is_ready else State.CHOOSING
	_show_state()


## Guest `player_name` on `seat_device` asks to drop out, playing `hero_class`: the card asks it to confirm.
func show_dropping(seat_device: int, player_name: String, hero_class: int) -> void:
	show_seat(seat_device, player_name, hero_class)
	state = State.DROPPING
	show_pick(hero_class)


func _show_state() -> void:
	theme_type_variation = (&"CardEmpty" if state == State.EMPTY else &"CardReady" if state == State.READY
		else &"Card")
	_ready_mark.visible = state == State.READY
	for arrow: Button in _arrows:
		arrow.visible = state == State.CHOOSING and device == UnifiedSession.DEVICE_KEYBOARD
	var clickable: bool = device == UnifiedSession.DEVICE_KEYBOARD and state in [State.CHOOSING, State.READY]
	_act.flat = not clickable
	_act.mouse_filter = Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_IGNORE
	match state:
		State.CHOOSING:
			_accept.actions = [&"ui_accept"]
			_accept.text = accept_text
		State.READY:
			_accept.actions = [&"ui_cancel"]
			_accept.text = "Change"
		State.DROPPING:
			_accept.actions = [&"ui_accept"]
			_accept.text = "Drop out"
	if state != State.EMPTY:
		_accept.device = device
	_more.visible = on_hud
	_steps.visible = state == State.CHOOSING
	_back.text = "Stay" if state == State.DROPPING else "Back"
	for prompt: ActionPrompt in [_accept, _steps, _back]:
		prompt.device = _accept.device
		prompt.refresh()
