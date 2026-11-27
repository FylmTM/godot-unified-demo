extends UnifiedCoop
## Crypt Crew's co-op play (the flow is the library's, UnifiedCoop): the friend's hero must arrive beside the host's (a
## late join lands by the party, not at the floor's start), as each side sees it; then the host raises skeletons around
## itself (a dev command) and swings at them until one is hit, then walks a square, swinging as it goes, while the
## joiner keeps moving. Once the party has gone down a floor (the descent saves the run), the host pauses the game for everyone (the co-op
## pause) from its pause menu, and its Leave asks "End the game for everyone?" (Stay); the joiner sees who paused (the
## State's paused_by, the HUD's banner, its own menu's heading) and resumes it from its menu, and the host leaves. The
## joiner's app then takes it back to the title, says why, and offers to continue the host's last save on its own, which
## it does, through hero select, at the depth it saw, its boons back (the host's save keeps its row by its profile id).
## Both sessions start from uni's flags, so this also proves the
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
## The vault and the hoard, on both sides before their combat beats (their revives leave each hero at REVIVE_HP): the
## host fells every skeleton and elite the floor raises from then until the descent (dev: a hero downed waiting on its
## plate, the other downed too, would wipe the party and start the floor over, its scene and every view anew); the
## joiner sets out once the elites are gone. Each crosses the spike gallery along its north wall, out of the roller's
## reach, as the spikes there fall; walks to one of the vault gate's two plates, and the gate opens only to both (its
## confirmed Event_Gate, latched). Then each walks into the vault to an end of the hoard (the host the left, the joiner
## the right), takes its handle, and once both holds are confirmed the two carry it a few metres together: it hangs
## clear of the floor and level under the two holds, and neither lets go until each side lets go itself (Interact).
## Each then walks back across the gallery to the floor's start and waits for the other there. The haul to the lift is
## the bots' and the workshop's tests' (simulation/tests/playthrough_test.odin, workshop_test.odin).
##
## The boons' beat, once the combat beats are done: the host puts the party and the hoard aboard the lift (dev_board),
## the deck goes down, and each side's boon panel opens on the confirmed Choosing; each takes a card with Interact. A
## panel locks its card only once its pick is CONFIRMED: from the press until then it never shows the pick taken, and
## on a bad link (`--lag 150 --verified-players`) the joiner must see its own pick predicted (EMITTED) frames before it
## is confirmed, the panel holding through the gap. Both then see the party descend to depth 1.
##
## The run's beats. Begun in the hub (the menus' start, `uni coop --menus`: uni's session flags start on Floor 1), each
## side first turns its shrine round and back (the host the mode's, the joiner the difficulty's), and the run begins
## once both stand on the hub lift's deck. After the boons' beat the host takes the party down the rest of the crypt
## (dev_board, a boon picked on each side each floor) into the vault, wakes the King and drives it into its second stage
## (dev); the two break its ward together, each kindling its braziers until its lighting is CONFIRMED, and both see the
## ward fall; the King, driven on into its third stage, stands warded through the pause. The save the joiner continues
## at the end is the vault's, its boons back.
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
## The joiner's profile id (Settings.profile_id), the same in the process `--crash` starts after the first one died, as
## a player's settings file keeps theirs: the host's save keeps the friend's boons by it. A tool run's own is random.
const FRIEND_PROFILE_ID: String = "1000003"
## How long the host waits for the descent's save, for the friend's resume, and how long the friend waits for the
## host's pause.
const SAVE_WITHIN_S: float = 15.0
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
const SPAWN_WITHIN: float = 0.5  # how near its spawn the host dances
const REVIVE_WITHIN: float = 1.0
const HEAVE_WITHIN: float = 1.4
const ABILITY_S: float = 0.5
const BEAT_S: float = 20.0
## A revive whose ring (or a kindling whose ember) hasn't grown any further for this long (milliseconds; a round trip on
## a bad link and more) was broken off: the reviver (the kindler) presses again.
const RING_STALL_MS: int = 1500
## The vault: how near a hero walks to its plate or a point of its way (metres), how often a walk asks the navigation
## for its path again (frames), how often the host fells the skeletons and elites from the vault's beat on (seconds),
## and the damage that fells every elite at once.
const PLATE_WITHIN: float = 0.35
const WAY_WITHIN: float = 0.25
const REPATH_FRAMES: int = 10
## A walk's last stretch (_walk, _slow_radius): it slows down within SLOW_LEADS times the distance the fastest class
## (the Rogue, FASTEST metres per second) covers over the move's lag, at least SLOW_RADII.x and at most .y metres, at
## no less than SLOWEST of the hero's speed, and lets go once within ARRIVE of its `within` (what it covers after,
## still slowing down, keeps it there). MOVE_DEADZONE is the move actions' (project.godot).
const FASTEST: float = 5.5
const SLOW_LEADS: float = 2.5
const SLOW_RADII: Vector2 = Vector2(0.75, 4.0)
const SLOWEST: float = 0.05
const ARRIVE: float = 0.5
const MOVE_DEADZONE: float = 0.25
const QUIET_S: float = 1.0
const FELL_ELITES: int = 1000
## The hub's beat and the ward's: how near a hero walks to its shrine (and how long it presses Interact there), to the
## hub lift's deck (its side's corner, this far out from the middle); where a hero kindles a brazier from (this far off
## its foot, on the side it comes from: the stand is a column of 0.45 m radius that the hero's 0.45 m can't walk into,
## and BRAZIER_RANGE is 1.6 m) and how near that spot it walks (metres); the depth of the vault; the vault's braziers
## each side kindles, by marker order (game/levels/vault.tscn: the host, spawned west of the joiner, the two west ones,
## the joiner the east one by the spawns, so their ways never cross: two heroes walking head-on along one line push
## against each other for good), and the King's ward stage.
const SHRINE_WITHIN: float = 1.3
const TURN_PRESS_S: float = 0.15
const TURN_GAP_S: float = 0.75  # past the sim's SHRINE_COOLDOWN_S (0.5) between a shrine's two turns
const DECK_CORNER: float = 1.0
const KINDLE_STAND: float = 1.2
const KINDLE_WITHIN: float = 0.3
const VAULT_DEPTH: int = 3
const HOST_BRAZIERS: Array[int] = [2, 0]
const JOINER_BRAZIERS: Array[int] = [3]
const WARD_STAGE: int = 2
## How near the floor's start each walks back to, and waits for the other (metres), before the combat beats.
const MEET_WITHIN: float = 2.0
## The spike gallery's north lane, this far north of the roller's marker (metres): past its path (1.2 m), half its
## pillar, its touch and a hero's radius, with a quarter metre to spare each side (its north wall's face is 3.5 m out).
## A hero waits on the lane this far west (or east) of the north spikes' marker for them to fall: clear of the tile.
const LANE_OFF_ROLLER: float = 2.8
const LANE_WAIT: float = 2.5
## Where the lane meets the gate (metres west of its marker) and where a hero stands inside the vault (east of it).
const LANE_GATE: float = 1.7
const VAULT_IN: float = 1.5
## The carry: where a hauler stands off the hoard's middle, along its handles (metres: its 0.8 m half length, a hero's
## radius, and midway into the hold's band, HOARD_HOLD_NEAR to _FAR off the capsule, where a hold lifts its handle
## rather than pulls it; past the band the two holds pull the chest apart instead of lifting it), how far north the two
## carry it (metres, in at most CARRY_S seconds), and what is
## carried clear (the rules' haul_speed: nothing but heroes touches the chest): every corner of its bottom this far off
## the floor (metres; one hauler lifts only an end, the other's corners drag), its bottom face's half extents
## (HOARD_HALF's x and z less HOARD_CHAMFER: the hull's bottom edges are cut back), and how many frames of the carry
## that must hold for.
const HAUL_STAND: float = 1.4
const CARRY_M: float = 2.5
const CARRY_S: float = 6.0
const CLEAR_Y: float = 0.03
const HOARD_BOTTOM: Vector2 = Vector2(0.6, 0.4)
const CLEAR_FRAMES: int = 10

## The host's hits on skeletons, counted once each is confirmed.
var _hits: int = 0
## The deepest this side saw the party while it played in the host's game (the joiner continues there).
var _depth_seen: int = 0
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
## The vault's gate was confirmed open; the hoard's handles taken and let go, by the hauler's key, and how many of the
## let-gos slipped (the hold stretched too far).
var _gate_open: bool = false
var _grabbed: Dictionary[int, int] = {}
var _dropped: Dictionary[int, int] = {}
var _slipped: int = 0
## The ward's beat's CONFIRMED events: braziers lit by player, shrines turned by player, and whether the ward fell.
var _lit: Dictionary[int, int] = {}
var _turned: Dictionary[int, int] = {}
var _ward_broken: bool = false
## From the ward's beat to the host's pause: the host fells the skeletons the King's stages raise (_keep_minions_down).
var _downing: Array[bool] = [true]
## The host's toasts seen since its play began (_watch_toasts), and whether it still watches them.
var _toasts_seen: Dictionary[String, bool] = {}
var _toasts_watched: Array[bool] = [true]
## From the vault's beat to the descent: the host fells the skeletons and elites the floor raises (_keep_crypt_quiet).
var _quiet: Array[bool] = [true]


func _init() -> void:
	super()
	if arg("role") == "join":
		node_added.connect(_name_friend)


func _run() -> void:
	Unified.data.hud.changed.connect(func() -> void:
		if session != null and session.mode in [UnifiedSession.MODE_JOIN_DIRECT, UnifiedSession.MODE_JOIN_ONLINE]:
			_depth_seen = maxi(_depth_seen, Unified.data.hud.depth))
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
	_watch_toasts()  # not awaited: from now until _check_friend has its toast
	await wait_for(func() -> bool: return _hero(friend) != null, 10.0, "the friend's hero appears")
	if failed():
		return
	var gap: float = _floor_distance(_hero(session.local_player), _hero(friend))
	expect(gap < _beside(), "the friend's hero arrived %.2f m from the host's (at most %.1f)" % [gap, _beside()])
	step("friend's hero arrived %.2f m from the host's" % gap)
	await _check_friend(friend)
	_watch_purse()
	session.sim_event.connect(_count_beats)
	await _shrine_beat(true)
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
	await _vault_beat(true)
	await _host_beats(friend)
	await _boon_beat(true)
	await _ward_beat(true)
	if failed():
		return
	await wait_for(func() -> bool: return Unified.data.hud.depth > 0, SAVE_WITHIN_S, "a descent (a save) before leaving")
	if failed():
		return
	_downing[0] = false
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
	await _shrine_beat(false)
	await _vault_beat(false)
	await _join_beats()
	await _boon_beat(false)
	await _ward_beat(false)
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


## The host lays COINS round its hero and dances among them for DANCE_S, strokes of STROKE_S left and right that never
## reach one (the joiner, predicting each stroke on, picks some up that a rollback gives back), then walks out right
## through the ring and picks one up for real. It dances at its spawn, where every spot of the ring is on the floor (one
## off it, over the lift's shaft say, would be moved onto the floor nearer the host). The skeletons are felled first (a
## dev kill), so nobody is hurt or downed meanwhile and no wipe takes the coins; the strokes turn about, and head back
## once past DANCE_DRIFT, so a hitch in the frames never walks it off. The host picks none of the ring's coins up while
## it dances (the felled skeletons' own coins may lie near), and the walk out's pickup is one confirmed after it began.
func _coin_dance() -> void:
	session.send_command(CommandDevKillMinions.new())
	await _walk_to(_host_spawn, SPAWN_WITHIN, "open floor: the host's spawn")  # no ring spot off the floor
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


## The vault's beat (the header's): the host fells the skeletons and elites from now on (a grave stands by the
## gallery's plate); the joiner waits for the elites to go. Each crosses the gallery on its north lane (by navigation
## to the lane's west end: the hall's way, not the passage the barricade closes), walks to its plate (the host the
## floor's first, in the passage, the joiner its second, in the gallery) and stands there until the gate's opening is
## confirmed; then the carry (_carry_beat), and back across the gallery to the floor's start, where each waits for the
## other (the host's beats then wait for the friend's coin: one picked up on the way, of the felled crowd's, is no
## coin beat's).
func _vault_beat(hosting: bool) -> void:
	if failed():
		return
	if hosting:
		_keep_crypt_quiet(_quiet)  # not awaited: it runs beside the vault and the beats, until the descent
	await wait_for(func() -> bool: return session.get_views(EnumView.ELITE).is_empty(), BEAT_S * 2.0,
		"the elites felled (the host's)")
	var plates: Array[Node3D] = _markers("plate")
	expect(plates.size() == 2 and _markers("gate").size() == 1 and _markers("trap").size() == 3,
		"the floor has the vault's gate, its two plates, the gallery's spikes and roller")
	if failed():
		return
	var plate: Vector3 = plates[0 if hosting else 1].global_position
	await _nav_walk_to(func() -> Vector3: return _lane(-LANE_WAIT), WAY_WITHIN, "the gallery's lane, west")
	await _cross_spikes(func() -> Vector3: return _lane_at_gate(), "across the gallery to the gate")
	await _walk_to(func() -> Vector3: return plate, PLATE_WITHIN, "its plate")
	await wait_for(func() -> bool: return _gate_open, BEAT_S * 2.0, "the vault's gate opens to the two plates")
	if failed():
		return
	await shot("c05_vault_open_" + ("host" if hosting else "joiner"))
	step("stood on a plate of the vault's gate: it opened to the two (%d hp)" % _hp())
	await _walk_to(_lane_at_gate, WAY_WITHIN, "the gallery's lane at the gate")
	await _carry_beat(hosting)
	if failed():
		return
	await _walk_to(func() -> Vector3: return _lane(LANE_WAIT), WAY_WITHIN, "the gallery's lane, east")
	await _cross_spikes(func() -> Vector3: return _lane(-LANE_WAIT), "back across the gallery")
	await _nav_walk_to(_host_spawn, MEET_WITHIN, "the floor's start, where the combat beats play")
	var start: Vector3 = _host_spawn()
	await wait_for(func() -> bool:
		var other: Node3D = _hero(_friend_player())
		if other == null:
			return false
		var gap: Vector3 = other.global_position - start
		return Vector2(gap.x, gap.z).length() < MEET_WITHIN + 1.0, BEAT_S * 2.0, "the other back at the floor's start")
	if hosting:
		_coins.erase(_friend_player())
	step("back at the floor's start with the other (%d hp)" % _hp())


## The carry (the header's), from the gallery's lane at the gate: each walks into the vault and to its end of the
## hoard (the joiner round the chest's north side to its far end), takes the handle there as soon as the "[E] Haul"
## prompt's rule allows (the HUD's haul), waits for the other's hold, and the two walk north until the chest has come
## CARRY_M, then let go. Every hold and let-go counted is a confirmed event: none let go during the carry, none slipped.
func _carry_beat(hosting: bool) -> void:
	var me: int = session.local_player
	var chest: Node3D = _hoard()
	expect(chest != null, "the hoard is on the floor")
	if failed():
		return
	var side: float = -1.0 if hosting else 1.0
	var along: Vector3 = chest.global_basis.x.normalized()
	var north: Vector3 = -chest.global_basis.z.normalized()
	var stand: Vector3 = chest.global_position + along * side * HAUL_STAND
	await _walk_to(func() -> Vector3: return _beyond_gate(VAULT_IN), WAY_WITHIN, "into the vault")
	if not hosting:
		var round_near: Vector3 = chest.global_position - along * HAUL_STAND + north * HAUL_STAND
		await _walk_to(func() -> Vector3: return round_near, WAY_WITHIN, "the hoard's north side")
		await _walk_to(func() -> Vector3: return stand + north * HAUL_STAND, WAY_WITHIN, "round the hoard")
	await _walk_to(func() -> Vector3: return stand, WAY_WITHIN, "its end of the hoard")
	await wait_for(func() -> bool: return _haul_prompt() != EnumHaulHandle.NONE, 3.0, "its handle in reach")
	if failed():
		return
	await press_action(&"interact")
	await wait_for(func() -> bool: return _tally(_grabbed, me) > 0, 5.0, "its hold of the hoard is confirmed")
	await wait_for(func() -> bool: return _tally(_grabbed, _friend_player()) > 0, BEAT_S * 2.0, "the other's hold")
	if failed():
		return
	var drops: int = _dropped.values().reduce(func(sum: int, n: int) -> int: return sum + n, 0)
	var from: Vector3 = chest.global_position
	var clear: int = 0  # frames the chest hung clear of the floor
	var frames_carried: int = 0
	var until: int = Time.get_ticks_msec() + int(CARRY_S * 1000.0)
	Input.action_press(&"move_up")  # north (-Z): the way the hoard's -Z points on this floor
	while not failed() and Time.get_ticks_msec() < until:
		chest = _hoard()
		if chest == null or (chest.global_position - from).dot(north) >= CARRY_M:
			break
		clear += int(_lowest_corner(chest) > CLEAR_Y)
		frames_carried += 1
		await process_frame
	Input.action_release(&"move_up")
	var carried: float = (chest.global_position - from).dot(north) if chest != null else 0.0
	var dropped: int = _dropped.values().reduce(func(sum: int, n: int) -> int: return sum + n, 0)
	expect(carried >= CARRY_M, "the two carried the hoard %.2f m (at least %.1f)" % [carried, CARRY_M])
	expect(dropped == drops, "neither hold let go during the carry (%d did)" % (dropped - drops))
	expect(clear >= CLEAR_FRAMES, "the hoard hung clear of the floor under the two holds (%d of %d frames)"
		% [clear, frames_carried])
	await seconds(0.3)  # both have stopped
	var mine: int = _tally(_dropped, me)
	await press_action(&"interact")
	await wait_for(func() -> bool: return _tally(_dropped, me) > mine, 5.0, "its let-go is confirmed")
	expect(_slipped == 0, "no hold slipped (%d did)" % _slipped)
	if failed():
		return
	step("carried the hoard together %.1f m, clear of the floor %d of %d frames, and let go"
		% [carried, clear, frames_carried])
	var at: Vector3 = _hero(me).global_position
	var inside: Vector3 = _beyond_gate(VAULT_IN)
	await _walk_to(func() -> Vector3: return Vector3(at.x, 0.0, inside.z), WAY_WITHIN, "out from the hoard")
	await _walk_to(func() -> Vector3: return inside, WAY_WITHIN, "the vault's mouth")


## While `running[0]` holds, the host fells every skeleton and elite (dev) every QUIET_S: a surge rising by the
## gallery's plate would down a hero standing on it, waiting for the other, the carry wakes the crypt (the haul's
## surges), and every few surges bring an elite.
func _keep_crypt_quiet(running: Array[bool]) -> void:
	var fell := CommandDevHurtElites.new()
	fell.damage = FELL_ELITES
	while running[0] and not failed():
		session.send_command(CommandDevKillMinions.new())
		session.send_command(fell)
		await seconds(QUIET_S)


## Waits on the gallery's lane for the north spikes to rise and fall (they stay down two of every three seconds), then
## walks straight to `target()` along it, across their tile before they rise again.
func _cross_spikes(target: Callable, what: String) -> void:
	await wait_for(func() -> bool: return _spikes_up(), BEAT_S, "the gallery's spikes rise")
	await wait_for(func() -> bool: return not _spikes_up(), BEAT_S, "the gallery's spikes fall")
	await _walk_to(target, WAY_WITHIN, what)


## Whether the gallery's north spikes are up, as their view shows (false while it isn't found).
func _spikes_up() -> bool:
	var spikes: Vector3 = _north_spikes()
	for view: Node in session.get_views(EnumView.TRAP):
		var trap := view as Node3D
		if Vector2(trap.global_position.x - spikes.x, trap.global_position.z - spikes.z).length() < 0.5:
			var data: ViewTrap = trap.get(&"data")
			return data != null and data.up
	return false


## The boons' beat (the header's): the host puts the party and the hoard aboard the lift (dev_board); each side waits
## for its panel, presses Interact, and watches its panel frame by frame until its pick is confirmed, then waits for
## the descent.
func _boon_beat(hosting: bool) -> void:
	if failed():
		return
	var me: int = session.local_player
	if hosting:
		session.send_command(CommandDevBoard.new())
	var boons: Control = find(current_scene, ^"Hud/%BoonPanels") as Control
	await wait_for(func() -> bool: return not _open_boon_panels(boons).is_empty(), BEAT_S * 2.0,
		"this side's boon panel opens")
	if failed():
		return
	var listed: Array = _open_boon_panels(boons)
	var panel: Control = listed[0]
	await shot("c05_boon_panel_" + ("host" if hosting else "joiner"))
	var seen: Array[int] = [0, 0]  # this side's pick: EMITTED seen, CONFIRMED seen
	var watch: Callable = func(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
		if event is EventBoonPicked and (event as EventBoonPicked).player == me:
			seen[0] += int(state == UnifiedSession.EVENT_EMITTED)
			seen[1] += int(state == UnifiedSession.EVENT_CONFIRMED)
	session.sim_event.connect(watch)
	await press_action(&"interact")
	var early: int = 0  # frames the pick was predicted and not yet confirmed
	var locked_early: int = 0  # frames the panel showed the pick taken before its CONFIRMED
	var until: int = Time.get_ticks_msec() + int(BEAT_S * 1000.0)
	while seen[1] == 0 and Time.get_ticks_msec() < until:
		var locked: bool = is_instance_valid(panel) and panel.call(&"taken")
		locked_early += int(locked)
		early += int(seen[0] > 0)
		await frames(1)
	session.sim_event.disconnect(watch)
	expect(seen[1] > 0, "this side's pick is confirmed")
	expect(locked_early == 0, "the panel showed no pick taken before it was confirmed (%d frames did)" % locked_early)
	if not hosting and arg("lag") != "":
		expect(early > 0, "on a bad link the pick was predicted %d frames before it was confirmed" % early)
	await wait_for(func() -> bool: return Unified.data.hud.depth >= 1, BEAT_S, "the party descends")
	_quiet[0] = false
	step("took a boon, shown once confirmed (%d frames predicted first); the party went down" % early)


## The hub's beat, when the session began in the hub (a game the menus started: `uni coop --menus`; uni's session
## flags start it on Floor 1, and there is nothing to do): each side turns its shrine twice, the host the mode's and the
## joiner the difficulty's (a press each once its "[E] Turn" prompt shows: Hud_Hero.shrine), so each setting goes
## round and back, both turns CONFIRMED; then both walk onto the hub lift's deck, and the run begins on Floor 1 once
## everyone is aboard (the HUD's run phase).
func _shrine_beat(hosting: bool) -> void:
	if failed() or Unified.data.hud.run != EnumRunPhase.HUB:
		return
	var me: int = session.local_player
	var sets: String = "mode" if hosting else "difficulty"
	var shrine: Vector3 = Vector3.INF
	var deck: Vector3 = Vector3.INF
	for marker: Node in Unified.level_markers(find(current_scene, ^"Level") as Node3D):
		var kind: Variant = marker.get(&"UNIFIED_KIND")
		if kind == "shrine" and marker.get(&"sets") == sets:
			shrine = (marker as Node3D).global_position
		elif kind == "lift":
			deck = (marker as Node3D).global_position
	if shrine == Vector3.INF or deck == Vector3.INF:
		fail("the hub has its %s shrine and its lift" % sets)
		return
	await _nav_walk_to(func() -> Vector3: return shrine, SHRINE_WITHIN, "the %s shrine" % sets)
	await wait_for(func() -> bool: return _shrine_prompt(me) != 0, BEAT_S, "the %s shrine's prompt" % sets)
	for turn: int in 2:
		if turn > 0:
			await seconds(TURN_GAP_S)  # a press within the shrine's cooldown turns nothing
		var turned: int = _tally(_turned, me)
		await hold(&"interact", TURN_PRESS_S)  # Input's state: the device a menu-started player plays on takes it
		await wait_for(func() -> bool: return _tally(_turned, me) > turned, BEAT_S, "the %s shrine turned" % sets)
	if failed():
		return
	step("turned the %s shrine round and back, CONFIRMED" % sets)
	var corner := Vector3(-DECK_CORNER if hosting else DECK_CORNER, 0.0, 0.0)
	await _nav_walk_to(func() -> Vector3: return deck + corner, WAY_WITHIN, "the hub lift's deck")
	await wait_for(func() -> bool: return Unified.data.hud.run == EnumRunPhase.PLAYING, BEAT_S * 2.0, "the run begins")
	await wait_for(func() -> bool: return not _hub_shown(), BEAT_S, "Floor 1 shows")  # the verified level, after a fade
	step("both aboard the hub's lift: the run began on Floor 1")


## Whether the level shown is still the hub (it has shrines).
func _hub_shown() -> bool:
	for marker: Node in Unified.level_markers(find(current_scene, ^"Level") as Node3D):
		if marker.get(&"UNIFIED_KIND") == "shrine":
			return true
	return false


## This side's "[E] Turn" prompt (Hud_Hero.shrine: its shrine setting + 1, 0 for none).
func _shrine_prompt(player: int) -> int:
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player == player:
			return hero.shrine
	return 0


## The ward's beat, once the boons' is done (the party one floor down): the host takes the party down the rest of the
## crypt (dev_board on each floor, each side picking its boon with Interact) into the vault; there it wakes the King and
## drives it into its second stage (dev hurts: warded, its braziers out), and the two break the ward together: each
## kindles its braziers (HOST_BRAZIERS, JOINER_BRAZIERS: three, the need for two heroes), holding Interact beside each
## until its lighting is CONFIRMED (_kindle), and both see the confirmed ward fall. The host then drives the King into
## its third stage, warded again and standing in the vault's middle, so nothing hurts the party through the pause; from
## the descents on it fells the skeletons the floors and the stages raise (dev), until its pause.
func _ward_beat(hosting: bool) -> void:
	if failed():
		return
	if hosting:
		_keep_minions_down(_downing)  # not awaited: it runs until the host pauses
	while not failed() and Unified.data.hud.depth < VAULT_DEPTH:
		var depth: int = Unified.data.hud.depth
		if hosting:
			session.send_command(CommandDevBoard.new())
		await _pick_boon(depth)
	if failed():
		return
	step("down to the vault, a boon a floor")
	if hosting:
		var wake := CommandDevHurtElites.new()
		wake.damage = 1
		session.send_command(wake)
		await wait_for(func() -> bool: return Unified.data.hud.boss_hp_max > 0, BEAT_S, "the King wakes")
		_drive_king()
	await wait_for(func() -> bool: return Unified.data.hud.boss_warded and Unified.data.hud.boss_stage == WARD_STAGE,
		BEAT_S, "the King warded in its second stage")
	var braziers: Array[Vector3] = []
	for marker: Node in Unified.level_markers(find(current_scene, ^"Level") as Node3D):
		if marker.get(&"UNIFIED_KIND") == "brazier":
			braziers.append((marker as Node3D).global_position)
	for index: int in (HOST_BRAZIERS if hosting else JOINER_BRAZIERS):
		if index < braziers.size():
			await _kindle(braziers[index])
	await wait_for(func() -> bool: return _ward_broken, BEAT_S * 2.0, "the ward breaks, CONFIRMED")
	if failed():
		return
	step("broke the King's ward together: %d braziers lit here" % _tally(_lit, session.local_player))
	if hosting:
		_drive_king()
	await wait_for(func() -> bool: return Unified.data.hud.boss_stage == WARD_STAGE + 1 and Unified.data.hud.boss_warded,
		BEAT_S, "the King warded in its third stage")


## A blow at the King for its whole health (dev: a blow never takes it past its stage's end): it roars into its next
## stage, warded.
func _drive_king() -> void:
	var blow := CommandDevHurtElites.new()
	blow.damage = Unified.data.hud.boss_hp_max
	session.send_command(blow)


## Waits for this side's boon panel at the lift's bottom, takes its card (Interact), and waits for the party to go down
## past `depth`.
func _pick_boon(depth: int) -> void:
	var boons: Control = find(current_scene, ^"Hud/%BoonPanels") as Control
	await wait_for(func() -> bool: return not _open_boon_panels(boons).is_empty(), BEAT_S * 2.0,
		"this side's boon panel opens")
	if failed():
		return
	await press_action(&"interact")
	await wait_for(func() -> bool: return Unified.data.hud.depth > depth, BEAT_S * 2.0,  # a bad link's picks come late
		"the party goes down past %d" % depth)


## Kindles the brazier whose foot is `at` until this side's lighting is CONFIRMED. A press kindles only with the rules'
## "[E] Light" prompt up (within BRAZIER_RANGE of the foot), and a kindling breaks off for good on a blow or a step out
## of range: then only a new press starts it again. So it walks to a spot KINDLE_STAND off the foot (the stand is a
## column it can't walk into) until the prompt names this brazier, presses and holds, and walks over and presses again
## whenever the brazier's ember (its view's `kindled`) stops growing before the lighting is confirmed.
func _kindle(at: Vector3) -> void:
	var me: int = session.local_player
	var from: Vector3 = _hero(me).global_position
	var off: Vector2 = Vector2(from.x - at.x, from.z - at.z).normalized() * KINDLE_STAND
	var spot: Vector3 = at + Vector3(off.x, 0.0, off.y)
	var lit: int = _tally(_lit, me)
	var until: int = Time.get_ticks_msec() + int(BEAT_S * 1000.0)
	var first_press: int = 0
	var presses: int = 0
	while _tally(_lit, me) == lit and not failed() and Time.get_ticks_msec() < until:
		Input.action_release(&"interact")
		await _nav_walk_to(func() -> Vector3: return spot, KINDLE_WITHIN, "the spot beside a brazier")
		await wait_for(func() -> bool: return _light_prompt(at) != null or _tally(_lit, me) > lit, BEAT_S,
			"the [E] Light prompt names the brazier")
		if failed() or _tally(_lit, me) > lit:
			break
		var brazier: BrazierView = _light_prompt(at)
		Input.action_press(&"interact")
		if presses == 0:
			first_press = Time.get_ticks_msec()
		presses += 1
		var ember: Array[int] = [-1, Time.get_ticks_msec()]  # the brazier's ember as last seen growing, and when
		await wait_for(func() -> bool:
			var shown: int = brazier.data.kindled if is_instance_valid(brazier) else -1
			if shown > ember[0]:
				ember[0] = shown
				ember[1] = Time.get_ticks_msec()
			return _tally(_lit, me) > lit or Time.get_ticks_msec() - ember[1] > RING_STALL_MS, BEAT_S,
			"the kindling grows or stalls")
	Input.action_release(&"interact")
	expect(_tally(_lit, me) > lit, "the lighting is confirmed")
	step("kindled a brazier, CONFIRMED %.1f s after its first press (%d presses)" % [
		(Time.get_ticks_msec() - first_press) / 1000.0, presses])


## The brazier whose foot is `at` while this side's "[E] Light" prompt names it (Hud_Hero.kindle), else null.
func _light_prompt(at: Vector3) -> BrazierView:
	var handle: int = _hud_hero(session.local_player).kindle
	var brazier := Unified.session.get_view(EnumView.BRAZIER, handle) as BrazierView if handle != 0 else null
	if brazier == null or Vector2(brazier.global_position.x - at.x, brazier.global_position.z - at.z).length() > 0.5:
		return null
	return brazier


## While `running[0]` holds, the host fells every skeleton (dev) every QUIET_S, and leaves the King be.
func _keep_minions_down(running: Array[bool]) -> void:
	while running[0] and not failed():
		session.send_command(CommandDevKillMinions.new())
		await seconds(QUIET_S)


## The boon panels open on this side's HUD (BoonPanels.panels).
func _open_boon_panels(boons: Control) -> Array:
	var open: Array = boons.call(&"panels")
	return open


## Where the host's hero started the floor: slot 0's hero_spawn marker.
func _host_spawn() -> Vector3:
	for marker: Node in Unified.level_markers(find(current_scene, ^"Level") as Node3D):
		if marker is HeroSpawn and (marker as HeroSpawn).slot == 0:
			return (marker as HeroSpawn).global_position
	return _hero(session.local_player).global_position


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
	# A press tends the ally only with the rules' "[E] Revive" prompt up, and tending breaks off for good once the two
	# come apart (a ragdoll still sliding from its fall, the reviver's own last steps): then only a new press starts it
	# again. So it walks over until the prompt is up, presses and holds, and walks over and presses again whenever the
	# ally's revive (its view's ring) stops filling before the revive is confirmed. The ally's view may be late (a bad
	# link with --verified-players): the prompt is the rules' own word on the range.
	var until: int = Time.get_ticks_msec() + int(BEAT_S * 1000.0)
	var presses: int = 0
	while _tally(_revived_by, me) == 0 and not failed() and Time.get_ticks_msec() < until:
		Input.action_release(&"interact")
		await _walk_to(at, REVIVE_WITHIN, "the downed ally, to revive it")
		await wait_for(func() -> bool: return _hud_hero(me).revive == ally or _tally(_revived_by, me) > 0, BEAT_S,
			"the [E] Revive prompt names the downed ally")
		if failed() or _tally(_revived_by, me) > 0:
			break
		Input.action_press(&"interact")
		presses += 1
		var ring: Array[int] = [-1, Time.get_ticks_msec()]  # the ally's revive as last seen rising, and when
		await wait_for(func() -> bool:
			var shown: int = _revive_ring(ally)
			if shown > ring[0]:
				ring[0] = shown
				ring[1] = Time.get_ticks_msec()
			return _tally(_revived_by, me) > 0 or Time.get_ticks_msec() - ring[1] > RING_STALL_MS, BEAT_S,
			"the revive fills or stalls")
	Input.action_release(&"interact")
	expect(_tally(_revived_by, me) > 0, "the revive is confirmed")
	step("revived %s (%d presses)" % [session.get_player_name(ally), presses])


## This side waits to be downed by the other's _rescue, and revived by it.
func _rescued() -> void:
	if failed():
		return
	var me: int = session.local_player
	await wait_for(func() -> bool: return _down(me), BEAT_S * 2.0, "the other side downs this hero")
	await wait_for(func() -> bool: return _tally(_revived, me) > 0, BEAT_S * 2.0, "the other side revives it")
	step("downed and revived by %s" % session.get_player_name(_friend_player()))


## Walks this side's hero toward `target()` (it may move: read each frame) on the floor until it is within `within`
## metres (_walk).
func _walk_to(target: Callable, within: float, what: String) -> void:
	await _walk(target, within, what, false)


## Walks this side's hero toward `target()` along the level's navigation (NavigationServer3D's path on the level's
## baked mesh, asked again every REPATH_FRAMES frames), steering at the path's next corner (_walk).
func _nav_walk_to(target: Callable, within: float, what: String) -> void:
	await _walk(target, within, what, true)


## Walks this side's hero toward `target()` (read each frame; along the navigation's path with `nav`) until it is
## within `within` metres, then lets go of the moves; failing after BEAT_S. The moves are a stick's (analog: the
## session reads them as a vector), so the last stretch slows down in proportion to what is left: on a bad link a move
## shows on the hero late and stretched (`--lag 150` on both sides is a 600 ms round trip, past the game's ceiling: the
## view stalls and catches up, and a tap of a seventh of a second moved the hero over two metres), so a hero steered at
## full speed from where it is shown overshoots and circles the target for good. The stretch scales with the lag
## (_slow_radius): on a good link the hero walks in at nearly full speed.
func _walk(target: Callable, within: float, what: String, nav: bool) -> void:
	var map: RID = (find(current_scene, ^"Level") as Node3D).get_world_3d().navigation_map if nav else RID()
	var until: int = Time.get_ticks_msec() + int(BEAT_S * 1000.0)
	var path: PackedVector3Array = []
	var frame: int = 0
	var gap: float = INF
	while not failed() and Time.get_ticks_msec() < until:
		var me: Node3D = _hero(session.local_player)
		if me == null:  # none for a frame after the floor starts over (a wipe): every view is made anew
			await process_frame
			continue
		var at: Vector3 = me.global_position
		var to: Vector3 = target.call()
		gap = Vector2(to.x - at.x, to.z - at.z).length()
		if gap < within * ARRIVE:
			break
		var next: Vector3 = to
		if nav:
			if frame % REPATH_FRAMES == 0:
				path = NavigationServer3D.map_get_path(map, at, to, true)
			for corner: Vector3 in path:
				if Vector2(corner.x - at.x, corner.z - at.z).length() > 0.3:
					next = corner
					break
		frame += 1
		_steer(Vector2(next.x - at.x, next.z - at.z), clampf(gap / _slow_radius(), SLOWEST, 1.0))
		await process_frame
	_steer(Vector2.ZERO, 0.0)
	expect(gap < within, "walked to %s: %.2f m off" % [what, gap])


## Moves this side's hero toward `toward` (on the floor's x and z) at `fraction` of its speed, as a stick held that
## far would (past the move actions' deadzone, which the session's vector takes off again); zero lets go of the moves.
func _steer(toward: Vector2, fraction: float) -> void:
	var stick: Vector2 = toward.normalized() * (MOVE_DEADZONE + fraction * (1.0 - MOVE_DEADZONE)) if fraction > 0.0 \
		else Vector2.ZERO
	_set_move(&"move_right", maxf(stick.x, 0.0))
	_set_move(&"move_left", maxf(-stick.x, 0.0))
	_set_move(&"move_down", maxf(stick.y, 0.0))
	_set_move(&"move_up", maxf(-stick.y, 0.0))


## How far from its target a walk starts slowing down (metres): the distance the hero covers at full speed over
## SLOW_LEADS times the move's lag (the round trip, or the input delay, whichever is longer), within SLOW_RADII.
func _slow_radius() -> float:
	var lag_s: float = maxf(session.round_trip_ms / 1000.0, (session.input_delay_ticks + 1.0) / Unified.tick_hz)
	return clampf(FASTEST * lag_s * SLOW_LEADS, SLOW_RADII.x, SLOW_RADII.y)


## The level's markers of `kind` (their UNIFIED_KIND), in marker order.
func _markers(kind: String) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for marker: Node in Unified.level_markers(find(current_scene, ^"Level") as Node3D):
		var script: Script = marker.get_script()
		if script != null and script.get_script_constant_map().get("UNIFIED_KIND") == kind:
			found.append(marker as Node3D)
	return found


## The point `metres` from the vault's gate along its passage, away from the floor's start (negative: toward it, the
## gallery's side). Every marker here is fetched anew each call: a wipe starts the floor over, and its scene with it.
func _beyond_gate(metres: float) -> Vector3:
	var gate: Node3D = _markers("gate")[0]
	var across: Vector3 = gate.global_basis.z.normalized()
	var spawn: Vector3 = _host_spawn()
	if (gate.global_position + across).distance_to(spawn) < (gate.global_position - across).distance_to(spawn):
		across = -across
	return gate.global_position + across * metres


## The point of the gallery's north lane (LANE_OFF_ROLLER north of the roller) `east` metres east of the north spikes.
func _lane(east: float) -> Vector3:
	var roller: Vector3 = _trap_marker("roller", false)
	return Vector3(_north_spikes().x + east, 0.0, roller.z - LANE_OFF_ROLLER)


## Where the gallery's north lane meets the vault's gate: LANE_GATE short of it.
func _lane_at_gate() -> Vector3:
	return Vector3(_beyond_gate(-LANE_GATE).x, 0.0, _lane(0.0).z)


## The gallery's north spikes: the spikes marker farthest north (least z).
func _north_spikes() -> Vector3:
	return _trap_marker("spikes", true)


## The first trap marker of `kind` ("spikes", "roller"), or with `northmost` the one of least z: its place.
func _trap_marker(kind: String, northmost: bool) -> Vector3:
	var found: Vector3 = Vector3.INF
	for trap: Node3D in _markers("trap"):
		if trap.get(&"kind") == kind and (found == Vector3.INF or (northmost and trap.global_position.z < found.z)):
			found = trap.global_position
	return found


## The hoard's view (null: none), at the middle of its bottom face, turned as the chest is.
func _hoard() -> Node3D:
	var hoards: Array[Node] = session.get_views(EnumView.HOARD)
	return null if hoards.is_empty() else hoards[0] as Node3D


## How high the lowest corner of the hoard's bottom is (its view's root is the bottom's middle).
func _lowest_corner(chest: Node3D) -> float:
	var lowest: float = INF
	for corner: Vector3 in [Vector3(1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(-1, 0, -1)]:
		var at: Vector3 = chest.global_transform * (corner * Vector3(HOARD_BOTTOM.x, 0.0, HOARD_BOTTOM.y))
		lowest = minf(lowest, at.y)
	return lowest


## The hoard's handle this side's hero's Interact would take now, as the HUD has it (EnumHaulHandle).
func _haul_prompt() -> int:
	return _hud_hero(session.local_player).haul


## This side's hero's hit points, as the HUD has them.
func _hp() -> int:
	return _hud_hero(session.local_player).hp


## How far `ally`'s revive has come as its hero view's ring shows it (0 to 255; -1: no view).
func _revive_ring(ally: int) -> int:
	var view: Node3D = _hero(ally)
	var data: ViewHero = view.get(&"data") if view != null else null
	return data.revive if data != null else -1


## `player`'s hero as the HUD's data has it (an empty one while it has none).
func _hud_hero(player: int) -> DataHudHero:
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player == player:
			return hero
	return DataHudHero.new()


## Presses a move action `strength` far (a stick's), or lets go of it (0).
func _set_move(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
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


## Counts the beats' CONFIRMED events (_abilities, _coins, _revived_by, _revived, _landed, the vault's and the hoard's).
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
	elif event is EventGate:
		_gate_open = _gate_open or (event as EventGate).open
	elif event is EventHoardGrabbed:
		var grabbed := event as EventHoardGrabbed
		_grabbed[grabbed.player] = _tally(_grabbed, grabbed.player) + 1
	elif event is EventHoardDropped:
		var dropped := event as EventHoardDropped
		_dropped[dropped.player] = _tally(_dropped, dropped.player) + 1
		_slipped += int(dropped.slipped)
	elif event is EventBrazier and (event as EventBrazier).lit:
		var brazier := event as EventBrazier
		_lit[brazier.player] = _tally(_lit, brazier.player) + 1
	elif event is EventShrine:
		var shrine := event as EventShrine
		_turned[shrine.player] = _tally(_turned, shrine.player) + 1
	elif event is EventBossWard:
		_ward_broken = _ward_broken or not (event as EventBossWard).up


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


## Names the joiner's player and gives it its profile id as its Settings enters the tree: before the session starts,
## with them, from uni's flags.
func _name_friend(node: Node) -> void:
	if node.name == &"Settings" and node.get_parent() == root:
		node.set(&"player_name", FRIEND_NAME)
		node.set(&"profile_id", FRIEND_PROFILE_ID)
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


## Notes the text of every toast the host shows (_toasts_seen) while `_toasts_watched[0]` holds: the friend's toast
## comes once its join is certain, which on a bad link with --verified-players is well before its hero shows (on the
## verified timeline), and may have gone by the time the host looks.
func _watch_toasts() -> void:
	var toasts: Node = find(game, ^"Notices/Toasts")
	while _toasts_watched[0] and not failed():
		for toast: Node in toasts.get_children():
			_toasts_seen[(toast.get_node(^"%Text") as Label).text] = true
		await process_frame


## The friend as the host sees it: its own name, and a toast naming it and its hero (_watch_toasts).
func _check_friend(friend: int) -> void:
	_check_own_class()
	var friend_name: String = session.get_player_name(friend)
	expect(friend_name == FRIEND_NAME, "the friend has its own name: '%s'" % friend_name)
	var text: String = "%s joined (%s)" % [friend_name, Heroes.name_of(Heroes.class_of(friend))]
	await wait_for(func() -> bool: return _toasts_seen.has(text), 5.0, "a toast: " + text)
	_toasts_seen.clear()
	_toasts_watched[0] = false
	step(text)


## The host, after its play: it leaves (the library's), and is back on the title with nothing to explain.
func _host() -> void:
	await super()
	await wait_for(func() -> bool: return scene_is("Menu"), 5.0, "the host back on the title")
	expect(not (find(game, ^"Overlays/Dialog") as Control).visible, "no dialog: the host left as it asked")
	step("host back on the title")


## The joiner, once the host left: back on the title, a dialog saying the game ended and why, offering to continue
## the host's last save alone; Continue on your own keeps it in the slot (what the title's Continue offers) and goes
## through hero select into a single-player game on it, at the depth the joiner last saw, its boons back.
func _host_left() -> void:
	if _lan_pair():
		return  # the recording ended with the host's session
	var seen: int = _depth_seen
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
	expect(kept != null and kept.depth == seen, "the host's save is in the slot, at depth %d (saw %d)"
		% [kept.depth if kept != null else -1, seen])
	await wait_for(func() -> bool: return _menu_top() != null and _menu_top().name == "HeroSelect", 3.0,
		"hero select, on the save")
	if failed():
		return
	var hero_select: Control = _menu_top()
	var card: Control = hero_select.call(&"card", 0)
	await click(find(card, ^"%Act") as Control)
	await click(find(hero_select, ^"%Start") as Control)
	await wait_for(_playing_alone, 10.0, "a game of its own on the host's save")
	expect(Unified.data.hud.depth == seen, "it continues from the host's last save (depth %d, saw %d)"
		% [Unified.data.hud.depth, seen])
	var ranks: int = 0
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.local:
			for rank: int in hero.boons:
				ranks += rank
	expect(ranks > 0, "its boons came back with it (the host's save keeps its row by its profile id)")
	step("continued on its own: depth %d, %d boon ranks" % [Unified.data.hud.depth, ranks])


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
