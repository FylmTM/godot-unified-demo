class_name LinkStatus
extends PanelContainer
## A small plate over the play scene while the session's link is in trouble: catching up with the others
## (recovering, shown only if it lasts past SHOW_AFTER_S, so a blip says nothing) or reconnecting after the link to the
## host was lost, the game held meanwhile with the player's place kept.
##
## It never takes the player's input: the game's input stays on, and nothing here has the focus when it appears, so
## Space, Esc and a pad's A and B go on meaning what they mean in play. Reconnecting offers "Leave game", reached on
## purpose: a click, or an up or down press while nothing has the focus, which only then puts it on the button.

## The player chose to leave the game rather than wait.
signal leave_pressed

## How long the session must be catching up before the plate says so, in seconds.
const SHOW_AFTER_S: float = 0.5

@onready var _text: Label = %Text
@onready var _leave: Button = %Leave
@onready var _delay: Timer = %Delay


func _ready() -> void:
	_leave.pressed.connect(leave_pressed.emit)
	_delay.wait_time = SHOW_AFTER_S
	_delay.timeout.connect(show)


func _unhandled_input(event: InputEvent) -> void:
	var asks: bool = event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"ui_down")
	if visible and _leave.visible and asks and get_viewport().gui_get_focus_owner() == null:
		get_viewport().set_input_as_handled()
		_leave.grab_focus()


## The session is catching up with the others: says so once it has lasted SHOW_AFTER_S.
func show_recovering() -> void:
	_text.text = "Catching up with the others..."
	_leave.hide()
	if not visible and _delay.is_stopped():
		_delay.start()


## The link to the host was lost: says so at once, with Leave game (not focused).
func show_reconnecting() -> void:
	_delay.stop()
	_text.text = "Reconnecting: your place in the game is kept"
	_leave.show()
	show()


## The link is fine again (or the session ended).
func close() -> void:
	_delay.stop()
	if _leave.has_focus():
		_leave.release_focus()
	hide()
