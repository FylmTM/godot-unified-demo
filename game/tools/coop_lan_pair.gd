class_name CoopLanPair
extends RefCounted
## The two-player play the replay regression `simulation/tests/replays/lan_pair` records: `./uni coop --rerecord
## lan_pair` runs game/tools/coop.gd with `--play=lan_pair` (the folder's coop.args), and each side plays its part of
## the same script every time, on what the shared sim says (its confirmed events and the HUD), never on the clock:
##
##   1. a Knight host and a Barbarian joiner (both asked for Any) arrive;
##   2. each grabs the nearest free prop, carries it and throws it, twice;
##   3. the host grabs a third, raises RING skeletons round itself (a dev command) and throws it through their ring
##      until a thrown prop hits one;
##   4. both swing until a blow of each lands;
##   5. the joiner pauses the game for everyone and the host resumes it;
##   6. the host becomes a Mage and the joiner a Rogue (dev), each raises RANGED skeletons round itself, and attacks
##      until its bolt or crossbow shot lands;
##   7. the host kills every skeleton (dev) and is downed (dev);
##   8. both fight on until SURGES surges have risen; then the host leaves (UnifiedCoop).
##
## The suite's the_lan_recording_holds_its_play checks the recording holds every step, so a play that changes what
## it does fails there, and `uni coop --record` keeps no recording that fails it. Each step fails the run here first,
## with what didn't happen.

## How many skeletons the host raises round itself for its throw, and each side for its ranged attack.
const RING: int = 32
const RANGED: int = 8
## How many props each side throws before the ring, and how many surges the play waits for.
const THROWS: int = 2
const SURGES: int = 4
## How long a step may take before it fails the run (seconds): reaching a prop, a throw or an attack landing, the
## other side's part, and the surges (the fourth rises about a minute into the floor).
const REACH_S: float = 8.0
const LAND_S: float = 15.0
const OTHER_S: float = 40.0
const SURGES_S: float = 100.0
## How long a hero carries a prop before throwing it, and how long it aims each way while it attacks (seconds).
const CARRY_S: float = 0.6
const AIM_STEP_S: float = 0.4
## How long raised skeletons take to rise (seconds): the play waits that long before it strikes at them.
const RISE_S: float = 1.0
## How long a press (a grab, a throw) holds its button (seconds): several ticks, so the sampler sees it.
const PRESS_S: float = 0.1
## How near a prop the hero walks slowly (metres), and how far from the other hero a prop must be to be free (it may
## be carrying it).
const SLOW_WITHIN: float = 2.0
const OTHERS_PROP: float = 1.6

const MOVES: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]
const AIMS: Array[StringName] = [&"aim_left", &"aim_right", &"aim_up", &"aim_down"]

var _coop: UnifiedCoop
var _session: UnifiedSession
## Confirmed events, counted by player: grabs, throws, and hits keyed by "player:source" (EnumHitSource).
var _grabs: Dictionary[int, int] = {}
var _throws: Dictionary[int, int] = {}
var _hits: Dictionary[String, int] = {}
var _downed: Dictionary[int, int] = {}
var _pauses: Array[String] = []


func _init(coop: UnifiedCoop) -> void:
	_coop = coop
	_session = coop.session
	_session.sim_event.connect(_count)


## The host's part.
func host() -> void:
	var me: int = _session.local_player
	var friend: int = await _arrive(EnumClass.KNIGHT)
	await _throw_props(THROWS)
	if _coop.failed():
		return
	await _ring_throw()
	await _attack_until(EnumHitSource.BLOW, "the Knight's blow lands")
	await _coop.wait_for(func() -> bool: return _hit_count(friend, EnumHitSource.BLOW) > 0, OTHER_S,
		"the Barbarian's blow lands")
	await _coop.wait_for(func() -> bool: return Unified.data.hud.paused and Unified.data.hud.paused_by == friend,
		OTHER_S, "the joiner pauses for everyone")
	if _coop.failed():
		return
	_coop.step("the joiner paused for everyone")
	await _coop.seconds(1.0)
	_set_paused(false)
	await _coop.wait_for(func() -> bool: return not Unified.data.hud.paused, 3.0, "the host resumes it")
	_coop.step("the host resumed it")
	_set_class(EnumClass.MAGE)
	await _raise(RANGED)
	await _attack_until(EnumHitSource.BOLT, "the Mage's bolt lands")
	await _coop.wait_for(func() -> bool: return _hit_count(friend, EnumHitSource.CROSSBOW) > 0, OTHER_S,
		"the Rogue's shot lands")
	if _coop.failed():
		return
	_session.send_command(CommandDevKillMinions.new())
	await _coop.wait_for(func() -> bool: return _hit_count(me, EnumHitSource.DEV) > 0 and Unified.data.hud.minions == 0,
		5.0, "every skeleton killed")
	_coop.step("killed every skeleton: %d" % _hit_count(me, EnumHitSource.DEV))
	var hurt := CommandDevHurt.new()
	hurt.damage = 1000
	_session.send_command(hurt)
	await _coop.wait_for(func() -> bool: return _downed.get(me, 0) > 0, 5.0, "the host is downed")
	_coop.step("the host was downed")
	await _fight_until_surges()
	_coop.result["lan_pair"] = _summary()


## The joiner's part.
func join() -> void:
	var friend: int = await _arrive(EnumClass.BARBARIAN)
	await _throw_props(THROWS)
	await _coop.wait_for(func() -> bool: return Unified.data.hud.minions > 0, OTHER_S, "the host raises its ring")
	if _coop.failed():
		return
	await _attack_until(EnumHitSource.BLOW, "the Barbarian's blow lands", friend)
	await _coop.wait_for(func() -> bool: return _hit_count(friend, EnumHitSource.BLOW) > 0, OTHER_S,
		"the Knight's blow lands")
	if _coop.failed():
		return
	_set_paused(true)
	await _coop.wait_for(func() -> bool: return Unified.data.hud.paused, 3.0, "the joiner pauses for everyone")
	_coop.step("paused for everyone")
	await _coop.wait_for(func() -> bool: return not Unified.data.hud.paused, OTHER_S, "the host resumes it")
	_coop.step("the host resumed it")
	_set_class(EnumClass.ROGUE)
	await _raise(RANGED)
	await _attack_until(EnumHitSource.CROSSBOW, "the Rogue's shot lands")
	await _coop.wait_for(func() -> bool: return _downed.get(friend, 0) > 0, OTHER_S, "the host is downed")
	_coop.step("the host was downed")
	await _fight_until_surges()
	_coop.result["lan_pair"] = _summary()


## Both heroes in; this side plays `wanted` (both asked for Any: the host gets the first class, the joiner the next).
## Returns the other player.
func _arrive(wanted: int) -> int:
	await _coop.wait_for(func() -> bool:
		return _hero(_session.local_player) != null and _other() != 0 and _hero(_other()) != null, 20.0,
		"both heroes in")
	var friend: int = _other()
	var mine: int = Heroes.class_of(_session.local_player)
	_coop.expect(mine == wanted, "this side plays the %s: %s" % [Heroes.name_of(wanted), Heroes.name_of(mine)])
	_coop.step("%s in, the friend's %s too" % [Heroes.name_of(mine), Heroes.name_of(Heroes.class_of(friend))])
	return friend


## Grabs the nearest free prop, carries it and throws it, `count` times.
func _throw_props(count: int) -> void:
	var me: int = _session.local_player
	for i: int in count:
		var thrown: int = _throws.get(me, 0)
		await _grab()
		await _coop.seconds(CARRY_S)
		_steer(Vector2.ZERO)
		await _coop.hold(&"attack", PRESS_S)
		await _coop.wait_for(func() -> bool: return _throws.get(me, 0) > thrown, 3.0, "the prop is thrown")
		if _coop.failed():
			return
		_coop.step("threw a prop (%d)" % _throws.get(me, 0))


## The host's third prop through the ring it raises: grabbed, RING skeletons risen round it, thrown; again with the
## nearest prop until a thrown prop hits one.
func _ring_throw() -> void:
	var me: int = _session.local_player
	await _grab()
	if _coop.failed():
		return
	await _raise(RING)
	var end: int = Time.get_ticks_msec() + int(LAND_S * 1000.0)
	while not _coop.failed() and _hit_count(me, EnumHitSource.PROP) == 0:
		if _held() == 0:
			await _grab()
		var thrown: int = _throws.get(me, 0)
		await _coop.hold(&"attack", PRESS_S)
		await _until(func() -> bool: return _throws.get(me, 0) > thrown, 2.0)
		await _until(func() -> bool: return _hit_count(me, EnumHitSource.PROP) > 0, 1.5)
		if Time.get_ticks_msec() > end:
			_coop.fail("no thrown prop hit a skeleton of the ring")
	_coop.step("threw a prop through the ring of %d: it hit one" % RING)


## Raises `count` skeletons round this side's hero (a dev command) and waits for them to rise.
func _raise(count: int) -> void:
	var raise := CommandDevSpawnMinions.new()
	raise.count = count
	_session.send_command(raise)
	await _coop.wait_for(func() -> bool: return Unified.data.hud.minions >= count, 5.0, "%d skeletons rise" % count)
	await _coop.seconds(RISE_S)
	_coop.step("raised %d skeletons (dev)" % count)


## Attacks (held), aiming round the eight directions, until this side's hit of `source` is confirmed; with `toward`, it
## walks to that player's hero first (the host, whom the ring surrounds).
func _attack_until(source: int, what: String, toward: int = 0) -> void:
	var me: int = _session.local_player
	Input.action_press(&"attack")
	var end: int = Time.get_ticks_msec() + int(LAND_S * 1000.0)
	var turn: int = 0
	while not _coop.failed() and _hit_count(me, source) == 0:
		if Time.get_ticks_msec() > end:
			_coop.fail("timed out: %s (%d skeletons up)" % [what, Unified.data.hud.minions])
			break
		var gap: Vector2 = _floor_to(_hero(toward)) if toward != 0 else Vector2.ZERO
		_steer(gap.normalized() if gap.length() > 2.0 else Vector2.ZERO)
		_aim(Vector2.from_angle(turn * TAU / 8.0))
		turn += 1
		await _coop.seconds(AIM_STEP_S)
	Input.action_release(&"attack")
	_steer(Vector2.ZERO)
	_aim(Vector2.ZERO)
	if not _coop.failed():
		_coop.step(what)


## Holds Attack, aiming round, until SURGES surges have risen.
func _fight_until_surges() -> void:
	Input.action_press(&"attack")
	var turn: int = 0
	var end: int = Time.get_ticks_msec() + int(SURGES_S * 1000.0)
	while not _coop.failed() and Unified.data.hud.surges < SURGES:
		if Time.get_ticks_msec() > end:
			_coop.fail("timed out: %d surges (%d)" % [SURGES, Unified.data.hud.surges])
			break
		_aim(Vector2.from_angle(turn * TAU / 8.0))
		turn += 1
		await _coop.seconds(AIM_STEP_S)
	Input.action_release(&"attack")
	_aim(Vector2.ZERO)
	if not _coop.failed():
		_coop.step("%d surges risen" % Unified.data.hud.surges)


## Walks to the nearest free prop that isn't a heavy crate (it slows its carrier) until the hands would grab it (its
## view is highlighted), then grabs it; the next nearest when one stays out of reach.
func _grab() -> void:
	var me: int = _session.local_player
	var grabbed: int = _grabs.get(me, 0)
	var tried: Array[PropView] = []
	while not _coop.failed() and _grabs.get(me, 0) == grabbed:
		var prop: PropView = _nearest_prop(tried)
		if prop == null:
			_coop.fail("no prop left in reach")
			return
		tried.append(prop)
		var end: int = Time.get_ticks_msec() + int(REACH_S * 1000.0)
		while Time.get_ticks_msec() < end and not _aimed(prop) and not _coop.failed():
			var gap: Vector2 = _floor_to(prop)
			_steer(gap.normalized() * (0.5 if gap.length() < SLOW_WITHIN else 1.0))
			await _coop.frames(1)
		_steer(Vector2.ZERO)
		if _aimed(prop):
			await _coop.hold(&"interact", PRESS_S)
			await _until(func() -> bool: return _grabs.get(me, 0) > grabbed, 1.0)
	_coop.step("grabbed a prop (%d)" % _grabs.get(me, 0))


## Whether this side's hands would grab `prop` now (its view is highlighted; false once its view is pooled).
func _aimed(prop: PropView) -> bool:
	return prop.data != null and prop.data.aimed


## Waits until `cond` holds or `timeout_s` passes, without failing the run: whether it held.
func _until(cond: Callable, timeout_s: float) -> bool:
	var end: int = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not _coop.failed() and Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await _coop.frames(1)
	var held: bool = cond.call()
	return held


## The nearest prop view, by the floor, that no hero is carrying and isn't in `skip` (null: none).
func _nearest_prop(skip: Array[PropView]) -> PropView:
	var other: Node3D = _hero(_other())
	var best: PropView = null
	var best_d: float = INF
	for node: Node in _coop.views(EnumView.PROP):
		var prop: PropView = node as PropView
		if prop == null or prop.data == null or prop.data.kind == EnumPropKind.HEAVY_CRATE or prop in skip:
			continue
		if other != null and _floor(prop.global_position - other.global_position).length() < OTHERS_PROP:
			continue
		var d: float = _floor_to(prop).length()
		if d < best_d:
			best_d = d
			best = prop
	return best


## The prop this side's hero holds, by its grabs and throws so far (0: none).
func _held() -> int:
	var me: int = _session.local_player
	return _grabs.get(me, 0) - _throws.get(me, 0)


## The move actions pushed along `dir` on the floor (x, z): the keyboard's or a stick's.
func _steer(dir: Vector2) -> void:
	_push(MOVES, dir)


## The aim actions pushed along `dir` (zero: the hero faces its move).
func _aim(dir: Vector2) -> void:
	_push(AIMS, dir)


func _push(actions: Array[StringName], dir: Vector2) -> void:
	var strengths: Array[float] = [maxf(-dir.x, 0.0), maxf(dir.x, 0.0), maxf(-dir.y, 0.0), maxf(dir.y, 0.0)]
	for i: int in actions.size():
		if strengths[i] > 0.0:
			Input.action_press(actions[i], strengths[i])
		else:
			Input.action_release(actions[i])


func _set_paused(paused: bool) -> void:
	var command := CommandSetPaused.new()
	command.paused = paused
	_session.send_command(command)


func _set_class(hero_class: int) -> void:
	var command := CommandDevSetClass.new()
	command.class = hero_class
	_session.send_command(command)
	_coop.step("became the %s (dev)" % Heroes.name_of(hero_class))


## Counts the confirmed events the steps wait on.
func _count(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if state != UnifiedSession.EVENT_CONFIRMED:
		return
	if event is EventPropGrabbed:
		var grabbed := event as EventPropGrabbed
		_grabs[grabbed.player] = _grabs.get(grabbed.player, 0) + 1
	elif event is EventPropThrown:
		var thrown := event as EventPropThrown
		_throws[thrown.player] = _throws.get(thrown.player, 0) + 1
	elif event is EventMinionHit:
		var hit := event as EventMinionHit
		var key: String = "%d:%d" % [hit.player, hit.source]
		_hits[key] = _hits.get(key, 0) + 1
	elif event is EventHeroDowned:
		var downed := event as EventHeroDowned
		_downed[downed.player] = _downed.get(downed.player, 0) + 1
	elif event is EventPaused:
		var paused := event as EventPaused
		_pauses.append("%s by %d" % ["paused" if paused.paused else "resumed", paused.player])


func _hit_count(player: int, source: int) -> int:
	return _hits.get("%d:%d" % [player, source], 0)


## What this side saw, for its result.
func _summary() -> Dictionary:
	return {"grabs": _grabs, "throws": _throws, "hits": _hits, "downed": _downed, "pauses": _pauses,
		"surges": Unified.data.hud.surges}


## The other present player (0: none yet).
func _other() -> int:
	for player: int in _session.players:
		if player != _session.local_player:
			return player
	return 0


## Player `player`'s hero view (null: none).
func _hero(player: int) -> Node3D:
	return _session.get_player_view(EnumView.HERO, player) as Node3D


## From this side's hero to `target` on the floor (x, z); zero when either is missing.
func _floor_to(target: Node3D) -> Vector2:
	var mine: Node3D = _hero(_session.local_player)
	if mine == null or target == null:
		return Vector2.ZERO
	return _floor(target.global_position - mine.global_position)


func _floor(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
