class_name PauseMenu
extends Control
## The pause menu over play, its own screen stack (the pause screen, the Players list, the settings) and prompt bar.
## The play scene makes one when a player presses pause (Esc, a playing pad's Start), or when the window goes to the
## background in a single-player game, and it frees itself when it closes.
##
## What it pauses follows what the library allows: opening asks for the single-player pause (UnifiedSession.paused),
## and when it takes (alone, couch included) the clock stands while the menu shows; when it doesn't (others play in
## this game, or did and could again: the library refuses it then) the menu is an overlay over the running game, whose
## co-op pause is its Pause for everyone (the CommandSetPaused command: every peer pauses on one tick, the HUD's banner
## names who, and anyone resumes). Over a replay it holds the replay's playhead and offers Resume and Leave only.
## Either way the game's input is off while it shows, so its presses move nobody.
##
## Leaving asks first where something is lost or others are affected: alone or hosting, "Leave to the title?" says where
## the crypt is saved (the slot's save); a host with others in ends the game for everyone, and that question stays on
## Stay; a joiner and a replay leave at once. Quit asks the same.

## The menu closed (it frees itself).
signal closed

## The input block it holds while it shows (Game.block_input).
const BLOCK: StringName = &"pause_menu"
## How many frames the single-player pause may take to take before the menu counts the game as online.
const PAUSE_TAKES_FRAMES: int = 6

## Invite friends (game/play/friends_screen.tscn), the Players list (players_screen.tscn) and the settings
## (game/ui/settings/settings_screen.tscn).
@export var friends_scene: PackedScene
@export var players_scene: PackedScene
@export var settings_scene: PackedScene

## The couch, which drops a guest out and says which pads play (the play scene's).
var couch: Couch

## The single-player pause took (the game is alone): opened to friends while it is, the co-op pause keeps it paused.
var _alone: bool = false

@onready var _session: UnifiedSession = Unified.session
@onready var _stack: MenuStack = %Stack
@onready var _prompt_bar: PromptBar = %PromptBar
@onready var _screen: PauseScreen = %PauseScreen


func _ready() -> void:
	Game.block_input(BLOCK)
	_screen.plays = couch.claimed
	_screen.resume_requested.connect(close)
	_screen.pause_all_requested.connect(_pause_all)
	_screen.friends_requested.connect(func() -> void: _stack.push(friends_scene))
	_screen.players_requested.connect(_open_players)
	_screen.settings_requested.connect(func() -> void: _stack.push(settings_scene))
	_screen.leave_requested.connect(_leave.bind(false))
	_screen.quit_requested.connect(_leave.bind(true))
	_session.mode_changed.connect(_on_mode_changed)
	_stack.top_changed.connect(_prompt_bar.follow)
	_stack.top_changed.connect(func(screen: MenuScreen) -> void:
		if screen == _screen:
			_screen.focus_resume_all())  # back from inviting a game paused alone: Resume for everyone
	_prompt_bar.follow(_stack.top())
	_settle_pause()


## Leaving the tree (closed, or gone with the play scene when the game ends from it): the clock runs again (alone), the
## game's input is back.
func _exit_tree() -> void:
	_session.paused = false
	Game.unblock_input(BLOCK)


## Closes the menu: alone, a co-op pause it was opened under (a game opened to friends and closed again) is lifted too.
func close() -> void:
	if _session.mode == UnifiedSession.MODE_SINGLE and Unified.data.hud.paused:
		_pause_all(false)
	closed.emit()
	queue_free()


## The screen on top, for the walk.
func top() -> MenuScreen:
	return _stack.top()


## The game was opened to friends (or fell back to alone) under the menu: a game paused alone stays paused, now for
## everyone (the co-op pause, sent at once, on the mode change), so the host reads the code out with the clock still
## standing; back alone, the menu pauses the clock again (Game lifts the co-op pause).
func _on_mode_changed(mode: UnifiedSession.Mode, _detail: String) -> void:
	if not is_inside_tree():
		return  # closing (the session's signals outlive the menu until it is freed)
	if _alone and mode != UnifiedSession.MODE_SINGLE:
		_pause_all(true)
	_settle_pause()


## Asks for the single-player pause and shows the menu for whether it took: alone (it did, within a few frames) or with
## others (it didn't). Shown at once as the mode suggests, so a menu alone never flickers.
func _settle_pause() -> void:
	_session.paused = true
	var replay: bool = _session.mode == UnifiedSession.MODE_REPLAY
	_show_mode(replay, _session.mode != UnifiedSession.MODE_SINGLE and not replay)
	if replay:
		return
	for i: int in PAUSE_TAKES_FRAMES:
		if _session.paused or not is_inside_tree():
			break
		await get_tree().process_frame
	if is_inside_tree():
		_alone = _session.paused
		_show_mode(false, not _alone)


func _show_mode(replay: bool, online: bool) -> void:
	var leave: String = "Leave to title"
	if replay:
		leave = "Leave the replay"
	elif _joined():
		leave = "Leave the game"
	elif _others() > 0:
		leave = "End the game"
	_screen.show_mode(replay, online, leave, not _joined(), _others() > 0)


## Pauses or resumes the game for everyone: the co-op pause, as this machine's first player.
func _pause_all(paused: bool) -> void:
	var command := CommandSetPaused.new()
	command.paused = paused
	_session.send_command(command)


func _open_players() -> void:
	var players := _stack.push(players_scene) as PlayersScreen
	players.drop_requested.connect(func(local: int) -> void: couch.drop(local))


## Leaves the game (`quit`: quits the app), asking first unless this machine only joined someone else's game or watches
## a replay.
func _leave(quit: bool) -> void:
	var act: Callable = Game.quit_app if quit else Game.leave
	if _joined() or _session.mode == UnifiedSession.MODE_REPLAY:
		act.call()
		return
	var heading: String = "Quit to desktop?" if quit else "Leave to the title?"
	var confirm: String = "Quit" if quit else "Leave"
	var others: bool = _others() > 0
	if others:
		heading = "End the game for everyone?"
		confirm = "End the game"
	var saved: String = "Nothing is saved yet: the first surge saves your crypt."
	if Game.saves.setup != null:
		saved = "Your crypt is saved at surge %d: Continue starts it there." % Game.saves.setup.surges
	Game.ask(heading, saved, confirm, "Stay", func(confirmed: bool) -> void:
		if confirmed:
			act.call(), "", others or quit)


func _joined() -> bool:
	return _session.mode in [UnifiedSession.MODE_JOIN_ONLINE, UnifiedSession.MODE_JOIN_DIRECT]


## How many players present aren't on this machine.
func _others() -> int:
	var others: int = 0
	for player: int in _session.get_players():
		if _session.get_local_index(player) < 0:
			others += 1
	return others
