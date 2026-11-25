extends UnifiedCoop
## Crypt Crew's co-op play (the flow is the library's, UnifiedCoop): the friend's hero must arrive beside the host's
## (a late join lands by the party, not at the floor's start), as each side sees it; then the host raises skeletons
## around itself (a dev command) and swings at them until one is hit, then walks a square, swinging as it goes, while
## the joiner keeps moving. Once a surge has risen (it saves the crypt), the host pauses the game for everyone (the
## co-op pause); the joiner sees who paused (the State's paused_by, the HUD's banner) and resumes it, and the host
## leaves. The joiner's app then takes it back to the title, says why, and offers to continue the host's last save on
## its own, which it does. Both sessions start from uni's flags, so this also proves the app adopts a session its
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


func _init() -> void:
	super()
	if arg("role") == "join":
		node_added.connect(_name_friend)


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
	_set_paused(true)
	await wait_for(func() -> bool: return Unified.data.hud.paused, 3.0, "the host pauses the game for everyone")
	step("paused for everyone")
	await shot("c05_paused_by_host")
	await wait_for(func() -> bool: return not Unified.data.hud.paused, RESUME_WITHIN_S, "the friend resumes it")
	step("the friend resumed it")


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
	_set_paused(false)
	await wait_for(func() -> bool: return not Unified.data.hud.paused, 3.0, "the joiner resumes it for everyone")
	step("resumed it for everyone")


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
	var toasts: Node = find(game, ^"Overlays/Toasts")
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
## the host's last save alone; Continue on your own starts a single-player game on it (its surges on the HUD).
func _host_left() -> void:
	await wait_for(func() -> bool: return scene_is("Menu"), 5.0, "back on the title")
	var dialog: Control = find(game, ^"Overlays/Dialog") as Control
	await wait_for(func() -> bool: return dialog.visible, 5.0, "a dialog says the game ended")
	var heading: String = (find(dialog, ^"%Heading") as Label).text
	var text: String = (find(dialog, ^"%Text") as Label).text
	var ok: Button = find(dialog, ^"%Ok") as Button
	expect(heading == "The game ended", "the dialog's heading: %s" % heading)
	expect(text.begins_with("The host left, or the link to it was lost."), "the dialog's reason: %s" % text)
	expect(ok.text == "Continue on your own", "it offers to continue on your own: %s" % ok.text)
	await shot("c06_host_left")
	step("back on the title: %s %s" % [heading, text])
	if failed():
		return
	await click(ok)
	await wait_for(_playing_alone, 10.0, "a game of its own on the host's save")
	expect(Unified.data.hud.surges > 0, "it continues from the host's last surge (%d)" % Unified.data.hud.surges)
	step("continued on its own: surge %d, %d felled" % [Unified.data.hud.surges, Unified.data.hud.kills])


## This side plays a single-player game of its own, its hero in the crypt.
func _playing_alone() -> bool:
	return scene_is("Play") and session.mode == UnifiedSession.MODE_SINGLE and _playing()


## Pauses (`on`) or resumes the game for everyone (the co-op pause), as this side's player.
func _set_paused(on: bool) -> void:
	var command := CommandSetPaused.new()
	command.paused = on
	session.send_command(command)


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
