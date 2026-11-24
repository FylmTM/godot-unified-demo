extends Node
## The app (the `Game` autoload): it owns the session for the app's whole life, switches between the menu and the
## play scene as the session's status says, and holds the overlays that outlive a change of scene.
##
##   MENU --start_single()--> STARTING --STATUS_CONNECTED--> PLAYING --leave(), or the session ends--> MENU
##   MENU --a session the menus didn't start--> STARTING or PLAYING (adopted)
##   any --quit_app()--> QUITTING
##
## The session lives here, not in the play scene, because it outlives that scene: it is connecting before the floor
## is loaded, and a failed join has to be shown somewhere. The play scene hands over its level and views roots when
## it is ready (game/play/play.gd), and they leave with it.
##
## Whoever starts the session, the flow follows it. The menus call start_single(); the command line's session flags
## (`--autostart`, `--host-port`, `--join`, `--replay`, which `uni run`, `uni coop`, `uni drive` and the godot suite
## pass) start it as it enters the tree, and a tool script may start one itself. Every edge is therefore driven by
## status_changed, never by the button that asked: a status the menus didn't ask for is adopted.
##
## The name and quit_app(exit_code) are a contract: UnifiedTool finds this autoload by its name and ends every tool
## run through quit_app, so a run quits the way a player does.

enum Flow { MENU, STARTING, PLAYING, QUITTING }

const MENU_SCENE: String = "res://game/menu/menu.tscn"
const PLAY_SCENE: String = "res://game/play/play.tscn"

## The app's session, from boot to quit (also `Unified.session`).
var session: UnifiedSession
var flow: Flow = Flow.MENU

## What the menu says once it is back, when the session ended on its own (it failed, the host left): a heading, the
## app's sentence and the library's words. Empty when it ended as the player asked.
var _ending: PackedStringArray = []
## The session quits the app when it ends (`--quit-at-end`: the godot suite's session step, a replay's check): an
## end is the app's quit, with no menu to go back to.
var _quits_at_end: bool = false
## Who wants the game's input off (the overlays over play, and later the pause menu): it is on only when nobody does.
var _input_blocks: Array[Object] = []

@onready var _connecting: Connecting = %Connecting
@onready var _dialog: Dialog = %Dialog
@onready var _toasts: Toasts = %Toasts
@onready var _fps: Label = %Fps


func _ready() -> void:
	get_tree().auto_accept_quit = false  # the window's close button quits through quit_app too
	_quits_at_end = "--quit-at-end" in OS.get_cmdline_user_args()
	get_tree().node_added.connect(_on_node_added)
	_connecting.cancelled.connect(leave)
	_dialog.closed.connect(unblock_input.bind(_dialog))
	_fps.visible = Settings.show_fps
	Settings.changed.connect(_on_setting_changed)
	session = UnifiedSession.new()
	session.name = &"UnifiedSession"
	session.view_root = null  # no views until the play scene hands over its root (else they would go under Game)
	session.status_changed.connect(_on_status_changed)
	session.sim_event.connect(_on_sim_event)
	add_child(session)  # last: the command line's session flags start it here, and the flow must already follow
	_preload_play_scene()


func _process(_delta: float) -> void:
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_app()


## Starts a new single-player game (couch co-op is single player too: a pad's Start adds its player).
func start_single() -> void:
	if not session.start_single():
		_show_ending("Couldn't start the game", "The game could not start.", "")
		return
	flow = Flow.STARTING


## Ends the session (the player leaves it, or cancels connecting); the menu follows once it has said goodbye.
func leave() -> void:
	if session.running:
		session.leave()
	elif flow != Flow.MENU:
		_go_to_menu()


## Quits the app: from the menus, the window's close button, and every tool run's end. Settings are written, the
## interface goes quiet, and UnifiedSession.quit ends the session, stops every sound and quits once the audio server
## has let go of them.
func quit_app(exit_code: int = 0) -> void:
	if flow == Flow.QUITTING:
		return
	flow = Flow.QUITTING
	Settings.save()
	Sfx.close()
	_collect_play_scene()
	session.quit(exit_code)


## `blocker` wants the game's input off (an overlay over play): the input helpers read nothing until every blocker
## has unblocked it, so two overlays never fight over one switch.
func block_input(blocker: Object) -> void:
	if blocker not in _input_blocks:
		_input_blocks.append(blocker)
	session.game_input = false


func unblock_input(blocker: Object) -> void:
	_input_blocks.erase(blocker)
	session.game_input = _input_blocks.is_empty()


## Shows `text` as a toast, a short line that needs no answer.
func toast(text: String) -> void:
	_toasts.show_toast(text)


func _on_status_changed(status: UnifiedSession.Status, detail: String) -> void:
	if flow == Flow.QUITTING:
		return
	var ended: bool = status in [UnifiedSession.STATUS_FAILED, UnifiedSession.STATUS_DISCONNECTED,
		UnifiedSession.STATUS_LEFT]
	if ended and _quits_at_end:
		flow = Flow.QUITTING  # the session quits the app now: no menu, and no sound to outlive the quit
		Sfx.close()
		return
	match status:
		UnifiedSession.STATUS_CONNECTING:
			if flow == Flow.MENU:
				_adopt()
		UnifiedSession.STATUS_CONNECTED:
			if flow == Flow.MENU:
				_adopt()
			if flow == Flow.STARTING:
				_enter_play()
			_hide_connecting()  # connected at last, or back from reconnecting or catching up
		UnifiedSession.STATUS_RECONNECTING:
			_show_connecting("Reconnecting", "The link to the host was lost. Your place in the game is kept.")
		UnifiedSession.STATUS_RECOVERING:
			_show_connecting("Catching up", "Putting your game back in step with the others'.")
		UnifiedSession.STATUS_FAILED:
			if flow != Flow.PLAYING:  # a start that failed (at once: the flow may not have left the menu)
				_end(_failed_heading(), "The game could not start.", detail)
			else:
				_end("The game ended", "It stopped on an error.", detail)
		UnifiedSession.STATUS_DISCONNECTED:
			_end("The game ended", "The host left, or the link to it was lost.", detail)
		UnifiedSession.STATUS_LEFT:
			_hide_connecting()
			_go_to_menu()


## A session the menus didn't start (the command line's flags, a tool) is the app's too: the flow takes it up where
## it is, with the overlay a menu start would have shown.
func _adopt() -> void:
	flow = Flow.STARTING
	match session.mode:
		UnifiedSession.MODE_HOST_ONLINE, UnifiedSession.MODE_HOST_DIRECT:
			_show_connecting("Opening the crypt", "Setting up a game for friends to join.")
		UnifiedSession.MODE_JOIN_ONLINE, UnifiedSession.MODE_JOIN_DIRECT:
			_show_connecting("Joining", "Finding the game and its host.")


## The heading of a start that failed, by what it tried.
func _failed_heading() -> String:
	match session.mode:
		UnifiedSession.MODE_JOIN_ONLINE, UnifiedSession.MODE_JOIN_DIRECT:
			return "Couldn't join the game"
		UnifiedSession.MODE_HOST_ONLINE, UnifiedSession.MODE_HOST_DIRECT:
			return "Couldn't host the game"
	return "Couldn't start the game"


## The session ended on its own: back to the menu, which then says why.
func _end(heading: String, text: String, detail: String) -> void:
	_hide_connecting()
	if flow == Flow.MENU:
		_show_ending(heading, text, detail)
		return
	_ending = [heading, text, detail]
	_go_to_menu()


func _enter_play() -> void:
	flow = Flow.PLAYING
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == PLAY_SCENE:
		return  # the play scene run on its own (the editor's Run Current Scene): it is here already
	var scene: PackedScene = _collect_play_scene()
	get_tree().change_scene_to_packed(scene if scene != null else load(PLAY_SCENE) as PackedScene)


func _go_to_menu() -> void:
	if flow == Flow.MENU:
		return
	flow = Flow.MENU
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != MENU_SCENE:
		get_tree().change_scene_to_file(MENU_SCENE)
		await get_tree().scene_changed
	if not _ending.is_empty():
		_show_ending(_ending[0], _ending[1], _ending[2])
		_ending = []
	_preload_play_scene()


func _show_ending(heading: String, text: String, detail: String) -> void:
	Sfx.play(&"error")
	block_input(_dialog)
	_dialog.open(heading, text, detail)


func _show_connecting(heading: String, text: String) -> void:
	block_input(_connecting)
	_connecting.open(heading, text)


func _hide_connecting() -> void:
	_connecting.close()
	unblock_input(_connecting)


## Loads the play scene on a worker thread while the menu is up, so its meshes and materials (and the shader compiles
## they start) are ready before the player picks a game instead of stalling the switch. In Godot 4.7 a resource a
## script first preloads on a worker thread is reported as leaked at exit, so the play scene's scripts load() what
## they need (game/tools/validate.gd names the play scene, and the check holds them to it).
func _preload_play_scene() -> void:
	for i: int in 2:  # the menu's first frames first
		await get_tree().process_frame
	var idle: bool = ResourceLoader.load_threaded_get_status(PLAY_SCENE) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	if flow == Flow.MENU and idle:
		ResourceLoader.load_threaded_request(PLAY_SCENE)


## The play scene from the background load (waiting for it if it is still loading); null when none was asked for. A
## load left uncollected would be held until exit, so the quit collects it too.
func _collect_play_scene() -> PackedScene:
	if ResourceLoader.load_threaded_get_status(PLAY_SCENE) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		return null
	return ResourceLoader.load_threaded_get(PLAY_SCENE) as PackedScene


## Joins and leaves as toasts, once they are certain (CONFIRMED). The first local player's own arrival is no news.
func _on_sim_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if state != UnifiedSession.EVENT_CONFIRMED:
		return
	if event is EventPlayerJoined:
		var joined := event as EventPlayerJoined
		if session.get_local_index(joined.player) != 0:
			Sfx.play(&"joined")
			toast("%s %s" % [session.get_player_name(joined.player), "is back" if joined.returning else "joined"])
	elif event is EventPlayerLeft:
		var left := event as EventPlayerLeft
		if session.get_local_index(left.player) != 0:
			Sfx.play(&"left")
			toast("%s left" % session.get_player_name(left.player))


## Every button takes the focus when the mouse moves over it, so the mouse and a pad never show two highlights.
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		if button.focus_mode != Control.FOCUS_NONE:
			button.mouse_entered.connect(button.grab_focus)


func _on_setting_changed(setting: StringName) -> void:
	if setting == &"show_fps":
		_fps.visible = Settings.show_fps
