class_name SeatCard
extends PanelContainer
## One seat's card: who sits there (their device and name) and the hero they pick, stepped through Any and the four
## classes, its portrait and a line of what it does; then ready. Hero select shows four, one per seat; in play the HUD
## shows one for a pad that asks to join (or for a guest that asks to drop out). The card only shows: whoever holds
## it routes its device's presses (Godot's one focus can't serve four players at once), and the mouse's arrows and
## Ready are for the keyboard's seat (`mouse_only`: they never take the pad's focus).

## The mouse asked to step the pick (by -1 or +1), or to ready the seat.
signal step_requested(by: int)
signal ready_requested

enum State { EMPTY, CHOOSING, READY, DROPPING }

## What the card shows now.
var state: State = State.EMPTY
## The pick (EnumClass, Any included).
var pick: int = 0
## What accept does while choosing: "Ready" on hero select, "Join" on a join card.
var accept_text: String = "Ready"

@onready var _who: Label = %Who
@onready var _portrait: TextureRect = %Portrait
@onready var _anyone: Label = %Anyone
@onready var _hero: Label = %Hero
@onready var _line: Label = %Line
@onready var _status: ActionPrompt = %Status
@onready var _arrows: Array[Button] = [%Previous as Button, %Next as Button]
@onready var _ready_button: Button = %Ready
@onready var _body: Control = %Body
@onready var _ready_mark: Label = %ReadyMark


func _ready() -> void:
	_arrows[0].pressed.connect(step_requested.emit.bind(-1))
	_arrows[1].pressed.connect(step_requested.emit.bind(1))
	_ready_button.pressed.connect(ready_requested.emit)
	show_empty([&"ui_accept"], -1)


## An empty seat, inviting a device to sit with `actions` ("[Start] Join"; the glyphs of pad `device`, or of the device
## used last for -1).
func show_empty(actions: Array[StringName], device: int) -> void:
	state = State.EMPTY
	theme_type_variation = &"CardEmpty"
	_body.hide()
	_ready_mark.hide()
	for control: Button in _arrows + [_ready_button]:
		control.hide()
	_who.text = "A free seat"
	_status.actions = actions
	_status.pad_device = device
	_status.text = "Join"
	_status.refresh()


## A seat taken by `device` (UnifiedSession.DEVICE_KEYBOARD or a pad's id), named `player_name`, picking `hero_class`;
## the mouse's controls show only for the keyboard.
func show_seat(device: int, player_name: String, hero_class: int) -> void:
	state = State.CHOOSING
	var with: String = "Keyboard" if device == UnifiedSession.DEVICE_KEYBOARD else "Pad %d" % (device + 1)
	_who.text = "%s · %s" % [player_name, with]
	for control: Button in _arrows + [_ready_button]:
		control.visible = device == UnifiedSession.DEVICE_KEYBOARD
	_status.pad_device = device if device >= 0 else -1
	show_pick(hero_class)


## Shows pick `hero_class` (EnumClass).
func show_pick(hero_class: int) -> void:
	pick = hero_class
	_body.show()
	var portrait: Texture2D = Heroes.portrait(hero_class)
	_portrait.texture = portrait
	_anyone.visible = portrait == null
	_hero.text = Heroes.name_of(hero_class)
	_line.text = Heroes.line_of(hero_class)
	_show_state()


## Steps the pick by `by` through Heroes.choices(), wrapping.
func step(by: int) -> void:
	var choices: Array[int] = Heroes.choices()
	show_pick(choices[posmod(choices.find(pick) + by, choices.size())])


## Readies the seat, or takes it back to choosing.
func set_ready(is_ready: bool) -> void:
	state = State.READY if is_ready else State.CHOOSING
	_show_state()


## A guest asking to drop out: the card asks it to confirm.
func show_dropping(player_name: String, hero_class: int) -> void:
	show_pick(hero_class)
	state = State.DROPPING
	_who.text = player_name
	for control: Button in _arrows + [_ready_button]:
		control.hide()
	_show_state()


func _show_state() -> void:
	theme_type_variation = &"CardReady" if state == State.READY else &"Card"
	_ready_mark.visible = state == State.READY
	match state:
		State.CHOOSING:
			_status.actions = [&"ui_accept"]
			_status.text = accept_text
		State.READY:
			_status.actions = [&"ui_cancel"]
			_status.text = "Change"
		State.DROPPING:
			_status.actions = [&"ui_accept"]
			_status.text = "Drop out"
	_ready_button.text = accept_text if state == State.CHOOSING else "Change"
	_status.refresh()
