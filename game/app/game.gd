extends Node
## The app (the `Game` autoload): it owns the session for the app's whole life, switches between the menu and the
## play scene as the session's status says, holds the overlays that outlive a change of scene, and keeps the rules
## every control of the game shares.
##
##   MENU --the session starts (the menus, the command line's flags, a tool)--> STARTING --CONNECTED--> PLAYING
##   STARTING or PLAYING --leave(), or the session ends--> MENU
##   any --quit_app()--> QUITTING
##
## The session lives here, not in the play scene, because it outlives that scene: it is connecting before the floor
## is loaded, and a failed join has to be shown somewhere. The play scene hands over its level and views roots when
## it is ready (game/play/play.gd), and they leave with it.
##
## Whoever starts the session, the flow follows it. The title calls start_single(); the command line's session flags
## (`--autostart`, `--host-port`, `--join`, `--replay`, which `uni run`, `uni coop`, `uni drive` and the godot suite
## pass) start it as it enters the tree; a tool script may start one itself. Every edge is therefore driven by
## status_changed, never by the button that asked: a session's first status, whoever started it, takes the flow out
## of MENU (the title's own start included: its status arrives inside start_single).
##
## The rules every control shares live here, in one place: each of the game's buttons sounds when pressed and takes
## the focus when the mouse moves over it, so the mouse and a pad never show two highlights; the focus moving between
## controls sounds; the focus frame pulses slowly. Buttons are wired as they enter the tree, hooked from _enter_tree,
## so a scene that is in the tree before any _ready runs (the main scene, on a real launch) is wired too.
##
## Saves: the session hands over a save at each surge (save_changed). When this machine plays alone or hosts it is kept
## in the one slot (Saves), which the title's Continue starts from; a joiner keeps the host's newest in memory only (a
## friend's game never overwrites its own crypt; a host's continued crypt counts from the start), and when the host is
## gone it is offered "Continue on your own": that save goes into its slot (asking first if it holds another crypt)
## and the menu continues it through hero select, as Continue does.
##
## The name and quit_app(exit_code) are a contract: UnifiedTool finds this autoload by its name and ends every tool
## run through quit_app, so a run quits the way a player does.

## The window went to the background while a single-player game plays and the player wants it paused then
## (Settings.pause_in_background): the play scene opens its pause menu.
signal pause_wanted
## The slot's save is to be continued (a joiner chose to continue its host's alone): the menu opens hero select on it.
signal continue_wanted
## A start the menus asked for (a host, a join) failed before it played: the menu goes back to where it was asked, the
## dialog over it saying why.
signal start_failed

enum Flow { MENU, STARTING, PLAYING, QUITTING }

const MENU_SCENE: String = "res://game/menu/menu.tscn"
const PLAY_SCENE: String = "res://game/play/play.tscn"
## The game's own scenes: a button from one of these is wired; the library's dev UI (built in code) is not.
const GAME_SCENES: String = "res://game/"
## The UDP port a LAN game is hosted on, and joined on when an address names none (lan_port can change it).
const LAN_PORT: int = 7777
## A button's sound when it means more than a press (one of Sfx's names): its `sfx` metadata.
const META_SOUND: StringName = &"sfx"
## The focus frame's pulse: a full breath, in seconds, and its faintest, as a share of the frame's full strength.
const FOCUS_PULSE_S: float = 1.6
const FOCUS_PULSE_LOW: float = 0.55
## The input blocks Game itself holds.
const BLOCK_DIALOG: StringName = &"dialog"
const BLOCK_CONNECTING: StringName = &"connecting"


## Why a session ended when it ended on its own: what the menu says once it is back.
class Ending:
	## What happened, the dialog's heading.
	var heading: String
	## Why, as a sentence.
	var reason: String
	## The library's own words, when they say more than `reason` (else empty).
	var detail: String
	## The host's save, when the game a joiner was in ended: the menu offers to continue it alone (null: none).
	var save: UnifiedSetup = null

	func _init(ending_heading: String, ending_reason: String, ending_detail: String) -> void:
		heading = ending_heading
		reason = ending_reason
		detail = ending_detail


## The app's session, from boot to quit (also `Unified.session`).
var session: UnifiedSession
var flow: Flow = Flow.MENU

## The one save slot.
var saves: Saves
## The port this machine hosts a LAN game on: LAN_PORT, unless a check sets another (uni coop --menus hands each run a
## free one; the walk picks one).
var lan_port: int = LAN_PORT

## The party a game started with, until the Couch takes it.
var _party: Party = null
## The host's newest save, while this machine plays in someone else's game (null: none yet, or not joined).
var _host_save: UnifiedSetup = null
## The window has had the focus, so losing it means the player turned away (a tool run's, never in front, never has:
## its focus changes mean nothing until a check sends the focus in).
var _had_focus: bool = false
## Each present player's class (EnumClass) as the HUD's data last said, by key: a leaver's, for its toast.
var _classes: Dictionary[int, int] = {}
## The local indices the Couch seated from the party: their arrival is the game's start, no news (party_seated()).
var _party_locals: Array[int] = []

## Shown on the menu once it is back (null: the session ended as the player asked).
var _ending: Ending = null
## The app asked to quit (quit_app): it goes through whatever else is under way.
var _quit_asked: bool = false
## The session quits the app when it ends (`--quit-at-end`: the godot suite's session step, a replay's check): its
## end is the app's quit, with no menu to go back to.
var _quits_at_end: bool = false
## Why the game's input is off, by name (an overlay, a dialog, the pause menu): on only when nothing holds it off.
## Names, not objects, so a blocker that is freed can't leave it off for good.
var _input_blocks: Array[StringName] = []
## The control that had the focus, to tell a move between controls (a sound) from a screen taking it.
var _focused: Control = null
## While a modal opens and takes the focus: that move is silent (the modal plays its own sound, if any).
var _quiet_focus: bool = false
## The theme's focus frame, which pulses, and its full colours.
var _focus_frame: StyleBoxFlat
var _focus_border: Color
var _focus_glow: Color
var _time: float = 0.0

@onready var _connecting: Connecting = %Connecting
@onready var _link_status: LinkStatus = %LinkStatus
@onready var _dialog: Dialog = %Dialog
@onready var _toasts: Toasts = %Toasts
@onready var _fps: Label = %Fps


func _enter_tree() -> void:
	var tree: SceneTree = get_tree()
	if not tree.node_added.is_connected(_wire):
		tree.node_added.connect(_wire)
	_wire_tree(tree.root)  # what entered before this (on a real launch the whole tree is built before any _ready)


func _ready() -> void:
	get_tree().auto_accept_quit = false  # the window's close button quits through quit_app too
	_quits_at_end = "--quit-at-end" in OS.get_cmdline_user_args()
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_focus_frame = ThemeDB.get_project_theme().get_stylebox(&"focus", &"Button") as StyleBoxFlat
	_focus_border = _focus_frame.border_color
	_focus_glow = _focus_frame.shadow_color
	_connecting.cancelled.connect(leave)
	_link_status.leave_pressed.connect(leave)
	_dialog.closed.connect(unblock_input.bind(BLOCK_DIALOG))
	_had_focus = not Settings.isolated and get_window().has_focus()
	_fps.visible = Settings.show_fps
	Settings.changed.connect(_on_setting_changed)
	saves = Saves.new(Settings.isolated)
	session = UnifiedSession.new()
	session.name = &"UnifiedSession"
	session.view_root = null  # no views until the play scene hands over its root (else they would go under Game)
	session.status_changed.connect(_on_status_changed)
	session.sim_event.connect(_on_sim_event)
	session.local_player_refused.connect(_on_local_player_refused)
	session.save_changed.connect(_on_save_changed)
	session.mode_changed.connect(_on_mode_changed)
	session.join_code_changed.connect(_on_join_code_changed)
	session.local_name = Settings.player_name
	Unified.data.hud.changed.connect(_remember_classes)
	add_child(session)  # last: the command line's session flags start it here, and the flow must already follow
	_preload_play_scene()
	await get_tree().process_frame  # the main scene is up
	_tell_read_problems()


func _process(delta: float) -> void:
	_time += delta
	if not _had_focus and not Settings.isolated and get_window().has_focus():
		_had_focus = true  # a real launch's window takes the focus a moment after _ready
	var strength: float = lerpf(FOCUS_PULSE_LOW, 1.0, 0.5 + 0.5 * cos(TAU * _time / FOCUS_PULSE_S))
	_focus_frame.border_color = Color(_focus_border, _focus_border.a * strength)
	_focus_frame.shadow_color = Color(_focus_glow, _focus_glow.a * strength)
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			quit_app()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_had_focus = true
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			var alone: bool = flow == Flow.PLAYING and session.mode == UnifiedSession.MODE_SINGLE
			if _had_focus and alone and Settings.pause_in_background:
				pause_wanted.emit()


## Starts a single-player game with `party` (hero select's seats; couch co-op is single player too) on `setup` (a save
## to continue; null: a new game): each Any among its seats becomes a class nobody picked (Party.resolve_any), the first
## seat's pick is the session's Profile, and the play scene's Couch brings the other seats in (take_party). Without a
## party, the first player plays Any (the sim resolves it on arrival). Ignored while a game is starting or playing, or
## the app quits; a start that fails says why through the session's status.
func start_single(party: Party = null, setup: UnifiedSetup = null) -> void:
	if _take_party(party):
		session.start_single(setup)


## Hosts a game for friends with `party` on `setup` (a save to continue; null: a new crypt): online (a lobby code, when
## UnifiedSession.online_problem is "") or on the LAN (this machine's address and lan_port). As start_single otherwise.
func start_host(party: Party, setup: UnifiedSetup, online: bool) -> void:
	if not _take_party(party):
		return
	if online:
		session.host_online(setup)
	else:
		session.host_direct(lan_port, setup)


## Joins the game at `target` with `party`: a lobby code, or an address (`host:port`; LAN_PORT when it names none).
## It is remembered for Rejoin last game (Settings.last_join). As start_single otherwise.
func start_join(party: Party, target: String) -> void:
	if not _take_party(party):
		return
	Settings.last_join = target
	if is_address(target):
		session.join_direct(target if target.contains(":") else "%s:%d" % [target, LAN_PORT])
	else:
		session.join_online(target)


## Whether `target` is an address (`host:port`, or a host alone) rather than a lobby code (letters and digits only).
func is_address(target: String) -> bool:
	return target.contains(".") or target.contains(":")

## Whether this machine has a clipboard to copy a code to or paste one from (a headless run has none).
func has_clipboard() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)


## `detail` (the library's words) as a sentence: a capital first, a full stop last; `otherwise` when it is empty.
func sentence(detail: String, otherwise: String) -> String:
	var text: String = detail.strip_edges()
	if text == "":
		return otherwise
	text = text[0].to_upper() + text.substr(1)
	return text if text.ends_with(".") or text.ends_with("!") or text.ends_with("?") else text + "."


## The party a start takes (each Any becomes a class nobody picked; the first seat's pick is the session's Profile);
## false when a game is starting or playing, or the app quits, so nothing starts.
func _take_party(party: Party) -> bool:
	if flow != Flow.MENU:
		return false
	if party != null:
		party.resolve_any()
	_party = party
	Unified.profile.class = party.seats[0].hero_class if party != null else EnumClass.ANY
	return true


## The party the game started with, for the Couch to seat (null: none, or already taken).
func take_party() -> Party:
	var party: Party = _party
	_party = null
	return party


## The Couch seated local player `local` from the party: its arrival is the game's start, so no toast says it.
func party_seated(local: int) -> void:
	_party_locals.append(local)


## Ends the session (the player leaves it, or cancels a start); the menu follows once it has said goodbye. A start
## cancelled hides its overlay at once: the title is already under it.
func leave() -> void:
	if flow == Flow.QUITTING:
		return
	_hide_connecting()
	if session.running:
		session.leave()
	elif flow != Flow.MENU:
		_go_to_menu()


## Quits the app: from the menus, the window's close button, and every tool run's end. Settings are written, the
## interface goes quiet, and UnifiedSession.quit ends the session, stops every sound and quits once the audio server
## has let go of them. It always gets through, a run that quits at its session's end included.
func quit_app(exit_code: int = 0) -> void:
	if _quit_asked:
		return
	_quit_asked = true
	flow = Flow.QUITTING
	Settings.save()
	Sfx.close()
	_collect_play_scene()
	session.quit(exit_code)


## Turns the game's input off for `reason` (an overlay over play): the input helpers read nothing, and the game's own
## handlers (the pause, the couch's join) ignore their keys, until every reason is unblocked.
func block_input(reason: StringName) -> void:
	if reason not in _input_blocks:
		_input_blocks.append(reason)
	session.game_input = false


## Drops `reason` for the game's input being off; it is on again once no reason is left.
func unblock_input(reason: StringName) -> void:
	_input_blocks.erase(reason)
	session.game_input = _input_blocks.is_empty()


## Shows `text` as a toast, a short line that needs no answer.
func toast(text: String) -> void:
	_toasts.show_toast(text)


## Asks the player `heading` (`text` saying what follows, `detail` the library's words under it) with two answers, the
## game's input off meanwhile; `answer` gets true for `confirm_text`, false for `cancel_text`, Esc, a pad's B, or another
## dialog shown over it. `affects_others`: the answer that stays has the focus, else the one that does it.
func ask(heading: String, text: String, confirm_text: String, cancel_text: String, answer: Callable,
		detail: String = "", affects_others: bool = false) -> void:
	block_input(BLOCK_DIALOG)
	_quiet_focus = true
	_dialog.ask(heading, text, confirm_text, cancel_text, answer, detail, affects_others)
	_quiet_focus = false


## Whether this machine keeps the saves: it plays alone or hosts (a joiner keeps the host's in memory only).
func keeps_saves() -> bool:
	return session.mode not in [UnifiedSession.MODE_JOIN_ONLINE, UnifiedSession.MODE_JOIN_DIRECT]


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
				_start()
		UnifiedSession.STATUS_CONNECTED:
			if flow == Flow.MENU:
				_start()
			_keep_host_setup()
			if flow == Flow.STARTING:
				_hide_connecting()
				_enter_play()
			_link_status.close()  # back from reconnecting or catching up
		UnifiedSession.STATUS_RECONNECTING:
			if flow == Flow.PLAYING:
				_link_status.show_reconnecting()
		UnifiedSession.STATUS_RECOVERING:
			if flow == Flow.PLAYING:
				_link_status.show_recovering()
		UnifiedSession.STATUS_FAILED:
			if flow != Flow.PLAYING:  # a start that failed (at once, the flow never left the menu)
				_end(Ending.new(_failed_heading(), sentence(detail, "The game could not start."), ""))
				start_failed.emit()
			else:
				_end(Ending.new("The game ended", sentence(detail, "It stopped on an error."), ""))
		UnifiedSession.STATUS_DISCONNECTED:
			# The library's words say which of the two it was (until its end reason comes as a value).
			var ending := Ending.new("The game ended", "The host left, or the link to it was lost.",
				sentence(detail, ""))
			ending.save = _host_save
			_end(ending)
		UnifiedSession.STATUS_LEFT:
			_go_to_menu()


## The session is starting: the flow leaves the menu, with the overlay a host or a join waits under (single player
## is up within a frame).
func _start() -> void:
	flow = Flow.STARTING
	match session.mode:
		UnifiedSession.MODE_HOST_ONLINE:
			_show_connecting("Opening the crypt", "Setting up a lobby for friends to join.")
		UnifiedSession.MODE_HOST_DIRECT:
			_show_connecting("Opening the crypt", "Opening the game to this network, on port %d." % lan_port)
		UnifiedSession.MODE_JOIN_ONLINE:
			_show_connecting("Joining %s" % Settings.last_join, "Finding the game and its host.")
		UnifiedSession.MODE_JOIN_DIRECT:
			_show_connecting("Joining", "Connecting to %s." % Settings.last_join)


## The heading of a start that failed, by what it tried.
func _failed_heading() -> String:
	match session.mode:
		UnifiedSession.MODE_JOIN_ONLINE, UnifiedSession.MODE_JOIN_DIRECT:
			return "Couldn't join the game"
		UnifiedSession.MODE_HOST_ONLINE, UnifiedSession.MODE_HOST_DIRECT:
			return "Couldn't host the game"
	return "Couldn't start the game"


## The session ended on its own: back to the menu, which then says why.
func _end(ending: Ending) -> void:
	_hide_connecting()
	if flow == Flow.MENU:
		_show_ending(ending)
		return
	_ending = ending
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
	_link_status.close()
	_toasts.clear()
	_party = null
	_host_save = null
	_classes.clear()
	_party_locals.clear()
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != MENU_SCENE:
		get_tree().change_scene_to_file(MENU_SCENE)
		await get_tree().scene_changed
	if _ending != null:
		_show_ending(_ending)
		_ending = null
	_tell_read_problems()
	_preload_play_scene()


## The settings file, or the save, didn't read at boot: the menu says so, once each, the save's when the settings'
## dialog closes (the walk sets a problem to see it said), naming the folder each file was kept in as the player's
## system names it.
func _tell_read_problems() -> void:
	if flow != Flow.MENU or _dialog.visible:
		return
	var told: Callable = func(_acknowledged: bool) -> void: _tell_read_problems.call_deferred()
	if Settings.read_problem != "":
		var kept: String = ProjectSettings.globalize_path(Settings.path + ".bad")
		_show_ending(Ending.new("Your settings didn't read", "The defaults are in use; your file is kept as %s in %s."
			% [kept.get_file(), OS.get_user_data_dir()], sentence(Settings.read_problem, "")), told)
		Settings.read_problem = ""
	elif saves.problem != "":
		_show_ending(Ending.new("Your save can't continue", "Another version of Crypt Crew made it, or it was "
			+ "damaged; it is kept as %s in %s." % [saves.bad_path.get_file(), OS.get_user_data_dir()],
			sentence(saves.problem, "")))
		saves.problem = ""


## Says why the game ended (`then` once the player read it); a joiner whose host left with a save is offered to
## continue it alone.
func _show_ending(ending: Ending, then: Callable = Callable()) -> void:
	Sfx.play(&"error")
	if ending.save != null:
		var save: UnifiedSetup = ending.save
		ask(ending.heading, ending.reason + " You can carry on from the last surge on your own.",
			"Continue on your own", "Back to the title", func(confirmed: bool) -> void:
				if confirmed:
					_continue_alone(save), ending.detail)
		return
	block_input(BLOCK_DIALOG)
	_quiet_focus = true
	_dialog.open(ending.heading, ending.reason, ending.detail, then)
	_quiet_focus = false


## A joiner continues its host's `save` on its own: into its slot (asking first when that holds a crypt of its own),
## then hero select on it, as the title's Continue.
func _continue_alone(save: UnifiedSetup) -> void:
	var take: Callable = func() -> void:
		saves.keep(save)
		continue_wanted.emit()
	if saves.setup == null or saves.setup.to_json() == save.to_json():
		take.call()
		return
	ask("Replace your crypt?", "This replaces your own crypt (%s)." % saves.summary(), "Replace it", "Keep mine",
		func(confirmed: bool) -> void:
			if confirmed:
				take.call())


## A joiner keeps the Setup its host's game started from when it is a save (a host's Continue): the host's save until
## the next surge gives a newer one, so "Continue on your own" is offered from the start.
func _keep_host_setup() -> void:
	if keeps_saves() or _host_save != null:
		return
	var setup: UnifiedSetup = session.setup
	if setup != null and setup.version == Unified.constants.save_version:
		_host_save = setup


func _show_connecting(heading: String, text: String) -> void:
	block_input(BLOCK_CONNECTING)
	_quiet_focus = true
	_connecting.open(heading, text)
	_quiet_focus = false


func _hide_connecting() -> void:
	_connecting.close()
	unblock_input(BLOCK_CONNECTING)


## Loads the play scene on a worker thread while the flow is at the menu, so its meshes and materials (and the shader
## compiles they start) are ready when a game starts instead of stalling the switch. In Godot 4.7 a resource a
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


## Joins and leaves as toasts naming the player and the hero ("Guest 2 joined (Mage)"), once they are certain
## (CONFIRMED). The first local player's own arrival is no news, nor the party's seats' at the start.
func _on_sim_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if state != UnifiedSession.EVENT_CONFIRMED:
		return
	if event is EventPlayerJoined:
		var joined := event as EventPlayerJoined
		var local: int = session.get_local_index(joined.player)
		_remember_classes()
		if local in _party_locals:
			_party_locals.erase(local)
		elif local != 0:
			Sfx.play(&"joined")
			toast("%s %s (%s)" % [session.get_player_name(joined.player), "is back" if joined.returning else "joined",
				_hero_of(joined.player)])
	elif event is EventPlayerLeft:
		var left := event as EventPlayerLeft
		if session.get_local_index(left.player) != 0:
			Sfx.play(&"left")
			toast("%s left (%s)" % [session.get_player_name(left.player), _hero_of(left.player)])
			_classes.erase(left.player)


## A game opened to friends that falls back to single player (its lobby died, or an opening failed): a toast says why.
func _on_mode_changed(mode: UnifiedSession.Mode, detail: String) -> void:
	if mode == UnifiedSession.MODE_SINGLE and detail != "" and flow == Flow.PLAYING:
		toast("Friends can't join: %s" % sentence(detail, ""))


## A lobby's code, once it comes, goes to the clipboard (a toast says so), ready to send to friends (where there is a
## clipboard).
func _on_join_code_changed(code: String) -> void:
	if code != "" and session.mode == UnifiedSession.MODE_HOST_ONLINE and has_clipboard():
		DisplayServer.clipboard_set(code)
		toast("Code %s copied" % code)


## A save from a verified tick: this machine's slot when it plays alone or hosts, else the host's, kept in memory.
func _on_save_changed(setup: UnifiedSetup) -> void:
	if keeps_saves():
		saves.keep(setup)
	else:
		_host_save = setup


## A local player the session refused (the game is full, or closed): a toast says why; its place is free again.
func _on_local_player_refused(local: int, reason: String) -> void:
	_party_locals.erase(local)
	toast("A guest couldn't join: %s" % reason)


## Player `player`'s hero as a toast says it ("Mage"), from what the HUD's data last said.
func _hero_of(player: int) -> String:
	return Heroes.name_of(_classes[player]) if _classes.has(player) else "a hero"


## Wires `node` when it is one of the game's buttons: its press sounds, and the mouse over it gives it the focus.
## Guarded, since a node that leaves the tree and enters again comes through here again. The game's controls all come
## from its scene files (a node from one has an owner, or is the scene's root); the library's dev UI builds its
## controls in code, and its clicks are its own business.
func _wire(node: Node) -> void:
	var button := node as BaseButton
	if button == null:
		return
	var from: Node = button if button.scene_file_path != "" else button.owner
	if from == null or not from.scene_file_path.begins_with(GAME_SCENES):
		return
	var press: Callable = _on_button_pressed.bind(button)
	if not button.pressed.is_connected(press):
		button.pressed.connect(press)
	var hover: Callable = _on_button_hovered.bind(button)
	if not button.mouse_entered.is_connected(hover):
		button.mouse_entered.connect(hover)


func _wire_tree(node: Node) -> void:
	_wire(node)
	for child: Node in node.get_children():
		_wire_tree(child)


func _on_button_pressed(button: BaseButton) -> void:
	var sound: StringName = button.get_meta(META_SOUND, &"press")
	Sfx.play(sound)


## The mouse over a button gives it the focus, unless it takes none (read now: a button may change it).
func _on_button_hovered(button: BaseButton) -> void:
	if button.focus_mode != Control.FOCUS_NONE and button.is_visible_in_tree():
		button.grab_focus()


## A move between two controls sounds; a screen or a modal taking the focus as it opens is silent.
func _on_focus_changed(control: Control) -> void:
	if not _quiet_focus and is_instance_valid(_focused) and _focused.is_visible_in_tree():
		Sfx.play(&"select")
	_focused = control


func _on_setting_changed(setting: StringName) -> void:
	if setting == &"show_fps":
		_fps.visible = Settings.show_fps
	elif setting == &"player_name":
		session.local_name = Settings.player_name  # the next session's


func _remember_classes() -> void:
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player != 0:
			_classes[hero.player] = hero.class
