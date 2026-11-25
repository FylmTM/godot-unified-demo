class_name PauseScreen
extends MenuScreen
## The pause menu's first screen: Resume, Pause for everyone (online only), Invite friends (alone or hosting), Players,
## Settings, Leave and Quit, under a heading that says what pausing means here. Alone (couch included) the game is
## paused while it shows; online it runs on under it ("Back to the game" leaves the menu), and Pause for everyone (the
## co-op pause, a command: every peer pauses on one tick) is its own button, reading Resume for everyone, and taking the
## focus, while anyone has paused. Over a replay it offers Resume and Leave only. Its back (Esc, a pad's B) and the
## pause press (Esc, Start) resume, as Resume does, from the keyboard or a pad that plays: a pad nobody plays (one about
## to join) leaves it open. The screen only asks: PauseMenu does each thing.

## The player asked to resume (close the menu).
signal resume_requested
## The player asked to pause, or resume, the game for everyone (`paused`: what it asks for).
signal pause_all_requested(paused: bool)
## The player asked to invite friends, for the players' list, the settings, to leave the game, or to quit the app.
signal friends_requested
signal players_requested
signal settings_requested
signal leave_requested
signal quit_requested

## Whether pad `device` plays someone (Couch.claimed): only a playing pad's back or pause resumes.
var plays: Callable = func(_device: int) -> bool: return true

## This game runs on under the menu (someone else plays in it, or could), or is a replay; others are in it.
var _online: bool = false
var _replay: bool = false
var _others: bool = false

@onready var _heading: Label = %Heading
@onready var _status: Label = %Status
@onready var _resume: Button = %Resume
@onready var _pause_all: Button = %PauseAll
@onready var _friends: Button = %Friends
@onready var _players: Button = %Players
@onready var _settings: Button = %Settings
@onready var _leave: Button = %Leave
@onready var _quit: Button = %Quit


func _ready() -> void:
	super()
	_resume.pressed.connect(resume_requested.emit)
	_pause_all.pressed.connect(func() -> void: pause_all_requested.emit(not Unified.data.hud.paused))
	_friends.pressed.connect(friends_requested.emit)
	_players.pressed.connect(players_requested.emit)
	_settings.pressed.connect(settings_requested.emit)
	_leave.pressed.connect(leave_requested.emit)
	_quit.pressed.connect(quit_requested.emit)
	Unified.data.hud.changed.connect(_show_pause)


func _unhandled_input(event: InputEvent) -> void:
	if not has_focus_within() or not (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		return
	var pad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
	if pad and not plays.call(event.device):
		return
	get_viewport().set_input_as_handled()
	resume_requested.emit()


## Shows the menu for a replay, or for a game played alone (`online` false: it is paused) or with others (it runs on),
## whose Leave reads `leave_text` ("Leave to title", "End the game", "Leave the game", "Leave the replay"), with Invite
## friends when this machine may (`can_invite`: alone, or hosting), and `others` present (who could resume).
func show_mode(replay: bool, online: bool, leave_text: String, can_invite: bool, others: bool) -> void:
	var first: bool = _online != online or _replay != replay
	_replay = replay
	_online = online and not replay
	_others = others
	_pause_all.visible = _online
	for button: Button in [_players, _settings, _quit]:
		button.visible = not replay
	_friends.visible = can_invite and not replay
	_leave.text = leave_text
	_show_pause()
	if first and _online and Unified.data.hud.paused:
		_pause_all.grab_focus()


## Gives Resume for everyone the focus while the game is paused for everyone (back from inviting friends).
func focus_resume_all() -> void:
	if _online and Unified.data.hud.paused:
		_pause_all.grab_focus()


func _show_pause() -> void:
	var paused: bool = Unified.data.hud.paused
	var pauser: String = Unified.session.get_player_name(Unified.data.hud.paused_by)
	_pause_all.text = "Resume for everyone" if paused else "Pause for everyone"
	_resume.text = "Back to the game" if _online and not paused else "Resume"
	if _replay:
		_heading.text = "Replay paused"
		_status.text = ""
	elif not _online:
		_heading.text = "Paused"
		_status.text = ""
	elif paused:
		_heading.text = "Paused by %s" % pauser if pauser != "" else "Paused"
		_status.text = "Anyone can resume the game for everyone." if _others else "Resume when you're ready."
	else:
		_heading.text = "The game runs on"
		_status.text = "The others play on while this menu is open."
	_status.visible = _status.text != ""
