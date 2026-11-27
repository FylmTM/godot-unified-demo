class_name CoopHaul
extends RefCounted
## The two-player play the replay regression `simulation/tests/replays/haul` records: `./uni coop --rerecord haul` runs
## game/tools/coop.gd with `--play=haul` (the folder's coop.args: a bad link, `--lag 150`), and each side plays its part
## of Floor 1's way out on what the shared sim says (its confirmed events and the HUD), never on the clock:
##
##   1. a Knight host and a Barbarian joiner (both asked for Any) arrive at the floor's start; from then on the host
##      fells every skeleton and elite the floor raises (dev: the play is the haul, not a fight);
##   2. each crosses the spike gallery and stands on one of the vault gate's two plates: the gate opens to the two;
##   3. each takes its end of the hoard (the host the west handle, the joiner the east), and the two carry it out of the
##      vault and along the gallery's north lane to the roller, wait for the spikes, and carry it past the roller and
##      across them as they fall into the hall, where both let go;
##   4. the host steps out onto open floor, and the joiner downs it (dev), heaves it, throws it and revives it where it
##      landed;
##   5. both take their handles again and carry the hoard down the hall and the corridor onto the lift's deck, and let
##      go;
##   6. the lift boards and goes down, each picks a boon at its bottom, and the party descends.
##
## The suite's the_haul_recording_holds_its_play checks the recording holds every step, so a play that changes what it
## does fails there, and `uni coop --record` keeps no recording that fails it. Each step fails the run here first, with
## what didn't happen, and every wait fails at once when the session ends (the other side failed and left).
##
## The carry is two sides steering one chest: each walks toward its own spot in the pair, its end of the chest a lead
## ahead along the way the chest must go (_carry_to), so the faster hero eases off and neither hold stretches. The way
## is the chest's own, in straight legs it keeps to: out of the vault's gate onto the lane (by the floor's markers: the
## pair in line with the way, the chest clear of the roller's reach and the lane's north wall), and from the hall
## Floor 1's own waypoints to the deck (WAY_TO_DECK: the navigation's path, made for a hero, cuts corners a chest
## between two haulers catches on).

## How far ahead of its end of the chest a hauler aims, along the chest's way (metres), and how far from its spot it
## walks at a full stick (nearer, slower).
const LEAD: float = 1.2
const FULL_STICK: float = 1.5
## How far ahead along a straight leg the chest is steered at (metres): near, so it keeps to the line.
const CARROT: float = 1.0
## How near its waypoint the chest's middle must come (metres), how near the deck's middle at the end, and how long a
## leg of the carry may take (seconds).
const CHEST_WITHIN: float = 0.4
const DECK_WITHIN: float = 0.6
const LEG_S: float = 30.0
## Where the pair waits for the spikes: its front hauler this far east of the roller's path (metres: past half its
## pillar, its touch and a hero's radius, and room for the pair's sway), out of its reach; and where the lane's leg
## ends, the back hauler this far clear of the north spikes' sensor (past SPIKES_HALF and a hero's radius).
const ROLLER_CLEAR: float = 0.75 + 0.15 + 0.45 + 0.75
const SPIKES_CLEAR: float = 1.1 + 0.45 + 0.25
## Where the pair sets the chest down in Floor 1's hall (its middle, x and z): north of the hall's long table, its ends
## and the open floor north of it clear of the hall's pillar (the joiner's way round it, the host's spot to be rescued).
const HALL_REST: Vector3 = Vector3(9.0, 0.0, -4.0)
## Floor 1's way for the chest from where the pair sets it down in the hall to the lift (its middle's waypoints, x and
## z): past the hall's long table into the corridor's middle, then south of it through the west doorway, clear of the
## heavy crate by it (the in-line pair clear of the doorways' pillars), and how near each the chest passes before it
## heads for the next (metres).
const WAY_TO_DECK: Array[Vector3] = [Vector3(0.0, 0.0, -2.0), Vector3(-6.5, 0.0, -2.0), Vector3(-11.5, 0.0, -1.4)]
const WAY_WITHIN: float = 1.0
## How far north of the resting chest the joiner walks round it, and how near each point of its way it walks (metres:
## no handle to reach there, only the chest to keep clear of).
const ROUND_OUT: float = 1.6
const ROUND_WITHIN: float = 0.6
## Where the host waits to be rescued (_rescue_spot): this far north of the chest (metres), and how near it the joiner
## waits to see it; how far north of there the joiner throws the host it heaved.
const RESCUE_OUT: float = 2.5
const SPOT_WITHIN: float = 1.2
const THROW_OUT: float = 3.0
## How long a step may take before it fails the run (seconds).
const STEP_S: float = 40.0

var _coop: CryptCoop
var _session: UnifiedSession
## Confirmed events: the vault's gate opened, the hoard's holds taken and let go by player (and how many slipped), the
## revives received by player, and the descent.
var _gate_open: bool = false
var _grabbed: Dictionary[int, int] = {}
var _dropped: Dictionary[int, int] = {}
var _slipped: int = 0
var _revived: Dictionary[int, int] = {}
var _depth: int = 0
## Whether the host still fells what the floor raises (its keeper runs beside the play until the descent).
var _quiet: Array[bool] = [true]


func _init(coop: CryptCoop) -> void:
	_coop = coop
	_session = coop.session
	_session.sim_event.connect(coop.count_beats)  # the rescue's tallies
	_session.sim_event.connect(_count)


## The host's part: the Knight, the hoard's west end.
func host() -> void:
	await _arrive(EnumClass.KNIGHT)
	_coop.keep_crypt_quiet(_quiet)  # not awaited: it runs beside the play, until the descent
	await _open_vault(0)
	await _haul_to_the_hall(-1.0)
	var spot: Vector3 = _rescue_spot()
	await _coop.walk_to(func() -> Vector3: return spot, ROUND_WITHIN, "open floor, to be rescued")
	await _rescued()
	await _haul_to_the_deck(-1.0)
	await _descend()
	_quiet[0] = false
	_coop.result["haul"] = _summary()


## The joiner's part: the Barbarian, the hoard's east end, the host's rescuer.
func join() -> void:
	var friend: int = await _arrive(EnumClass.BARBARIAN)
	await _open_vault(1)
	await _haul_to_the_hall(1.0)
	await _round_the_chest(1.0)
	var spot: Vector3 = _rescue_spot()
	await _wait(func() -> bool: return _flat(_hero(friend).global_position - spot).length() < SPOT_WITHIN, STEP_S,
		"the host on open floor, to be rescued")
	await _coop.rescue(friend, spot + Vector3.FORWARD * THROW_OUT)
	await _haul_to_the_deck(1.0)
	await _descend()
	_coop.result["haul"] = _summary()


## Both heroes in; this side plays `wanted` (both asked for Any: the host gets the first class, the joiner the next).
## Returns the other player.
func _arrive(wanted: int) -> int:
	await _wait(func() -> bool:
		return _hero(_session.local_player) != null and _other() != 0 and _hero(_other()) != null, 20.0,
		"both heroes in")
	var mine: int = Heroes.class_of(_session.local_player)
	_coop.expect(mine == wanted, "this side plays the %s: %s" % [Heroes.name_of(wanted), Heroes.name_of(mine)])
	_coop.step("%s in, the friend's %s too" % [Heroes.name_of(mine), Heroes.name_of(Heroes.class_of(_other()))])
	return _other()


## Once the host's keeper has felled the elites, crosses the gallery on its north lane (as the co-op checks' vault beat
## does) and stands on the vault gate's plate `plate` (marker order) until the gate's opening is confirmed; then back
## to the lane at the gate.
func _open_vault(plate: int) -> void:
	await _wait(func() -> bool: return _session.get_views(EnumView.ELITE).is_empty(), STEP_S, "the elites felled")
	var plates: Array[Node3D] = _coop.markers("plate")
	_coop.expect(plates.size() == 2, "the floor has the vault gate's two plates")
	if _coop.failed():
		return
	var at: Vector3 = plates[plate].global_position
	await _coop.nav_walk_to(func() -> Vector3: return _coop.lane(-CryptCoop.LANE_WAIT), CryptCoop.WAY_WITHIN,
		"the gallery's lane, west")
	await _coop.cross_spikes(_coop.lane_at_gate, "across the gallery to the gate")
	await _coop.walk_to(func() -> Vector3: return at, CryptCoop.PLATE_WITHIN, "its plate")
	await _wait(func() -> bool: return _gate_open, STEP_S, "the vault's gate opens to the two plates")
	if _coop.failed():
		return
	_coop.step("stood on a plate: the vault's gate opened to the two")
	await _coop.walk_to(_coop.lane_at_gate, CryptCoop.WAY_WITHIN, "the gallery's lane at the gate")


## Into the vault to this side's end of the hoard (`side`: -1 the west, 1 the east, along the chest), takes it, and the
## two carry the chest out of the gate, along the lane to the roller, wait for the spikes, carry it past the roller and
## across them as they fall into the hall, and let go.
func _haul_to_the_hall(side: float) -> void:
	await _coop.walk_to(func() -> Vector3: return _coop.beyond_gate(CryptCoop.VAULT_IN), CryptCoop.WAY_WITHIN,
		"into the vault")
	await _take(side)
	var lane_z: float = _coop.lane(0.0).z
	var spikes: float = _coop.north_spikes().x
	var wait_x: float = _coop.trap_marker("roller", false).x + ROLLER_CLEAR + CryptCoop.HAUL_STAND
	await _carry_to(side, Vector3(wait_x, 0.0, lane_z), CHEST_WITHIN, "out of the vault to the roller")
	# The pair sets off as the spikes rise: they are up a second of three, about what the front hauler takes from here
	# to their edge, so it meets them falling and the pair has their two seconds down to cross.
	await _wait(func() -> bool: return not _coop.spikes_up(), STEP_S, "the gallery's spikes are down")
	await _wait(func() -> bool: return _coop.spikes_up(), STEP_S, "the gallery's spikes rise")
	var lane_end: Vector3 = Vector3(spikes - SPIKES_CLEAR - CryptCoop.HAUL_STAND, 0.0, lane_z)
	await _carry_to(side, lane_end, WAY_WITHIN, "past the roller and across the spikes", false,
		Vector3(wait_x, 0.0, lane_z))
	await _carry_to(side, HALL_REST, CHEST_WITHIN, "into the hall", true, lane_end)
	await _let_go()
	_coop.step("carried the hoard together past the roller and the spikes into the hall")


## Takes this side's end of the hoard again and the two carry it by WAY_TO_DECK onto the lift's deck, the chest's
## middle on the deck's, and let go: the two stand on the deck at its ends, so the lift boards.
func _haul_to_the_deck(side: float) -> void:
	await _take(side)
	var lifts: Array[Node3D] = _coop.markers("lift")
	_coop.expect(lifts.size() == 1, "the floor has its lift")
	if _coop.failed():
		return
	var from: Vector3 = _coop.hoard().global_position
	for point: Vector3 in WAY_TO_DECK:
		await _carry_to(side, point, WAY_WITHIN, "down the hall (%.0f, %.0f)" % [point.x, point.z], false, from)
		from = point
	var deck: Vector3 = lifts[0].global_position
	await _carry_to(side, deck, DECK_WITHIN, "onto the lift's deck", true, from)
	await _let_go()
	_coop.step("carried the hoard together onto the lift's deck")


## Walks from this side's end of the resting chest (`side` along it) round its north side to its other end: the
## joiner's way to the host it rescues.
func _round_the_chest(side: float) -> void:
	var chest: Node3D = _coop.hoard()
	if _coop.failed() or chest == null:
		return
	var off: Vector3 = Vector3.FORWARD * ROUND_OUT
	var here: Vector3 = chest.global_position + _along(chest) * side * CryptCoop.HAUL_STAND + off
	var there: Vector3 = chest.global_position - _along(chest) * side * CryptCoop.HAUL_STAND + off
	await _coop.walk_to(func() -> Vector3: return here, ROUND_WITHIN, "the hoard's north side")
	await _coop.walk_to(func() -> Vector3: return there, ROUND_WITHIN, "round the hoard")


## Where the host waits to be rescued: RESCUE_OUT north of the resting chest's west end and a metre past it, open
## floor (the ragdoll falls clear of the chest), as both sides see the chest.
func _rescue_spot() -> Vector3:
	var chest: Node3D = _coop.hoard()
	if chest == null:
		return Vector3.INF
	return chest.global_position - _along(chest) * (CryptCoop.HAUL_STAND + 1.0) + Vector3.FORWARD * RESCUE_OUT


## Walks round the chest to this side's end (the far side by the chest's north), and takes its handle as soon as the
## "[E] Haul" prompt's rule allows; waits for the other's hold too.
func _take(side: float) -> void:
	var me: int = _session.local_player
	var chest: Node3D = _coop.hoard()
	_coop.expect(chest != null, "the hoard is on the floor")
	if _coop.failed():
		return
	var along: Vector3 = _along(chest)
	var north: Vector3 = Vector3.FORWARD
	var stand: Vector3 = chest.global_position + along * side * CryptCoop.HAUL_STAND
	if (_hero(me).global_position - chest.global_position).dot(along) * side < 0.0:  # beyond the chest: round it
		var round_near: Vector3 = chest.global_position - along * side * CryptCoop.HAUL_STAND + north * CryptCoop.HAUL_STAND
		await _coop.walk_to(func() -> Vector3: return round_near, CryptCoop.WAY_WITHIN, "the hoard's north side")
		await _coop.walk_to(func() -> Vector3: return stand + north * CryptCoop.HAUL_STAND, CryptCoop.WAY_WITHIN,
			"round the hoard")
	await _coop.walk_to(func() -> Vector3: return stand, CryptCoop.WAY_WITHIN, "its end of the hoard")
	await _wait(func() -> bool: return _coop.haul_prompt() != EnumHaulHandle.NONE, 3.0, "its handle in reach")
	if _coop.failed():
		return
	var held: int = _grabbed.get(me, 0)
	await _coop.press_action(&"interact")
	await _wait(func() -> bool: return _grabbed.get(me, 0) > held, 5.0, "its hold of the hoard is confirmed")
	await _wait(func() -> bool: return _holding(_other()), STEP_S, "the other's hold")
	if not _coop.failed():
		_coop.step("took its end of the hoard; the other holds its own")


## Carries the hoard with the other until its middle is within `within` of `goal`, along the straight line to it from
## `from` (INF: where the chest is; a leg of a fixed way, so both sides keep to the same lines whenever each takes it
## up: _carrot): this side's hero walks toward its spot in the pair (the west end, `side` -1, in front; the pair in
## line with the way, so a chest the heave's blast turned comes round to it in a doorway's width), LEAD
## ahead along the chest's way (with `stop`, less in the last LEAD metres, so the pair eases in rather than walking on
## past; without, a waypoint it passes, _past), at a stick that grows with how far it has to go. Neither hold may let go
## meanwhile.
func _carry_to(side: float, goal: Vector3, within: float, what: String, stop: bool = true,
		from: Vector3 = Vector3.INF) -> void:
	if _coop.failed():
		return
	var me: int = _session.local_player
	var drops: int = _drops()
	var start: Vector3 = from
	if start == Vector3.INF:
		start = _coop.hoard().global_position if _coop.hoard() != null else goal
	var until: int = Time.get_ticks_msec() + int(LEG_S * 1000.0)
	var gap: float = INF
	while not _coop.failed():
		var chest: Node3D = _coop.hoard()
		var mine: Node3D = _hero(me)
		if chest == null or mine == null:
			_coop.fail("the hoard or the hero is gone: " + what)
			break
		var to: Vector3 = _carrot(start, goal, chest.global_position)
		var way: Vector2 = _flat(to - chest.global_position)
		gap = _flat(goal - chest.global_position).length()
		if gap < within or (not stop and _past(start, goal, chest.global_position, within)):
			break
		if _drops() > drops:
			_coop.fail("a hold let go of the hoard (%d slipped; %d hp here): %s" % [_slipped, _coop.hud_hero(me).hp, what])
			break
		if _lost() or Time.get_ticks_msec() > until:
			_coop.fail("timed out: %s (%.1f m to go)" % [what, gap])
			break
		var lead: float = minf(LEAD, gap) if stop else LEAD
		var ahead: Vector3 = Vector3(way.x, 0.0, way.y).normalized() if way.length() > 0.01 else -_along(chest)
		var spot: Vector3 = chest.global_position - ahead * side * CryptCoop.HAUL_STAND
		var aim: Vector2 = _flat(spot - mine.global_position) + way.normalized() * lead
		_coop.steer(aim, clampf(aim.length() / FULL_STICK, 0.0, 1.0))
		await _coop.frames(1)
	_coop.steer(Vector2.ZERO, 0.0)
	if not _coop.failed():
		_coop.step("carried the hoard %s (%.2f m off)" % [what, gap])


## A point CARROT ahead of where the chest at `at` is along the line from `from` to `goal` (no further than the goal):
## the chest steered at it keeps to that line, clear of what lies either side (the lane's wall, the roller).
func _carrot(from: Vector3, goal: Vector3, at: Vector3) -> Vector3:
	var line: Vector3 = Vector3(goal.x - from.x, 0.0, goal.z - from.z)
	var length: float = line.length()
	if length < 0.001:
		return goal
	var dir: Vector3 = line / length
	var along: float = clampf((at - from).dot(dir), 0.0, length)
	return from + dir * minf(along + CARROT, length)


## Whether the chest at `at` has come along the line from `from` to `goal` to within `within` of the goal's end of
## it, however far to its side: both sides see a waypoint passed alike, so neither heads back for one the other left.
func _past(from: Vector3, goal: Vector3, at: Vector3, within: float) -> bool:
	var line: Vector2 = _flat(goal - from)
	return line.length() < within or _flat(at - from).dot(line.normalized()) > line.length() - within


## Lets go of the hoard (Interact) once both have stopped, and waits for its let-go to be confirmed; none slipped.
func _let_go() -> void:
	if _coop.failed():
		return
	var me: int = _session.local_player
	await _coop.seconds(0.3)
	var let_go: int = _dropped.get(me, 0)
	await _coop.press_action(&"interact")
	await _wait(func() -> bool: return _dropped.get(me, 0) > let_go, 5.0, "its let-go is confirmed")
	_coop.expect(_slipped == 0, "no hold slipped (%d did)" % _slipped)


## The host waits to be downed by the joiner, heaved, thrown and revived.
func _rescued() -> void:
	if _coop.failed():
		return
	var me: int = _session.local_player
	await _wait(func() -> bool: return _coop.down(me), STEP_S, "the joiner downs the host")
	await _wait(func() -> bool: return _revived.get(me, 0) > 0, STEP_S, "the joiner revives the host")
	if not _coop.failed():
		_coop.step("downed, heaved and revived by the joiner")


## Waits for the boon choice at the lift's bottom and picks this side's card (Interact) unless it has picked already,
## then waits for the descent to be confirmed. The lift may board, go down and open the choice while this side is still
## letting go: the choice is the HUD's (choosing, its hero's picked), not a panel it might miss.
func _descend() -> void:
	if _coop.failed():
		return
	var me: int = _session.local_player
	await _wait(func() -> bool: return _depth > 0 or Unified.data.hud.choosing, STEP_S, "the boon choice opens")
	if _depth == 0 and Unified.data.hud.choosing and not _coop.hud_hero(me).picked:
		await _coop.press_action(&"interact")
	await _wait(func() -> bool: return _depth > 0, STEP_S, "the descent is confirmed")
	if not _coop.failed():
		_coop.step("the lift took the party and the hoard down: depth %d" % _depth)


## Whether `player`'s hero holds a handle of the hoard now, by the confirmed takes and let-gos.
func _holding(player: int) -> bool:
	return _grabbed.get(player, 0) > _dropped.get(player, 0)


## The let-gos so far, everyone's.
func _drops() -> int:
	return _dropped.values().reduce(func(sum: int, n: int) -> int: return sum + n, 0)


## The chest's long axis on the floor (its handles' line), its +X turned as the chest is, pointing east: `side` -1
## along it is the west end whichever way the chest came to rest (the heave's blast may turn it round), so the host
## always takes the end that leads west, toward the lift.
func _along(chest: Node3D) -> Vector3:
	var x: Vector3 = chest.global_basis.x
	var along: Vector3 = Vector3(x.x, 0.0, x.z).normalized()
	return along if along.x >= 0.0 else -along


## Counts the confirmed events the steps wait on.
func _count(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if state != UnifiedSession.EVENT_CONFIRMED:
		return
	if event is EventGate:
		_gate_open = _gate_open or (event as EventGate).open
	elif event is EventHoardGrabbed:
		var grabbed := event as EventHoardGrabbed
		_grabbed[grabbed.player] = _grabbed.get(grabbed.player, 0) + 1
	elif event is EventHoardDropped:
		var dropped := event as EventHoardDropped
		_dropped[dropped.player] = _dropped.get(dropped.player, 0) + 1
		_slipped += int(dropped.slipped)
	elif event is EventHeroRevived:
		var revived := event as EventHeroRevived
		_revived[revived.player] = _revived.get(revived.player, 0) + 1
	elif event is EventDescended:
		_depth = (event as EventDescended).depth


## What this side saw, for its result.
func _summary() -> Dictionary:
	return {"grabbed": _grabbed, "dropped": _dropped, "slipped": _slipped, "revived": _revived, "depth": _depth}


## Waits until `cond` holds, failing the run after `timeout_s` with "timed out: `what`", or at once when the session
## ends (the other side failed and left: nothing it waits on will come).
func _wait(cond: Callable, timeout_s: float, what: String) -> void:
	var end: int = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not _coop.failed():
		if cond.call():
			return
		if _lost():
			_coop.fail("the session ended while waiting: " + what)
			return
		if Time.get_ticks_msec() > end:
			_coop.fail("timed out (%.0f s): %s" % [timeout_s, what])
			return
		await _coop.frames(1)


## Whether the session is no longer connected (left, ended or failed).
func _lost() -> bool:
	return _session.status != UnifiedSession.STATUS_CONNECTED


## The other present player (0: none yet).
func _other() -> int:
	for player: int in _session.players:
		if player != _session.local_player:
			return player
	return 0


## Player `player`'s hero view (null: none).
func _hero(player: int) -> Node3D:
	return _session.get_player_view(EnumView.HERO, player) as Node3D


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
