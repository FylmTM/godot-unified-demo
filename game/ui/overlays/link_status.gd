class_name LinkStatus
extends PanelContainer
## A small plate over the play scene while the session's link is in trouble: catching up with the others
## (recovering, shown only if it lasts past SHOW_AFTER_S, so a blip says nothing) or reconnecting after the link to the
## host was lost, the game held meanwhile with the player's place kept. It keeps to the HUD's lane between its plates
## (keep_in), its text wrapping to stay no wider.
##
## It never takes the player's input: the game's input stays on, and nothing here has the focus when it appears, so
## Space, Esc and a pad's A and B go on meaning what they mean in play. Reconnecting offers "Leave game", reached on
## purpose: a click, or an up or down press while nothing has the focus, which only then puts it on the button.

## The player chose to leave the game rather than wait.
signal leave_pressed

## How long the session must be catching up before the plate says so, in seconds.
const SHOW_AFTER_S: float = 0.5## The narrowest its text wraps to (canvas units).
const TEXT_MIN: float = 200.0

## The HUD's lane it keeps to (null: none yet, centred on the view).
var _lane: Lane = null

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


## Keeps the plate in `lane` (the HUD's, between its plates): centred in it, its text wrapping to stay no wider.
func keep_in(lane: Lane) -> void:
	_lane = lane
	_fit()


## Its text on one line when the lane has room for it, else wrapped to the lane's width; centred in the lane.
func _fit() -> void:
	if _lane == null:
		return
	var others: float = get_theme_stylebox(&"panel").get_minimum_size().x
	if _leave.visible:
		others += _leave.get_combined_minimum_size().x + ($Rows as Container).get_theme_constant(&"separation")
	var room: float = _lane.width() - others
	var font: Font = _text.get_theme_font(&"font")
	var natural: float = font.get_string_size(_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		_text.get_theme_font_size(&"font_size")).x
	var wraps: bool = natural > room
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wraps else TextServer.AUTOWRAP_OFF
	_text.custom_minimum_size.x = maxf(room, TEXT_MIN) if wraps else 0.0
	_lane.centre(self)


## The session is catching up with the others: says so once it has lasted SHOW_AFTER_S.
func show_recovering() -> void:
	_text.text = "Catching up with the others..."
	_leave.hide()
	_fit()
	if not visible and _delay.is_stopped():
		_delay.start()


## The link to the host was lost: says so at once, with Leave game (not focused).
func show_reconnecting() -> void:
	_delay.stop()
	_text.text = "Reconnecting: your place in the game is kept"
	_leave.show()
	_fit()
	show()


## The link is fine again (or the session ended).
func close() -> void:
	_delay.stop()
	if _leave.has_focus():
		_leave.release_focus()
	hide()
