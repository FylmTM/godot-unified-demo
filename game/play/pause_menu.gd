class_name PauseMenu
extends Control
## The pause menu over play, its own screen stack (the pause screen, the Players list, the settings) and prompt bar.
## The play scene makes one when a player presses pause (Esc, a playing pad's Start), or when the window goes to the
## background in a single-player game, and it frees itself when it closes.
##
## What it pauses follows the session: alone (couch included, UnifiedSession.MODE_SINGLE) it stops the session's clock
## (UnifiedSession.paused) while it shows; with others it is an overlay over the running game, whose co-op pause is the
## Pause for everyone button (the CommandSetPaused command: every peer pauses on one tick, the HUD's banner names who,
## and anyone resumes). Either way the game's input is off while it shows, so its presses move nobody.
##
## Leaving asks first where something is lost or others are affected: alone or hosting, "Leave to the title?" says where
## the crypt is saved; a host with others in ends the game for everyone; a joiner leaves at once (its game goes on).
## Quit asks the same.

## The menu closed (it frees itself).
signal closed

## The input block it holds while it shows (Game.block_input).
const BLOCK: StringName = &"pause_menu"

## The Players list (game/play/players_screen.tscn) and the settings (game/ui/settings/settings_screen.tscn).
@export var players_scene: PackedScene
@export var settings_scene: PackedScene

## The couch, which drops a guest out (the play scene's).
var couch: Couch

@onready var _session: UnifiedSession = Unified.session
@onready var _stack: MenuStack = %Stack
@onready var _prompt_bar: PromptBar = %PromptBar
@onready var _screen: PauseScreen = %PauseScreen


func _ready() -> void:
	Game.block_input(BLOCK)
	_session.paused = true  # alone, the clock stops; with others it reads false and the game runs on
	_screen.resume_requested.connect(close)
	_screen.pause_all_requested.connect(_pause_all)
	_screen.players_requested.connect(_open_players)
	_screen.settings_requested.connect(func() -> void: _stack.push(settings_scene))
	_screen.leave_requested.connect(_leave.bind(false))
	_screen.quit_requested.connect(_leave.bind(true))
	_session.mode_changed.connect(func(_mode: UnifiedSession.Mode, _detail: String) -> void: _show_mode())
	_stack.top_changed.connect(_prompt_bar.follow)
	_prompt_bar.follow(_stack.top())
	_show_mode()


## Leaving the tree (closed, or gone with the play scene when the game ends from it): the clock runs again (alone), the
## game's input is back.
func _exit_tree() -> void:
	_session.paused = false
	Game.unblock_input(BLOCK)


## Closes the menu.
func close() -> void:
	closed.emit()
	queue_free()


## The screen on top, for the walk.
func top() -> MenuScreen:
	return _stack.top()


func _show_mode() -> void:
	var leave: String = "Leave to title"
	if _joined():
		leave = "Leave the game"
	elif _others() > 0:
		leave = "End the game"
	_screen.show_mode(_online(), leave)


## Pauses or resumes the game for everyone: the co-op pause, as this machine's first player.
func _pause_all(paused: bool) -> void:
	var command := CommandSetPaused.new()
	command.paused = paused
	_session.send_command(command)


func _open_players() -> void:
	var players := _stack.push(players_scene) as PlayersScreen
	players.drop_requested.connect(func(local: int) -> void: couch.drop(local))


## Leaves the game (`quit`: quits the app), asking first unless this machine only joined someone else's game.
func _leave(quit: bool) -> void:
	var act: Callable = Game.quit_app if quit else Game.leave
	if _joined():
		act.call()
		return
	var heading: String = "Quit to desktop?" if quit else "Leave to the title?"
	var confirm: String = "Quit" if quit else "Leave"
	if _others() > 0:
		heading = "End the game for everyone?"
		confirm = "End the game"
	var surges: int = Unified.data.hud.surges
	var saved: String = ("Your crypt is saved at surge %d: Continue starts it there." % surges if surges > 0
		else "Nothing is saved yet: the first surge saves your crypt.")
	Game.ask(heading, saved, confirm, "Stay", func(confirmed: bool) -> void:
		if confirmed:
			act.call())


## Someone else plays in this game: it runs on under the menu.
func _online() -> bool:
	return _session.mode != UnifiedSession.MODE_SINGLE


func _joined() -> bool:
	return _session.mode in [UnifiedSession.MODE_JOIN_ONLINE, UnifiedSession.MODE_JOIN_DIRECT]


## How many players present aren't on this machine.
func _others() -> int:
	var others: int = 0
	for player: int in _session.get_players():
		if _session.get_local_index(player) < 0:
			others += 1
	return others
