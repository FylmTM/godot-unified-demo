extends UnifiedCoop
## Crypt Crew's co-op play (the flow is the library's, UnifiedCoop): the friend's hero must arrive beside the host's
## (a late join lands by the party, not at the floor's start), as each side sees it; then the host raises skeletons
## around itself (a dev command) and swings at them until one is hit, then walks a square, swinging as it goes, while
## the joiner keeps moving. Once a surge has risen (it saves the crypt), the host pauses the game for everyone (the
## co-op pause) from its pause menu, and its Leave asks "End the game for everyone?" (Stay); the joiner sees who paused
## (the State's paused_by, the HUD's banner, its own menu's heading) and resumes it from its menu, and the host leaves.
## The joiner's app then takes it back to the title, says why, and offers to continue the host's last save on its own,
## which it does, through hero select, from the surge it saw. Both sessions start from uni's flags, so this also proves the app adopts a session its
## menus didn't start.
##
## Each side arrives with its own name and its own Profile: the joiner names its player FRIEND_NAME itself (a tool
## run's is Settings.TOOL_NAME), and each side checks its hero is the class its own Profile asked for, as the sim they
## share says; the host's toast names the friend and its hero. Run it as
## `./uni coop --lan --host-profile class=Knight --join-profile class=Mage` (and `--rejoin`); without the profiles
## both play Any, which the sim resolves to two classes.

## How far past an arrival's farther ring (twice Unified.constants.arrival_ring: the nearer one may be taken) the
## friend's hero may stand from the host's, in metres: the capsule settling on the floor.
const BESIDE_MARGIN: float = 1.0
## How long the joiner's hero stands where it arrived (seconds), so the host sees it there too.
const STILL_S: float = 3.0
## How many skeletons the host raises to swing at, and how long it waits for a hit (seconds).
const SKELETONS: int = 4
const HIT_WITHIN_S: float = 10.0

const DIRS: Array[StringName] = [&"move_left", &"move_down", &"move_right", &"move_up"]
## The joiner's name.
const FRIEND_NAME: String = "Friend"
## How long the host waits for the first surge (seconds of play: it saves the crypt), for the friend's resume, and how
## long the friend waits for the host's pause.
const SURGE_WITHIN_S: float = 15.0
const RESUME_WITHIN_S: float = 15.0
const PAUSE_WITHIN_S: float = 40.0

## The host's hits on skeletons, counted once each is confirmed.
var _hits: int = 0
## The most surges this side saw while it played in the host's game (the joiner continues from them).
var _surges_seen: int = 0


func _init() -> void:
	super()
	if arg("role") == "join":
		node_added.connect(_name_friend)


func _run() -> void:
	Unified.data.hud.changed.connect(func() -> void:
		if session != null and session.mode in [UnifiedSession.MODE_JOIN_DIRECT, UnifiedSession.MODE_JOIN_ONLINE]:
			_surges_seen = maxi(_surges_seen, Unified.data.hud.surges))
	await super()


func _host_play() -> void:
	var friend: int = _friend_player()
	await wait_for(func() -> bool: return _hero(friend) != null, 10.0, "the friend's hero appears")
	if failed():
		return
	var gap: float = _floor_distance(_hero(session.local_player), _hero(friend))
	expect(gap < _beside(), "the friend's hero arrived %.2f m from the host's (at most %.1f)" % [gap, _beside()])
	step("friend's hero arrived %.2f m from the host's" % gap)
	await _check_friend(friend)
	await shot("c03_arrived_beside")
	session.sim_event.connect(_count_hits)
	var raise := CommandDevSpawnMinions.new()
	raise.count = SKELETONS
	session.send_command(raise)
	Input.action_press(&"attack")
	await wait_for(func() -> bool: return _hits > 0, HIT_WITHIN_S, "the host's swings hit a skeleton")
	Input.action_release(&"attack")
	if failed():
		return
	step("swung at the skeletons it raised: %d hits" % _hits)
	for i: int in 16:
		if i % 4 == 0:
			Input.action_press(&"attack")
		await hold(DIRS[floori(i / 4.0) % DIRS.size()], 0.25)
		Input.action_release(&"attack")
	await shot("c04_coop_play")
	step("played together: %d hits, %d skeletons" % [_hits, Unified.data.hud.minions])
	await wait_for(func() -> bool: return Unified.data.hud.surges > 0, SURGE_WITHIN_S, "a surge (a save) before leaving")
	if failed():
		return
	await press_action(&"pause")
	expect((_menu_control("Heading") as Label).text == "The game runs on", "with a friend in, the pause menu is an overlay")
	await click(_menu_control("PauseAll"))
	await wait_for(func() -> bool: return Unified.data.hud.paused, 3.0, "the host pauses the game for everyone")
	step("paused for everyone, from the pause menu")
	await click(_menu_control("Leave"))
	var dialog: Control = find(game, ^"Overlays/Dialog") as Control
	var question: String = (find(dialog, ^"%Heading") as Label).text
	expect(dialog.visible and question == "End the game for everyone?", "with a friend in, Leave asks: %s" % question)
	expect(root.gui_get_focus_owner() == find(dialog, ^"%Other"), "and stays on Stay")
	await shot("c05_end_for_everyone")
	await press_action(&"ui_cancel")
	expect(not dialog.visible, "Stay")
	await wait_for(func() -> bool: return not Unified.data.hud.paused, RESUME_WITHIN_S, "the friend resumes it")
	step("the friend resumed it")
	await press_action(&"ui_cancel")
	expect(_pause_menu() == null, "the host closes its menu")


func _join_play() -> void:
	await wait_for(_playing, 20.0, "the joiner's hero appears")
	if failed():
		return
	var gap: float = _floor_distance(_hero(session.local_player), _hero(_friend_player()))
	expect(gap < _beside(), "the hero arrived %.2f m from the host's (at most %.1f)" % [gap, _beside()])
	step("hero in, %.2f m from the host's" % gap)
	_check_own_class()
	await seconds(STILL_S)
	Input.action_press(&"move_down")  # keeps moving while the host plays on
	await wait_for(func() -> bool: return Unified.data.hud.paused, PAUSE_WITHIN_S, "the host pauses for everyone")
	if failed():
		return
	var banner: String = (find(current_scene, ^"Hud/%PausedText") as Label).text
	var host: String = session.get_player_name(_friend_player())
	expect(Unified.data.hud.paused_by == _friend_player(), "the State names the host as who paused")
	expect(banner == "Paused by %s" % host, "the banner names who: %s" % banner)
	step(banner)
	await press_action(&"pause")
	var heading: String = (_menu_control("Heading") as Label).text
	var resume_all: Button = _menu_control("PauseAll") as Button
	expect(heading == "Paused by %s" % host, "the joiner's menu names who: %s" % heading)
	expect(root.gui_get_focus_owner() == resume_all and resume_all.text == "Resume for everyone",
		"and has Resume for everyone focused")
	await shot("c06_joiner_menu")
	await click(resume_all)
	await wait_for(func() -> bool: return not Unified.data.hud.paused, 3.0, "the joiner resumes it for everyone")
	await press_action(&"ui_cancel")
	expect(_pause_menu() == null, "the joiner closes its menu")
	step("resumed it for everyone, from its pause menu")


## Names the joiner's player as its Settings enters the tree: before the session starts, with that name, from uni's
## flags.
func _name_friend(node: Node) -> void:
	if node.name == &"Settings" and node.get_parent() == root:
		node.set(&"player_name", FRIEND_NAME)
		node_added.disconnect(_name_friend)


## This side's hero is the class its own Profile asked for (unless it asked for Any).
func _check_own_class() -> void:
	var asked: int = Unified.profile.class
	var arrived: int = Heroes.class_of(session.local_player)
	if asked != EnumClass.ANY:
		expect(arrived == asked, "the %s's Profile asked for the %s: it plays the %s" % [role, Heroes.name_of(asked),
			Heroes.name_of(arrived)])
	step("plays the %s, as its Profile asked (%s)" % [Heroes.name_of(arrived), Heroes.name_of(asked)])


## The friend as the host sees it: its own name, and a toast naming it and its hero.
func _check_friend(friend: int) -> void:
	_check_own_class()
	var friend_name: String = session.get_player_name(friend)
	expect(friend_name == FRIEND_NAME, "the friend has its own name: '%s'" % friend_name)
	var text: String = "%s joined (%s)" % [friend_name, Heroes.name_of(Heroes.class_of(friend))]
	var toasts: Node = find(game, ^"Notices/Toasts")
	await wait_for(func() -> bool: return toasts.get_children().any(func(toast: Node) -> bool:
		return (toast.get_node(^"%Text") as Label).text == text), 5.0, "a toast: " + text)
	step(text)


## The host, after its play: it leaves (the library's), and is back on the title with nothing to explain.
func _host() -> void:
	await super()
	await wait_for(func() -> bool: return scene_is("Menu"), 5.0, "the host back on the title")
	expect(not (find(game, ^"Overlays/Dialog") as Control).visible, "no dialog: the host left as it asked")
	step("host back on the title")


## The joiner, once the host left: back on the title, a dialog saying the game ended and why, offering to continue
## the host's last save alone; Continue on your own keeps it in the slot (what the title's Continue offers) and goes
## through hero select into a single-player game on it, at the surge the joiner last saw.
func _host_left() -> void:
	var seen: int = _surges_seen
	await wait_for(func() -> bool: return scene_is("Menu"), 5.0, "back on the title")
	var dialog: Control = find(game, ^"Overlays/Dialog") as Control
	await wait_for(func() -> bool: return dialog.visible, 5.0, "a dialog says the game ended")
	var heading: String = (find(dialog, ^"%Heading") as Label).text
	var text: String = (find(dialog, ^"%Text") as Label).text
	var ok: Button = find(dialog, ^"%Ok") as Button
	expect(heading == "The game ended", "the dialog's heading: %s" % heading)
	expect(text.begins_with("The host left, or the link to it was lost."), "the dialog's reason: %s" % text)
	expect(ok.text == "Continue on your own", "it offers to continue on your own: %s" % ok.text)
	await shot("c07_host_left")
	step("back on the title: %s %s" % [heading, text])
	if failed():
		return
	await click(ok)
	var saves: RefCounted = game.get(&"saves")
	var kept: UnifiedSetup = saves.get(&"setup")
	expect(kept != null and kept.surges == seen, "the host's save is in the slot, at surge %d (saw %d)"
		% [kept.surges if kept != null else -1, seen])
	await wait_for(func() -> bool: return _menu_top() != null and _menu_top().name == "HeroSelect", 3.0,
		"hero select, on the save")
	if failed():
		return
	var hero_select: Control = _menu_top()
	var card: Control = hero_select.call(&"card", 0)
	await click(find(card, ^"%Act") as Control)
	await click(find(hero_select, ^"%Start") as Control)
	await wait_for(_playing_alone, 10.0, "a game of its own on the host's save")
	expect(Unified.data.hud.surges == seen, "it continues from the host's last surge (%d, saw %d)"
		% [Unified.data.hud.surges, seen])
	step("continued on its own: surge %d, %d felled" % [Unified.data.hud.surges, Unified.data.hud.kills])


## The play scene's pause menu while it shows (null: closed).
func _pause_menu() -> Control:
	if not scene_is("Play"):
		return null
	var menu: Control = current_scene.call(&"pause_menu")
	return menu


## The pause screen's control `unique_name` (null, failing the run, when the menu isn't open).
func _menu_control(unique_name: String) -> Control:
	var menu: Control = _pause_menu()
	return find(menu.get_node_or_null(^"Stack/PauseScreen") if menu != null else null, "%" + unique_name) as Control


## The menu scene's screen on top (null: not on the menu).
func _menu_top() -> Control:
	if not scene_is("Menu"):
		return null
	var top: Control = current_scene.get_node(^"UI/Stack").call(&"top")
	return top


## This side plays a single-player game of its own, its hero in the crypt.
func _playing_alone() -> bool:
	return scene_is("Play") and session.mode == UnifiedSession.MODE_SINGLE and _playing()


## The joiner's hero is in the crypt.
func _playing() -> bool:
	return _hero(session.local_player) != null


## How far from the host's hero an arrival may stand: its farther ring and the margin.
func _beside() -> float:
	return 2.0 * Unified.constants.arrival_ring + BESIDE_MARGIN


## Counts the host's confirmed hits on skeletons.
func _count_hits(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if state == UnifiedSession.EVENT_CONFIRMED and event is EventMinionHit:
		if (event as EventMinionHit).player == session.local_player:
			_hits += 1


## Player `player`'s hero view (null: none yet).
func _hero(player: int) -> Node3D:
	return session.get_player_view(EnumView.HERO, player) as Node3D


## The distance between two views on the floor (x, z); INF when either is missing.
func _floor_distance(a: Node3D, b: Node3D) -> float:
	if a == null or b == null:
		return INF
	var d: Vector3 = a.global_position - b.global_position
	return Vector2(d.x, d.z).length()
