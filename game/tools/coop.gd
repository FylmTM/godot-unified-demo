extends UnifiedCoop
## Crypt Crew's co-op play (the flow is the library's, UnifiedCoop): the friend's hero must arrive beside the host's (a
## late join lands by the party, not at the floor's start), as each side sees it; then the host raises skeletons around
## itself (a dev command) and swings at them until one is hit, then walks a square, swinging as it goes, while the
## joiner keeps moving. Once a surge has risen (it saves the crypt), the host pauses the game for everyone (the co-op
## pause) from its pause menu, and its Leave asks "End the game for everyone?" (Stay); the joiner sees who paused (the
## State's paused_by, the HUD's banner, its own menu's heading) and resumes it from its menu, and the host leaves. The
## joiner's app then takes it back to the title, says why, and offers to continue the host's last save on its own, which
## it does, through hero select, from the surge it saw. Both sessions start from uni's flags, so this also proves the
## app adopts a session its menus didn't start.
##
## With `uni coop --menus` (and `--lan`), neither side starts from session flags: each goes through the game's own menus
## (_start_host, _start_join: Play together, Host or Join, a code or an address typed with key events, hero select
## with its Profile's class picked, Start), so the menu-driven host and join are proved across two processes too.
##
## With `--rejoin` too, the second join goes through the title's Rejoin (the last game this side joined).
##
## Each side arrives with its own name and its own Profile: the joiner names its player FRIEND_NAME itself (a tool
## run's is Settings.TOOL_NAME), and each side checks its hero is the class its --host-profile or --join-profile asked
## for (the flag's, not Unified.profile, which hero select sets), as the sim they share says; a joiner that asked for
## Any plays a class the host doesn't. The host's toast names the friend and its hero. Run it as
## `./uni coop --lan --host-profile class=Knight --join-profile class=Mage` (and `--rejoin`); without the profiles
## both play Any, which the sim resolves to two classes.
##
## The joiner's HUD says what it joined (the code or address its menus joined, "A friend's game" for a session uni's
## flags started) and how many play; then a couch guest joins it on pad 1, named after the joiner ("Friend +1"), and
## drops out again, across the two processes.
##
## The coins on the link: after its square the host lays coins round its hero and dances among them, short strokes
## left and right that never reach one, while the joiner, a link behind, predicts each stroke running on into the ring
## and picks up coins a rollback then gives back; then the host walks out and picks one up for real. On both sides the
## purse moves only on a CONFIRMED pickup and never down (PurseWatch), and at the co-op pause shows the State's gold.
## On a bad link (`uni coop --lan -- --lag 150 --verified-players`: the joiner predicts the host many ticks deep) the
## joiner must see a pickup taken back (a CANCELLED one), so the purse is shown holding through a misprediction.
##
## The combat beats, on both sides: each uses its class's ability (a Barbarian's is its heave of the downed ally it
## then revives), each picks up a coin (the host's from its dance, the joiner's from coins it lays round itself), and
## each revives the other: once the joiner's coin and ability are confirmed, the host fells the skeletons and downs the
## friend (dev commands), walks over and holds Interact until the revive is confirmed (a Barbarian first heaves the
## friend and throws it, then goes to where it landed); then the joiner does the same for the host. Every beat waits on
## what the shared sim confirmed, never on the clock.
##
## With `-- --play=lan_pair`, each side plays the script the replay regression replays/lan_pair records instead
## (CoopLanPair; `./uni coop --rerecord lan_pair` runs it with the folder's coop.args and keeps the host's recording).

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
## The coins the host lays round its hero (on DEV_DROP_RING, 2 m out), its dance among them (strokes this long, each
## way, a few tens of centimetres: never in reach of one; past DANCE_DRIFT metres off where it began, the next stroke
## heads back whatever the turn) and how long it dances.
const COINS: int = 12
const STROKE_S: float = 0.08
const DANCE_DRIFT: float = 0.25
const DANCE_S: float = 5.0
## How long the host walks out of the ring (seconds): past the coin 2 m to its right.
const WALK_OUT_S: float = 0.8
## The beats: how many coins the joiner lays round itself, how near a hero walks to a coin, an ally to revive or to
## heave (metres: inside LOOT_RADIUS, REVIVE_RANGE and the grab's reach), how long a press of Ability holds (a Knight's
## block), and how long a beat may take (seconds).
const JOINER_COINS: int = 6
const COIN_WITHIN: float = 0.6
const REVIVE_WITHIN: float = 1.0
const HEAVE_WITHIN: float = 1.4
const ABILITY_S: float = 0.5
const BEAT_S: float = 20.0

## The host's hits on skeletons, counted once each is confirmed.
var _hits: int = 0
## The most surges this side saw while it played in the host's game (the joiner continues from them).
var _surges_seen: int = 0
## How many times this side joined through the menus (the second is a --rejoin: the title's Rejoin).
var _menu_joins: int = 0
## What this side's menus joined ("" while it joined from uni's flags).
var _joined: String = ""
## The purse through this side's play (PurseWatch), from the friend's arrival.
var _purse_watch: PurseWatch = null
## The beats' confirmed events by player key: abilities used, coins picked up, revives given (by the reviver's key)
## and received, heaved bodies landed (by the thrower's key).
var _abilities: Dictionary[int, int] = {}
var _coins: Dictionary[int, int] = {}
var _revived_by: Dictionary[int, int] = {}
var _revived: Dictionary[int, int] = {}
var _landed: Dictionary[int, int] = {}


func _init() -> void:
	super()
	if arg("role") == "join":
		node_added.connect(_name_friend)


func _run() -> void:
	Unified.data.hud.changed.connect(func() -> void:
		if session != null and session.mode in [UnifiedSession.MODE_JOIN_DIRECT, UnifiedSession.MODE_JOIN_ONLINE]:
			_surges_seen = maxi(_surges_seen, Unified.data.hud.surges))
	await super()


## Hosts through the game's own menus (uni coop --menus): Play together, then Host on this network (on `port`, made
## Game.lan_port) or Host online (`port` 0), then hero select with this side's Profile's class picked, and Start.
func _start_host(port: int) -> void:
	if port > 0:
		game.set(&"lan_port", port)
	await _open_play_together()
	await click(_on_top("HostLan" if port > 0 else "HostOnline"))
	await _pick_and_start("Host a crypt")
	step("hosted through the menus (%s)" % ("port %d" % port if port > 0 else "online"))


## Joins through the game's own menus (uni coop --menus; again after --crash): Play together, then Join an address
## (`code` is the host's address) or Join with a code, typed with key events, Join, then hero select with this side's
## Profile's class picked, and Start. The second time in one process (--rejoin) it presses Rejoin instead.
func _start_join(code: String) -> void:
	_menu_joins += 1
	_joined = code
	await _open_play_together()
	if _menu_joins > 1:
		var again: Button = _on_top("Rejoin") as Button
		expect(again.visible and not again.disabled and again.text == "Rejoin %s" % code,
			"the title offers the last game: %s" % again.text)
		await click(again)
		await _pick_and_start("Join %s" % code)
		step("rejoined through the title's Rejoin (%s)" % code)
		return
	if code.contains(":"):
		await click(_on_top("JoinAddress"))
		var field: LineEdit = _on_top("Address") as LineEdit
		await click(field)
		field.select_all()
		await type_text(code)
	else:
		await click(_on_top("JoinCode"))
		var cells: Control = _on_top("Code")
		if cells.call(&"code") != code:
			await click(cells)
			await type_text(code)
	expect(not (_on_top("Join") as Button).disabled, "the typed %s can be joined" % code)
	await click(_on_top("Join"))
	await _pick_and_start("Join %s" % code)
	step("joined through the menus (%s)" % code)


func _host_play() -> void:
	if _lan_pair():
		await CoopLanPair.new(self).host()
		return
	var friend: int = _friend_player()
	await wait_for(func() -> bool: return _hero(friend) != null, 10.0, "the friend's hero appears")
	if failed():
		return
	var gap: float = _floor_distance(_hero(session.local_player), _hero(friend))
	expect(gap < _beside(), "the friend's hero arrived %.2f m from the host's (at most %.1f)" % [gap, _beside()])
	step("friend's hero arrived %.2f m from the host's" % gap)
	await _check_friend(friend)
	_watch_purse()
	session.sim_event.connect(_count_beats)
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
	await _coin_dance()
	await _host_beats(friend)
	if failed():
		return
	await wait_for(func() -> bool: return Unified.data.hud.surges > 0, SURGE_WITHIN_S, "a surge (a save) before leaving")
	if failed():
		return
	await press_action(&"pause")
	expect((_menu_control("Heading") as Label).text == "The game runs on",
		"with a friend in, the pause menu is an overlay")
	await click(_menu_control("PauseAll"))
	await wait_for(func() -> bool: return Unified.data.hud.paused, 3.0, "the host pauses the game for everyone")
	step("paused for everyone, from the pause menu")
	await seconds(1.0)  # paused, nothing moves: the verified timeline catches up with the prediction
	_check_purse()
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
	if _lan_pair():
		await CoopLanPair.new(self).join()
		return
	await wait_for(_playing, 20.0, "the joiner's hero appears")
	if failed():
		return
	var gap: float = _floor_distance(_hero(session.local_player), _hero(_friend_player()))
	expect(gap < _beside(), "the hero arrived %.2f m from the host's (at most %.1f)" % [gap, _beside()])
	step("hero in, %.2f m from the host's" % gap)
	_check_own_class()
	var host_class: int = Heroes.class_of(_friend_player())
	if _asked() == EnumClass.ANY:
		expect(Heroes.class_of(session.local_player) != host_class, "asking for Any, it plays a class the host doesn't")
	_watch_purse()
	session.sim_event.connect(_count_beats)
	await seconds(STILL_S)
	await _couch_guest()
	await _join_beats()
	if failed():
		return
	Input.action_press(&"move_down")  # keeps moving while the host plays on
	await wait_for(func() -> bool: return Unified.data.hud.paused, PAUSE_WITHIN_S, "the host pauses for everyone")
	if failed():
		return
	var banner: String = (find(current_scene, ^"Hud/%PausedText") as Label).text
	var host: String = session.get_player_name(_friend_player())
	expect(Unified.data.hud.paused_by == _friend_player(), "the State names the host as who paused")
	expect(banner == "Paused by %s" % host, "the banner names who: %s" % banner)
	step(banner)
	await seconds(1.0)  # paused, nothing moves: the verified timeline catches up with the prediction
	_check_purse()
	if arg("lag") != "":
		expect(_purse_watch.cancelled > 0, "on a bad link, a pickup the joiner predicted was taken back")
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


## The host lays COINS round its hero and dances among them for DANCE_S, strokes of STROKE_S left and right that
## never reach one (the joiner, predicting each stroke on, picks some up that a rollback gives back), then walks out
## right through the ring and picks one up for real. The skeletons are felled first (a dev kill), so nobody is hurt or
## downed meanwhile and no wipe takes the coins; the strokes turn about, and head back once past DANCE_DRIFT, so a
## hitch in the frames never walks it off. The host picks none of the ring's coins up while it dances (the felled
## skeletons' own coins may lie near), and the walk out's pickup is one confirmed after it began.
func _coin_dance() -> void:
	session.send_command(CommandDevKillMinions.new())
	await seconds(1.0)
	var ring: Dictionary[int, bool] = {}  # the ring's coins, by their keys (their events' `loot`)
	var on_ring: Array[int] = [0]  # the host's own pickups of them as it predicts them (EMITTED), while it dances
	var watch_ring: Callable = func(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
		if state != UnifiedSession.EVENT_EMITTED:
			return
		if event is EventLootDropped:
			ring[(event as EventLootDropped).loot] = true
		elif event is EventLootCollected:
			var collected := event as EventLootCollected
			on_ring[0] += int(collected.player == session.local_player and ring.has(collected.loot))
	session.sim_event.connect(watch_ring)
	var drop := CommandDevDropLoot.new()
	drop.count = COINS
	session.send_command(drop)
	await seconds(0.6)  # the coins armed
	var centre: float = _hero(session.local_player).global_position.x
	var dance_until: int = Time.get_ticks_msec() + int(DANCE_S * 1000.0)
	var right: bool = false
	while Time.get_ticks_msec() < dance_until and not failed():
		var off: float = _hero(session.local_player).global_position.x - centre
		right = off < -DANCE_DRIFT or (not right and off <= DANCE_DRIFT)
		await hold(&"move_right" if right else &"move_left", STROKE_S)
	session.sim_event.disconnect(watch_ring)
	expect(ring.size() == COINS, "the ring's %d coins dropped (%d)" % [COINS, ring.size()])
	expect(on_ring[0] == 0, "the host picks none of the ring's coins up while it dances (%d)" % on_ring[0])
	var mark: int = _purse_watch.confirmed
	await hold(&"move_right", WALK_OUT_S)
	await wait_for(func() -> bool: return _purse_watch.confirmed > mark, 5.0, "the walk out picks a coin up")
	step("danced among the coins and walked out: %s" % _purse_watch.summary())


## The host's beats, once its dance picked a coin up: it waits for the joiner's coin and ability, uses its own ability
## (a Barbarian's comes with its rescue), downs the friend and revives it, then waits to be downed and revived in turn.
func _host_beats(friend: int) -> void:
	var barbarian: bool = Heroes.class_of(friend) == EnumClass.BARBARIAN  # its ability comes with its rescue
	await wait_for(func() -> bool: return _tally(_coins, friend) > 0 and (barbarian or _tally(_abilities, friend) > 0),
		BEAT_S * 2.0, "the friend's coin and ability")
	if failed():
		return
	await _ability_beat()
	await _rescue(friend)
	await _rescued()
	_check_beats()


## The joiner's beats: it lays coins round itself and picks one up, uses its ability (a Barbarian's comes with its
## rescue), waits to be downed and revived by the host, then downs the host and revives it.
func _join_beats() -> void:
	await _coin_beat()
	await _ability_beat()
	await _rescued()
	await _rescue(_friend_player())
	_check_beats()


## Each beat of this side was confirmed: its ability, a coin, a revive given and one received.
func _check_beats() -> void:
	var me: int = session.local_player
	expect(_tally(_abilities, me) > 0, "this side used its ability")
	expect(_tally(_coins, me) > 0, "this side picked up a coin")
	expect(_tally(_revived_by, me) > 0 and _tally(_revived, me) > 0, "this side revived and was revived")
	step("beats: %d abilities, %d coins, revived %d and was revived %d" % [_tally(_abilities, me), _tally(_coins, me),
		_tally(_revived_by, me), _tally(_revived, me)])


## This side's ability, unless it plays the Barbarian (its heave needs a body: _rescue's): Ability held ABILITY_S (a
## Knight's block; the Rogue's roll and the Mage's fireball start on its press), until the sim confirms it.
func _ability_beat() -> void:
	var me: int = session.local_player
	if failed() or Heroes.class_of(me) == EnumClass.BARBARIAN:
		return
	await hold(&"ability", ABILITY_S)
	await wait_for(func() -> bool: return _tally(_abilities, me) > 0, 5.0, "this side's ability is confirmed")
	step("used its ability, the %s's" % Heroes.name_of(Heroes.class_of(me)))


## The joiner lays JOINER_COINS coins round its hero (dev) and walks to the first that fell, until the sim confirms its
## pickup (the purse's rule is PurseWatch's).
func _coin_beat() -> void:
	var me: int = session.local_player
	var dropped: Array[Vector3] = []
	var on_drop: Callable = func(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
		if state == UnifiedSession.EVENT_EMITTED and event is EventLootDropped:
			dropped.append((event as EventLootDropped).position)
	session.sim_event.connect(on_drop)
	var drop := CommandDevDropLoot.new()
	drop.count = JOINER_COINS
	session.send_command(drop)
	await wait_for(func() -> bool: return dropped.size() >= JOINER_COINS, 5.0, "the joiner's coins drop")
	session.sim_event.disconnect(on_drop)
	if failed():
		return
	await seconds(0.6)  # the coins armed
	await _walk_to(func() -> Vector3: return dropped[0], COIN_WITHIN, "a coin")
	await wait_for(func() -> bool: return _tally(_coins, me) > 0, 5.0, "the joiner's pickup is confirmed")
	step("picked up a coin it laid")


## This side downs `ally` (dev, the skeletons felled first so nobody else falls) and revives it: walks over and holds
## Interact until the sim confirms the revive. A Barbarian heaves the ally first, throws it, and goes to where it
## landed (its ability's beat).
func _rescue(ally: int) -> void:
	if failed():
		return
	var me: int = session.local_player
	session.send_command(CommandDevKillMinions.new())
	var hurt := CommandDevHurt.new()
	hurt.player = ally
	hurt.damage = 100
	session.send_command(hurt)
	await wait_for(func() -> bool: return _down(ally), 5.0, "the ally is down")
	var at: Callable = func() -> Vector3: return _hero(ally).global_position
	if Heroes.class_of(me) == EnumClass.BARBARIAN:
		await _walk_to(at, HEAVE_WITHIN, "the downed ally, to heave it")
		await press_action(&"ability")
		await wait_for(func() -> bool: return _tally(_abilities, me) > 0, 5.0, "the heave is confirmed")
		await press_action(&"attack")
		await wait_for(func() -> bool: return _tally(_landed, me) > 0, 5.0, "the thrown ally lands")
		step("heaved the downed ally and threw it")
	await _walk_to(at, REVIVE_WITHIN, "the downed ally, to revive it")
	Input.action_press(&"interact")
	await wait_for(func() -> bool: return _tally(_revived_by, me) > 0, BEAT_S, "the revive is confirmed")
	Input.action_release(&"interact")
	step("revived %s" % session.get_player_name(ally))


## This side waits to be downed by the other's _rescue, and revived by it.
func _rescued() -> void:
	if failed():
		return
	var me: int = session.local_player
	await wait_for(func() -> bool: return _down(me), BEAT_S * 2.0, "the other side downs this hero")
	await wait_for(func() -> bool: return _tally(_revived, me) > 0, BEAT_S * 2.0, "the other side revives it")
	step("downed and revived by %s" % session.get_player_name(_friend_player()))


## Walks this side's hero toward `target()` (it may move: read each frame) on the floor until it is within `within`
## metres, steering by the eight move directions, then lets go of the moves; failing after BEAT_S.
func _walk_to(target: Callable, within: float, what: String) -> void:
	var until: int = Time.get_ticks_msec() + int(BEAT_S * 1000.0)
	var gap: Vector2 = Vector2.INF
	while not failed() and Time.get_ticks_msec() < until:
		var me: Node3D = _hero(session.local_player)
		var to: Vector3 = target.call()
		gap = Vector2(to.x - me.global_position.x, to.z - me.global_position.z)
		if gap.length() < within:
			break
		var steer: Vector2 = gap.normalized()
		_set_move(&"move_right", steer.x > 0.38)
		_set_move(&"move_left", steer.x < -0.38)
		_set_move(&"move_down", steer.y > 0.38)
		_set_move(&"move_up", steer.y < -0.38)
		await process_frame
	for move: StringName in DIRS:
		Input.action_release(move)
	expect(gap.length() < within, "walked to %s: %.2f m off" % [what, gap.length()])


## Presses or lets go of a move action.
func _set_move(action: StringName, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


## Whether `player`'s hero is down, as the HUD's data has it.
func _down(player: int) -> bool:
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player == player:
			return hero.down
	return false


## How many `tally` holds for `player`.
func _tally(tally: Dictionary[int, int], player: int) -> int:
	return tally.get(player, 0)


## Counts the beats' CONFIRMED events (_abilities, _coins, _revived_by, _revived, _landed).
func _count_beats(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if state != UnifiedSession.EVENT_CONFIRMED:
		return
	if event is EventAbility:
		var used := event as EventAbility
		_abilities[used.player] = _tally(_abilities, used.player) + 1
	elif event is EventLootCollected:
		var collected := event as EventLootCollected
		_coins[collected.player] = _tally(_coins, collected.player) + 1
	elif event is EventHeroRevived:
		var revived := event as EventHeroRevived
		_revived_by[revived.by] = _tally(_revived_by, revived.by) + 1
		_revived[revived.player] = _tally(_revived, revived.player) + 1
	elif event is EventHeaveLanded:
		var landed := event as EventHeaveLanded
		_landed[landed.player] = _tally(_landed, landed.player) + 1


## Watches this side's purse from now on (PurseWatch).
func _watch_purse() -> void:
	var purse: Control = find(current_scene, ^"Hud/%Purse") as Control
	if purse != null:
		_purse_watch = PurseWatch.new(purse, session)


## The purse kept its rule through this side's play, at the co-op pause (the verified timeline caught up): it moved
## only on confirmed pickups, never down, and shows the State's gold.
func _check_purse() -> void:
	if _purse_watch == null:
		fail("the HUD has its Purse")
		return
	for problem: String in _purse_watch.problems:
		expect(false, problem)
	var gold: int = PurseWatch.gold_of(find(current_scene, ^"Hud/%Purse") as Control)
	expect(gold == Unified.data.hud.gold, "the purse shows the State's gold: %d (%d)" % [gold, Unified.data.hud.gold])
	step("the purse moved on confirmed pickups only, at %d (%s)" % [gold, _purse_watch.summary()])


## Names the joiner's player as its Settings enters the tree: before the session starts, with that name, from uni's
## flags.
func _name_friend(node: Node) -> void:
	if node.name == &"Settings" and node.get_parent() == root:
		node.set(&"player_name", FRIEND_NAME)
		node_added.disconnect(_name_friend)


## The joiner's HUD panel (what it joined, two players), and a couch guest on pad 1 that joins it as "Friend +1" (the
## panel then counts three) and drops out again, before the host's pause.
func _couch_guest() -> void:
	var panel: Control = find(current_scene, ^"Hud/SessionPanel") as Control
	var value: String = (find(panel, ^"%Value") as Label).text
	var players: Label = find(panel, ^"%Players") as Label
	var target: String = _joined if _joined != "" else "A friend's game"
	expect(panel.visible and value == target, "the joiner's panel says what it joined: %s" % value)
	expect(players.text == "2 players", "and who plays: %s" % players.text)
	await pad_button(JOY_BUTTON_START, 1)
	await pad_button(JOY_BUTTON_A, 1)
	var guest: Array[int] = [0]
	await wait_for(func() -> bool:
		guest[0] = session.get_local_player_key(1) if session.local_indices.size() > 1 else 0
		return guest[0] != 0 and guest[0] in session.players, 5.0, "pad 1's guest joins the joiner")
	if failed():
		return
	var guest_name: String = session.get_player_name(guest[0])
	expect(guest_name == FRIEND_NAME + " +1", "the guest is named after the joiner: %s" % guest_name)
	await wait_for(func() -> bool: return players.text == "3 players", 3.0, "the panel counts three: %s" % players.text)
	await shot("c03a_joiner_guest")
	step("a couch guest joined the joiner: %s, %s" % [guest_name, players.text])
	session.remove_local_player(1)
	await wait_for(func() -> bool: return session.players.size() == 2 and players.text == "2 players", 5.0,
		"the guest drops out: two players")
	step("the guest dropped out")


## This side's hero is the class its --host-profile or --join-profile asked for (unless it asked for Any).
func _check_own_class() -> void:
	var asked: int = _asked()
	var arrived: int = Heroes.class_of(session.local_player)
	if asked != EnumClass.ANY:
		expect(arrived == asked, "the %s's Profile asked for the %s: it plays the %s" % [role, Heroes.name_of(asked),
			Heroes.name_of(arrived)])
	step("plays the %s, as its Profile asked (%s)" % [Heroes.name_of(arrived), Heroes.name_of(asked)])


## The class this side's --profile (uni's --host-profile or --join-profile) asked for (Any without one).
func _asked() -> int:
	for assignment: String in arg("profile").split(",", false):
		var key: String = assignment.get_slice("=", 0).strip_edges()
		var value: String = assignment.get_slice("=", 1).strip_edges()
		if key == "class":
			for hero_class: int in Heroes.choices():
				if EnumClass.name(hero_class).to_lower() == value.to_lower():
					return hero_class
			fail("--profile class=%s: no such class" % value)
	return EnumClass.ANY


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
	if _lan_pair():
		return  # the recording ended with the host's session
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


## Whether this run plays replays/lan_pair's script (--play=lan_pair) instead of the co-op checks.
func _lan_pair() -> bool:
	return arg("play") == "lan_pair"


## The title's Play together, once the menu shows the title (the run's main scene, loaded here: no session flag
## started a game to take the app past it).
func _open_play_together() -> void:
	if current_scene == null:
		change_scene_to_file(str(ProjectSettings.get_setting("application/run/main_scene")))
	await wait_for(func() -> bool: return _menu_top() != null and _menu_top().name == "TitleScreen", 10.0, "the title")
	await click(_on_top("PlayTogether"))


## Hero select under `heading`: the first seat (the keyboard and mouse) steps its card to this side's Profile's class
## (its --host-profile or --join-profile), readies it and starts.
func _pick_and_start(heading: String) -> void:
	await wait_for(func() -> bool: return _menu_top() != null and _menu_top().name == "HeroSelect", 3.0, "hero select")
	if failed():
		return
	var hero_select: Control = _menu_top()
	var shown: String = (find(hero_select, ^"%Heading") as Label).text
	expect(shown == heading, "hero select says what it starts: %s" % shown)
	var card: Control = hero_select.call(&"card", 0)
	var wanted: int = Unified.profile.class
	for i: int in Heroes.choices().size():
		var pick: int = card.get(&"pick")
		if pick == wanted:
			break
		await click(find(card, ^"%Next") as Control)
	await click(find(card, ^"%Act") as Control)
	await click(find(hero_select, ^"%Start") as Control)


## The control `unique_name` on the menu's screen on top.
func _on_top(unique_name: String) -> Control:
	return find(_menu_top(), "%" + unique_name) as Control


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
