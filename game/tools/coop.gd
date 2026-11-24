extends UnifiedCoop
## Crypt Crew's co-op play (the flow is the library's, UnifiedCoop): the friend's hero must arrive beside the host's
## (a late join lands by the party, not at the floor's start), as each side sees it; then the host raises skeletons
## around itself (a dev command) and swings at them until one is hit, then walks a square, swinging as it goes, while
## the joiner keeps moving, until the host leaves. The joiner's app then takes it back to the title and says why.
## Both sessions start from uni's flags, so this also proves the app adopts a session its menus didn't start.

## How far past an arrival's farther ring (twice Unified.constants.arrival_ring: the nearer one may be taken) the
## friend's hero may stand from the host's, in metres: the capsule settling on the floor.
const BESIDE_MARGIN: float = 1.0
## How long the joiner's hero stands where it arrived (seconds), so the host sees it there too.
const STILL_S: float = 3.0
## How many skeletons the host raises to swing at, and how long it waits for a hit (seconds).
const SKELETONS: int = 4
const HIT_WITHIN_S: float = 10.0

const DIRS: Array[StringName] = [&"move_left", &"move_down", &"move_right", &"move_up"]

## The host's hits on skeletons, counted once each is confirmed.
var _hits: int = 0


func _host_play() -> void:
	var friend: int = _friend_player()
	await wait_for(func() -> bool: return _hero(friend) != null, 10.0, "the friend's hero appears")
	if failed():
		return
	var gap: float = _floor_distance(_hero(session.local_player), _hero(friend))
	expect(gap < _beside(), "the friend's hero arrived %.2f m from the host's (at most %.1f)" % [gap, _beside()])
	step("friend's hero arrived %.2f m from the host's" % gap)
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


func _join_play() -> void:
	await wait_for(_playing, 20.0, "the joiner's hero appears")
	if failed():
		return
	var gap: float = _floor_distance(_hero(session.local_player), _hero(_friend_player()))
	expect(gap < _beside(), "the hero arrived %.2f m from the host's (at most %.1f)" % [gap, _beside()])
	step("hero in, %.2f m from the host's" % gap)
	await seconds(STILL_S)
	Input.action_press(&"move_down")  # keeps moving while the host plays on


## The host, after its play: it leaves (the library's), and is back on the title with nothing to explain.
func _host() -> void:
	await super()
	await wait_for(func() -> bool: return scene_is("Menu"), 5.0, "the host back on the title")
	expect(not (find(game, ^"Overlays/Dialog") as Control).visible, "no dialog: the host left as it asked")
	step("host back on the title")


## The joiner, once the host left: back on the title, a dialog saying the game ended and why.
func _host_left() -> void:
	await wait_for(func() -> bool: return scene_is("Menu"), 5.0, "back on the title")
	var dialog: Control = find(game, ^"Overlays/Dialog") as Control
	await wait_for(func() -> bool: return dialog.visible, 5.0, "a dialog says the game ended")
	var heading: String = (find(dialog, ^"%Heading") as Label).text
	var text: String = (find(dialog, ^"%Text") as Label).text
	expect(heading == "The game ended", "the dialog's heading: %s" % heading)
	expect(text == "The host left, or the link to it was lost.", "the dialog's reason: %s" % text)
	await shot("c05_host_left")
	step("back on the title: %s %s" % [heading, text])


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
