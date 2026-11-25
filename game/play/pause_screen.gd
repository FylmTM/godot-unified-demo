class_name PauseScreen
extends MenuScreen
## The pause menu's first screen: Resume, Pause for everyone (online only), Players, Settings, Leave and Quit, under a
## heading that says what pausing means here. Alone (couch included) the game is paused while it shows; online it runs
## on under it, and Pause for everyone (the co-op pause, a command: every peer pauses on one tick) is its own button,
## reading Resume for everyone while anyone has paused, whoever that was. Its back (Esc, a pad's B) and the pause press
## (Esc, Start) resume, as Resume does. The screen only asks: PauseMenu does each thing.

## The player asked to resume (close the menu).
signal resume_requested
## The player asked to pause, or resume, the game for everyone (`paused`: what it asks for).
signal pause_all_requested(paused: bool)
## The player asked for the players' list, the settings, to leave the game, or to quit the app.
signal players_requested
signal settings_requested
signal leave_requested
signal quit_requested

## This game runs on under the menu (someone else plays in it).
var _online: bool = false

@onready var _heading: Label = %Heading
@onready var _status: Label = %Status
@onready var _resume: Button = %Resume
@onready var _pause_all: Button = %PauseAll
@onready var _players: Button = %Players
@onready var _settings: Button = %Settings
@onready var _leave: Button = %Leave
@onready var _quit: Button = %Quit


func _ready() -> void:
	super()
	_resume.pressed.connect(resume_requested.emit)
	_pause_all.pressed.connect(func() -> void: pause_all_requested.emit(not Unified.data.hud.paused))
	_players.pressed.connect(players_requested.emit)
	_settings.pressed.connect(settings_requested.emit)
	_leave.pressed.connect(leave_requested.emit)
	_quit.pressed.connect(quit_requested.emit)
	Unified.data.hud.changed.connect(_show_pause)


func _unhandled_input(event: InputEvent) -> void:
	if has_focus_within() and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


## Shows the menu for a game played alone (`online` false: it is paused) or with others (it runs on), whose Leave
## reads `leave_text` ("Leave to title", "End the game", "Leave the game").
func show_mode(online: bool, leave_text: String) -> void:
	_online = online
	_pause_all.visible = online
	_leave.text = leave_text
	_show_pause()


func _show_pause() -> void:
	var paused: bool = Unified.data.hud.paused
	var pauser: String = Unified.session.get_player_name(Unified.data.hud.paused_by)
	_pause_all.text = "Resume for everyone" if paused else "Pause for everyone"
	if not _online:
		_heading.text = "Paused"
		_status.text = ""
	elif paused:
		_heading.text = "Paused by %s" % pauser if pauser != "" else "Paused"
		_status.text = "Anyone can resume the game for everyone."
	else:
		_heading.text = "The game runs on"
		_status.text = "The others play on while this menu is open."
	_status.visible = _status.text != ""
