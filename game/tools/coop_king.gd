class_name CoopKing
extends RefCounted
## The two-player play the replay regression `simulation/tests/replays/king` records: `./uni coop --rerecord king` runs
## game/tools/coop.gd with `--play=king` (the folder's coop.args: the vault as the game's floor, `--setup floor=vault`,
## on a bad link, `--lag 150`), and each side plays its part of the King's fight on what the shared sim says (its
## confirmed events and the HUD), never on the clock:
##
##   1. a Knight host and a Barbarian joiner (both asked for Any) arrive in the vault; from then on the host fells the
##      skeletons the King's stages raise and stands up a downed hero (dev: the play is the King, not its crowd);
##   2. the host wakes the King and drives it into its second stage (dev): its braziers go out and its ward goes up;
##   3. the two break the ward together, each kindling its braziers (the host two, the joiner one) until the lighting is
##      confirmed;
##   4. both fight the King until it slams, the braziers burning;
##   5. the host drives it into its third stage (dev), and the two break its ward again;
##   6. the host takes it to its last few hit points and breaks its guard (dev), and both strike until it falls.
##
## The suite's the_king_recording_holds_its_play checks the recording holds every step, so a play that changes what it
## does fails there, and `uni coop --record` keeps no recording that fails it. Each step fails the run here first, with
## what didn't happen, and every wait fails at once when the session ends (the other side failed and left).

## The vault's braziers each side kindles, by marker order (game/levels/vault.tscn: the host the east two, the joiner
## the south-west one): three, the ward's need with two heroes.
const HOST_BRAZIERS: Array[int] = [3, 1]
const JOINER_BRAZIERS: Array[int] = [2]
## The King's last hit points, left by the host's dev blow for the heroes' own (a Knight's blow is 18, a Barbarian's
## 30).
const LAST_HP: int = 40
## How near the King a hero walks to strike it (metres from its centre: inside a blow's reach and the King's radius),
## how often the host breaks its guard again in the end (seconds: inside BOSS_GUARD_DOWN_S), and how often its keeper
## runs (often: a skeleton the King's stage raised breaks a kindling off with a blow).
const STRIKE_WITHIN: float = 2.2
const GUARD_EVERY_S: float = 3.0
const KEEP_S: float = 0.5
## How long a step may take before it fails the run (seconds): the first slam comes BOSS_SLAM_EVERY_S after the ward
## breaks, and the host's two braziers are the width of the vault apart.
const STEP_S: float = 60.0

var _coop: CryptCoop
var _session: UnifiedSession
## Confirmed events: braziers lit by player, the ward's breaks, the King's slams, and its fall.
var _lit: Dictionary[int, int] = {}
var _breaks: int = 0
var _slams: int = 0
var _fallen: bool = false
## Whether the host's keeper still runs (until the King falls).
var _keeping: Array[bool] = [true]


func _init(coop: CryptCoop) -> void:
	_coop = coop
	_session = coop.session
	_session.sim_event.connect(coop.count_beats)  # the kindling's tallies
	_session.sim_event.connect(_count)


## The host's part: the Knight, the dev blows.
func host() -> void:
	await _arrive(EnumClass.KNIGHT)
	_keep()  # not awaited: it runs beside the play, until the King falls
	var wake := CommandDevHurtElites.new()
	wake.damage = 1
	_session.send_command(wake)
	await _wait(func() -> bool: return Unified.data.hud.boss_hp_max > 0, STEP_S, "the King wakes")
	_drive()
	await _break_ward(2, HOST_BRAZIERS)
	await _fight_until(func() -> bool: return _slams > 0, "the King slams, the braziers lit")
	_drive()
	await _break_ward(3, HOST_BRAZIERS)
	if not _coop.failed():
		_coop.step("took the King to its last %d hit points and broke its guard (dev)" % LAST_HP)
	var blow := CommandDevHurtElites.new()
	blow.damage = Unified.data.hud.boss_hp - LAST_HP
	_session.send_command(blow)
	_break_guard()  # not awaited: again and again, until the King falls
	await _fight_until(func() -> bool: return _fallen, "the King falls")
	_keeping[0] = false
	_coop.result["king"] = _summary()


## The joiner's part: the Barbarian.
func join() -> void:
	await _arrive(EnumClass.BARBARIAN)
	await _break_ward(2, JOINER_BRAZIERS)
	await _fight_until(func() -> bool: return _slams > 0, "the King slams, the braziers lit")
	await _break_ward(3, JOINER_BRAZIERS)
	await _fight_until(func() -> bool: return _fallen, "the King falls")
	_coop.result["king"] = _summary()


## Both heroes in; this side plays `wanted` (both asked for Any: the host gets the first class, the joiner the next).
func _arrive(wanted: int) -> void:
	await _wait(func() -> bool:
		return _hero(_session.local_player) != null and _other() != 0 and _hero(_other()) != null, 20.0,
		"both heroes in")
	var mine: int = Heroes.class_of(_session.local_player)
	_coop.expect(mine == wanted, "this side plays the %s: %s" % [Heroes.name_of(wanted), Heroes.name_of(mine)])
	_coop.expect(_king() != null, "the King is in the vault")
	_coop.step("%s in the vault, the friend's %s too" % [Heroes.name_of(mine), Heroes.name_of(Heroes.class_of(_other()))])


## Waits for the King warded in `stage`, kindles this side's `braziers` (marker order) and waits for the ward to break,
## CONFIRMED.
func _break_ward(stage: int, braziers: Array[int]) -> void:
	await _wait(func() -> bool: return Unified.data.hud.boss_stage == stage and Unified.data.hud.boss_warded, STEP_S,
		"the King warded in its stage %d" % stage)
	var breaks: int = _breaks
	var lit: int = _lit.get(_session.local_player, 0)
	var stands: Array[Node3D] = _coop.markers("brazier")
	for index: int in braziers:
		if index < stands.size():
			await _coop.kindle(stands[index].global_position)
	await _wait(func() -> bool: return _breaks > breaks, STEP_S, "the ward breaks, CONFIRMED")
	if not _coop.failed():
		_coop.step("broke the King's ward in its stage %d together: %d braziers lit here" % [stage,
			_lit.get(_session.local_player, 0) - lit])


## Walks at the King and strikes it (Attack held, aimed at it) until `done` holds.
func _fight_until(done: Callable, what: String) -> void:
	if _coop.failed():
		return
	Input.action_press(&"attack")
	var until: int = Time.get_ticks_msec() + int(STEP_S * 1000.0)
	while not _coop.failed() and not done.call():
		if _lost() or Time.get_ticks_msec() > until:
			_coop.fail("timed out: " + what)
			break
		var king: Node3D = _king()
		var mine: Node3D = _hero(_session.local_player)
		var gap: Vector2 = _flat(king.global_position - mine.global_position) if king != null and mine != null \
			else Vector2.ZERO
		_coop.steer(gap, 1.0 if gap.length() > STRIKE_WITHIN else 0.0)
		_aim(gap.normalized())
		await _coop.frames(1)
	Input.action_release(&"attack")
	_coop.steer(Vector2.ZERO, 0.0)
	_aim(Vector2.ZERO)
	if not _coop.failed():
		_coop.step(what)


## A blow at the King for its whole health (dev: a blow never takes it past its stage's end): it roars into its next
## stage, warded.
func _drive() -> void:
	if _coop.failed():
		return
	var stage: int = Unified.data.hud.boss_stage
	_coop.drive_king()
	_coop.step("drove the King on from its stage %d (dev)" % stage)


## The host's keeper, while `_keeping[0]` holds: every KEEP_S it fells the skeletons (dev) and stands up any hero down
## (a dev revive), so no wipe starts the vault over.
func _keep() -> void:
	while _keeping[0] and not _coop.failed():
		_session.send_command(CommandDevKillMinions.new())
		if _coop.down(_session.local_player) or _coop.down(_other()):
			_session.send_command(CommandDevRevive.new())
		await _coop.seconds(KEEP_S)


## Breaks the King's guard (dev) every GUARD_EVERY_S until it falls: the heroes' blows land whole.
func _break_guard() -> void:
	while not _fallen and not _coop.failed():
		_session.send_command(CommandDevBreakGuards.new())
		await _coop.seconds(GUARD_EVERY_S)


## The aim actions pushed along `dir` (zero: the hero faces its move).
func _aim(dir: Vector2) -> void:
	var actions: Array[StringName] = [&"aim_left", &"aim_right", &"aim_up", &"aim_down"]
	var strengths: Array[float] = [maxf(-dir.x, 0.0), maxf(dir.x, 0.0), maxf(-dir.y, 0.0), maxf(dir.y, 0.0)]
	for i: int in actions.size():
		if strengths[i] > 0.0:
			Input.action_press(actions[i], strengths[i])
		else:
			Input.action_release(actions[i])


## The King's view (null: none, or fallen).
func _king() -> Node3D:
	var elites: Array[Node] = _session.get_views(EnumView.ELITE)
	return null if elites.is_empty() else elites[0] as Node3D


## Counts the confirmed events the steps wait on.
func _count(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if state != UnifiedSession.EVENT_CONFIRMED:
		return
	if event is EventBrazier and (event as EventBrazier).lit:
		var brazier := event as EventBrazier
		_lit[brazier.player] = _lit.get(brazier.player, 0) + 1
	elif event is EventBossWard and not (event as EventBossWard).up:
		_breaks += 1
	elif event is EventBossSlam:
		_slams += 1
	elif event is EventBossDefeated:
		_fallen = true


## What this side saw, for its result.
func _summary() -> Dictionary:
	return {"lit": _lit, "breaks": _breaks, "slams": _slams, "fallen": _fallen}


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
