class_name Effects
extends Node3D
## The play scene's effects of the sim's events: sparks, puffs, bursts, rings, decals and light pulses. The play scene
## hands it every event in each of its states (on_event), and the event-state rule decides what shows when:
##
## - Instant (under half a second, leaving nothing: sparks, puffs, bursts, the slam's shock ring, a short light pulse)
##   plays on EMITTED, as soon as the event is predicted, and is never undone: one a rollback takes back has already
##   played, which an effect can afford, and one shown late would look worse.
## - Lingering (a decal, a light pulse longer than LINGER_S) also starts on EMITTED, remembered by the event's id: its
##   CANCELLED fades it out in CANCEL_FADE_S (cancel), its CONFIRMED forgets the id (forget), so it runs its course.
## - News (the revive's rising stars) waits for CONFIRMED: a revive a rollback undid would have celebrated nothing.
##
## What lasts as long as a state does (a charge's dust, a lit brazier's smoke, the vault's ambient) is no event's: the
## views and Lighting show it from view data.
##
## Each one-shot kind is a pool of its scene (game/fx/), taken in turn (the oldest goes first), so a fight's hundreds
## of hits make no node. Budgets keep a crowd's death from costing a frame: at most STARTS_PER_FRAME new ones of a kind
## a frame (one within MERGE_DISTANCE of one already started this frame merges into it, later ones are dropped), at
## most EMITTING_MAX nodes and PARTICLES_MAX particles playing, DECALS decals and PULSES light pulses (unshadowed, each
## taking the oldest's place). Its decals, rings, pulses and tracers move by its own clock (advance), which the play
## scene's frames run and a check steps by hand.

## The kinds of one-shot particles, each a pool of its scene.
enum Kind { SPARKS, BURST, DUST, FIREBALL, GLINT, BONE_PUFF, BONE_BURST, DUST_RING, SMOKE, EMBERS, STARS, SLAM_DUST }
## What a slot shows.
enum Shows { DECAL, PULSE, RING, TRACER }

## How many of a kind start in one frame at most (later ones are dropped), and how near (metres) a later one merges
## into one already started this frame: a cleave through a packed crowd sparks once a body's width, not a hundred times.
const STARTS_PER_FRAME: int = 8
const MERGE_DISTANCE: float = 1.0
## How many one-shot nodes, and particles (their scenes' amounts), play at once at most: a new one past either is
## dropped.
const EMITTING_MAX: int = 96
const PARTICLES_MAX: int = 3000
## Each kind's pool, by Kind: room for STARTS_PER_FRAME a frame over its lifetime where a crowd sets it off, fewer where
## one event at a time does.
const POOL_SIZES: Array[int] = [32, 16, 24, 8, 16, 32, 8, 8, 8, 8, 8, 4]
## How many decals, light pulses, shock rings and tracers show at once, each new one taking the oldest's place.
const DECALS: int = 8
const PULSES: int = 8
const RINGS: int = 4
const TRACERS: int = 16
## A light pulse longer than this (seconds) lingers: it is undone when its event is cancelled.
const LINGER_S: float = 0.3
## How fast a cancelled event's lingering effect fades out (seconds).
const CANCEL_FADE_S: float = 0.08
## How long a tracer takes to fade, in seconds.
const TRACER_FADE_S: float = 0.15

## Where on a skeleton its hit's sparks fly from and its bones puff from, above its feet.
const HIT_HEIGHT: float = 1.1
const BONE_HEIGHT: float = 0.8
## Where on an elite its hit's sparks fly from, above its feet (a Warrior's shield, struck).
const ELITE_HIT_HEIGHT: float = 1.3
## A prop landing faster than this (metres per second) raises dust.
const DUST_SPEED: float = 5.0
## Where a picked-up coin's glint shines from, above where it lay (its hover: game/views/coin.gdshader).
const GLINT_HEIGHT: float = 0.4
## A brazier's bowl above its foot (the stand: game/levels/parts/crypt/brazier.tscn), where its embers rise from.
const BOWL_HEIGHT: float = 3.0
## A flash's light above the floor where it bursts.
const FLASH_HEIGHT: float = 1.2
## A fireball's blast: its flash (a short pulse: seconds, colour, energy, reach in metres) and its scorch on the floor.
const FIREBALL_FLASH_S: float = 0.2
const FIREBALL_FLASH: Color = Color(1.0, 0.6, 0.3)
const FIREBALL_FLASH_ENERGY: float = 5.0
const FIREBALL_FLASH_RANGE: float = 8.0
const SCORCH_S: float = 6.0
const SCORCH_SIZE: float = 3.2
const SCORCH_TINT: Color = Color(0.05, 0.04, 0.035, 0.85)
## The King's slam: its shock ring spreads from SHOCK_START to SHOCK_RADIUS metres in SHOCK_S, and leaves a crack.
const SHOCK_START: float = 0.6
const SHOCK_RADIUS: float = 5.0
const SHOCK_S: float = 0.4
const CRACK_S: float = 5.0
const CRACK_SIZE: float = 5.0
const CRACK_TINT: Color = Color(0.03, 0.025, 0.02, 0.9)
## How long a decal takes to fade at the end of its life (seconds).
const DECAL_FADE_S: float = 1.5
## How deep a decal's box reaches, half above the floor and half below (metres): the floor, not who stands on it.
const DECAL_DEPTH: float = 1.0
## The King's fall: three bone bursts round where it fell (offsets from its feet) and a long pale flash.
const BOSS_BURSTS: Array[Vector3] = [Vector3(0, 1.6, 0), Vector3(-0.9, 0.8, 0.5), Vector3(0.9, 0.8, -0.5)]
const BOSS_FLASH_S: float = 0.8
const BOSS_FLASH: Color = Color(1.0, 0.86, 0.62)
const BOSS_FLASH_ENERGY: float = 4.0
const BOSS_FLASH_RANGE: float = 12.0

## The one-shot kinds' scenes (game/fx/), one per Kind.
@export var sparks_scene: PackedScene
@export var burst_scene: PackedScene
@export var dust_scene: PackedScene
@export var fireball_scene: PackedScene
@export var glint_scene: PackedScene
@export var bone_puff_scene: PackedScene
@export var bone_burst_scene: PackedScene
@export var dust_ring_scene: PackedScene
@export var smoke_scene: PackedScene
@export var embers_scene: PackedScene
@export var stars_scene: PackedScene
@export var slam_dust_scene: PackedScene
## The crossbow's tracer (a glowing beam along its -Z, a metre long).
@export var tracer_scene: PackedScene
## The decals' textures (white, their alpha the shape): a fireball's scorch, the slam's crack.
@export var scorch_texture: Texture2D
@export var crack_texture: Texture2D
## The shock ring's material (game/fx/ground_ring.gdshader).
@export var ring_material: Material

## Its own clock (seconds): what its decals, rings, pulses and tracers move by.
var _clock: float = 0.0
var _pools: Array[Pool] = []
## The frame the starts were counted for, and how many one-shot nodes and particles play.
var _frame: int = -1
var _live_nodes: int = 0
var _live_particles: int = 0
var _decals: Array[Slot] = []
var _pulses: Array[Slot] = []
var _rings: Array[Slot] = []
var _tracers: Array[Slot] = []
## What an event may leave lingering (the decals and pulses), and every slot.
var _lingering: Array[Slot] = []
var _slots: Array[Slot] = []


func _ready() -> void:
	var scenes: Array[PackedScene] = [
		sparks_scene, burst_scene, dust_scene, fireball_scene, glint_scene, bone_puff_scene, bone_burst_scene,
		dust_ring_scene, smoke_scene, embers_scene, stars_scene, slam_dust_scene,
	]
	for kind: int in scenes.size():
		_pools.append(_pool(scenes[kind], POOL_SIZES[kind]))
	for _i: int in DECALS:
		_decals.append(_slot(Decal.new(), Shows.DECAL))
	for _i: int in PULSES:
		var light := OmniLight3D.new()
		light.shadow_enabled = false
		_pulses.append(_slot(light, Shows.PULSE))
	var quad := PlaneMesh.new()
	quad.size = Vector2(2, 2)
	for _i: int in RINGS:
		var ring := MeshInstance3D.new()
		ring.mesh = quad
		ring.material_override = ring_material
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rings.append(_slot(ring, Shows.RING))
	for _i: int in TRACERS:
		_tracers.append(_slot(tracer_scene.instantiate() as Node3D, Shows.TRACER))
	_lingering.append_array(_decals)
	_lingering.append_array(_pulses)


func _process(delta: float) -> void:
	advance(delta)


## The effects of `event` in `state` (the session's sim_event), by the event-state rule (the file's header).
func on_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if state == UnifiedSession.EVENT_CANCELLED:
		cancel(event.id)
	elif state == UnifiedSession.EVENT_CONFIRMED:
		forget(event.id)
		if event is EventHeroRevived:
			play(Kind.STARS, (event as EventHeroRevived).position)
	else:
		_on_emitted(event)


## Fades out what the event `id` left lingering (its decals and long light pulses) in CANCEL_FADE_S: its event was
## cancelled. An instant effect it started plays on.
func cancel(id: int) -> void:
	for slot: Slot in _lingering:
		if slot.id == id and slot.lingers and not slot.settled and slot.cancelled_at < 0.0 and slot.life > 0.0:
			slot.cancel_from = _strength(slot)
			slot.cancelled_at = _clock


## Forgets the event `id`: it was confirmed, so what it left runs its course.
func forget(id: int) -> void:
	for slot: Slot in _lingering:
		if slot.id == id:
			slot.settled = true


## Plays one-shot `kind` at `at`, within the budgets (the file's header): false when it merged into one of this
## frame's, or was dropped.
func play(kind: Kind, at: Vector3) -> bool:
	_count_frame()
	var pool: Pool = _pools[kind]
	if pool.started >= STARTS_PER_FRAME:
		return false
	for spot: Vector3 in pool.spots:
		if spot.distance_squared_to(at) < MERGE_DISTANCE * MERGE_DISTANCE:
			return false
	var replaces_live: bool = pool.ends[pool.next] > _clock
	if not replaces_live and (_live_nodes >= EMITTING_MAX or _live_particles + pool.amount > PARTICLES_MAX):
		return false
	pool.ends[pool.next] = _clock + pool.lifetime
	var particles: GPUParticles3D = pool.take()
	particles.visible = true
	particles.global_position = at
	particles.restart()
	pool.started += 1
	pool.spots.append(at)
	if not replaces_live:
		_live_nodes += 1
		_live_particles += pool.amount
	return true


## How many of `kind` play now.
func playing(kind: Kind) -> int:
	var count: int = 0
	for end: float in _pools[kind].ends:
		if end > _clock:
			count += 1
	return count


## A fireball's scorch on the floor at `at`, lingering SCORCH_S for the event `id`.
func scorch(at: Vector3, id: int) -> void:
	_decal(at, id, scorch_texture, SCORCH_TINT, SCORCH_SIZE, SCORCH_S)


## The slam's crack in the floor at `at`, lingering CRACK_S for the event `id`.
func crack(at: Vector3, id: int) -> void:
	_decal(at, id, crack_texture, CRACK_TINT, CRACK_SIZE, CRACK_S)


## A light pulse at `at` dying away over `seconds` (`energy` at first, reaching `reach` metres): one longer than
## LINGER_S lingers for the event `id`.
func pulse(at: Vector3, color: Color, energy: float, reach: float, seconds: float, id: int) -> void:
	var slot: Slot = _take(_pulses, id, seconds)
	slot.lingers = seconds > LINGER_S
	slot.peak = energy
	var light: OmniLight3D = slot.node as OmniLight3D
	light.global_position = at
	light.light_color = color
	light.omni_range = reach
	_show(slot)


## The slam's shock ring at `at`, on the floor: it spreads to SHOCK_RADIUS over SHOCK_S, fading.
func shock_ring(at: Vector3) -> void:
	var slot: Slot = _take(_rings, 0, SHOCK_S)
	slot.node.global_position = at + Vector3(0, 0.06, 0)
	_show(slot)


## A crossbow's tracer from `from` to `to`, fading over TRACER_FADE_S.
func tracer(from: Vector3, to: Vector3) -> void:
	var length: float = from.distance_to(to)
	if length < 0.01:
		return
	var slot: Slot = _take(_tracers, 0, TRACER_FADE_S)
	slot.node.look_at_from_position((from + to) / 2.0, to, Vector3.UP)
	slot.node.scale = Vector3(1, 1, length)
	_show(slot)


## How strongly what the event `id` left lingering shows now (0: nothing, 1: fully): its decal or its pulse.
func shown(id: int) -> float:
	var most: float = 0.0
	for slot: Slot in _lingering:
		if slot.id == id and slot.lingers and slot.life > 0.0:
			most = maxf(most, _strength(slot))
	return most


## Moves the decals, rings, pulses and tracers on by `delta` seconds of its clock: the play scene's frames call it,
## and a check, by hand.
func advance(delta: float) -> void:
	_clock += delta
	for slot: Slot in _slots:
		if slot.life > 0.0:
			_show(slot)


## Ends every effect at once: the level changed (what a floor showed has no place on the next), or the look-dev scene
## sets a new shot.
func clear() -> void:
	for pool: Pool in _pools:
		for index: int in pool.nodes.size():
			var particles: GPUParticles3D = pool.nodes[index]
			particles.visible = false
			particles.emitting = false
			particles.speed_scale = 1.0
			particles.preprocess = 0.0
			pool.ends[index] = 0.0
	for slot: Slot in _slots:
		slot.life = 0.0
		slot.node.visible = false
	_frame = -1
	set_process(true)


## Holds every effect playing at `fraction` of its life, and nothing moves on until clear(): the look-dev scene's
## frozen sheets of effects.
func hold_at(fraction: float) -> void:
	set_process(false)
	for pool: Pool in _pools:
		for index: int in pool.nodes.size():
			if pool.ends[index] > _clock:
				var particles: GPUParticles3D = pool.nodes[index]
				particles.preprocess = particles.lifetime * fraction
				particles.speed_scale = 0.0
				particles.restart()
	for slot: Slot in _slots:
		if slot.life > 0.0:
			slot.born = _clock - slot.life * fraction
			_show(slot)


func _on_emitted(event: UnifiedEvent) -> void:
	if event is EventMinionHit:
		play(Kind.SPARKS, (event as EventMinionHit).position + Vector3(0, HIT_HEIGHT, 0))
	elif event is EventMinionDied:
		play(Kind.BONE_PUFF, (event as EventMinionDied).position + Vector3(0, BONE_HEIGHT, 0))
	elif event is EventBoltBurst:
		var bolt := event as EventBoltBurst
		play(Kind.SPARKS if bolt.bone else Kind.BURST, bolt.position)  # a skeleton Mage's: bone splinters
	elif event is EventCrossbowShot:
		var shot := event as EventCrossbowShot
		var shooter := Unified.session.get_player_view(EnumView.HERO, shot.player) as HeroView
		tracer(shooter.weapon_position() if shooter != null else shot.from, shot.to)
	elif event is EventPropImpact:
		var impact := event as EventPropImpact
		if impact.speed >= DUST_SPEED:
			play(Kind.DUST, impact.position)
	# the abilities
	elif event is EventBlocked:
		play(Kind.SPARKS, (event as EventBlocked).position)
	elif event is EventFireballBurst:
		var blast: Vector3 = (event as EventFireballBurst).position
		play(Kind.FIREBALL, blast)
		play(Kind.SMOKE, blast)
		pulse(blast + Vector3(0, FLASH_HEIGHT, 0), FIREBALL_FLASH, FIREBALL_FLASH_ENERGY, FIREBALL_FLASH_RANGE,
			FIREBALL_FLASH_S, event.id)
		scorch(blast, event.id)
	elif event is EventHeaveLanded:
		play(Kind.DUST_RING, (event as EventHeaveLanded).position)
	# Elites
	elif event is EventEliteHit:
		play(Kind.SPARKS, (event as EventEliteHit).position + Vector3(0, ELITE_HIT_HEIGHT, 0))
	elif event is EventGuardBroken:
		var broken := event as EventGuardBroken
		play(Kind.SPARKS, broken.position + Vector3(0, ELITE_HIT_HEIGHT, 0))
		play(Kind.DUST, broken.position)
	elif event is EventEliteDied:
		var died := event as EventEliteDied
		play(Kind.BONE_BURST, died.position + Vector3(0, BONE_HEIGHT, 0))
		play(Kind.DUST_RING, died.position)
	# Loot
	elif event is EventLootCollected:
		play(Kind.GLINT, (event as EventLootCollected).position + Vector3(0, GLINT_HEIGHT, 0))
	# Mechanisms: a gate shutting (dust at its foot), a barricade breaking, the deck at the shaft's bottom
	elif event is EventGate:
		var gate := event as EventGate
		if not gate.open:
			play(Kind.DUST, Vector3(gate.position.x, 0, gate.position.z))
	elif event is EventBarricadeBroken:
		play(Kind.DUST, (event as EventBarricadeBroken).position)
	elif event is EventLift and (event as EventLift).phase == EnumLiftPhase.CHOOSING:
		for lift: Node in Unified.session.get_views(EnumView.LIFT):
			play(Kind.DUST_RING, (lift as Node3D).global_position)
	# Braziers and the boss
	elif event is EventBrazier:
		var brazier := event as EventBrazier
		var bowl: Vector3 = brazier.position + Vector3(0, BOWL_HEIGHT, 0)
		play(Kind.EMBERS, bowl)
		if not brazier.lit:
			play(Kind.SMOKE, bowl)
	elif event is EventBossStage:
		var king: EliteView = _king()
		if king != null:
			play(Kind.DUST_RING, king.global_position)
	elif event is EventBossSlam:
		var slam: Vector3 = (event as EventBossSlam).position
		shock_ring(slam)
		play(Kind.SLAM_DUST, slam)
		crack(slam, event.id)
	elif event is EventBossDefeated:
		var fell: Vector3 = (event as EventBossDefeated).position
		for offset: Vector3 in BOSS_BURSTS:
			play(Kind.BONE_BURST, fell + offset)
		pulse(fell + Vector3(0, FLASH_HEIGHT, 0), BOSS_FLASH, BOSS_FLASH_ENERGY, BOSS_FLASH_RANGE, BOSS_FLASH_S,
			event.id)


## The Bone King's view while it is in the sim (null: none).
func _king() -> EliteView:
	for view: Node in Unified.session.get_views(EnumView.ELITE):
		var elite := view as EliteView
		if elite.data.kind == EnumEliteKind.KING:
			return elite
	return null


func _decal(at: Vector3, id: int, texture: Texture2D, tint: Color, size: float, seconds: float) -> void:
	var slot: Slot = _take(_decals, id, seconds)
	var decal: Decal = slot.node as Decal
	decal.texture_albedo = texture
	decal.modulate = tint
	decal.size = Vector3(size, DECAL_DEPTH, size)
	# turned by where it lies, so two scorches never look stamped
	decal.global_transform = Transform3D(Basis(Vector3.UP, fposmod(at.x * 12.9898 + at.z * 78.233, TAU)), at)
	_show(slot)


## The oldest of `slots` (a free one first), made `id`'s for `seconds` from now.
func _take(slots: Array[Slot], id: int, seconds: float) -> Slot:
	var oldest: Slot = slots[0]
	for slot: Slot in slots:
		if slot.life <= 0.0:
			oldest = slot
			break
		if slot.born < oldest.born:
			oldest = slot
	oldest.id = id
	oldest.lingers = true
	oldest.settled = false
	oldest.born = _clock
	oldest.life = seconds
	oldest.cancelled_at = -1.0
	oldest.node.visible = true
	return oldest


## How strongly `slot` shows now, 0 to 1: its life's own fade, then a cancel's.
func _strength(slot: Slot) -> float:
	var age: float = _clock - slot.born
	var strength: float = clampf(1.0 - age / slot.life, 0.0, 1.0)
	if slot.shows == Shows.DECAL:
		strength = clampf((slot.life - age) / DECAL_FADE_S, 0.0, 1.0)
	elif slot.shows == Shows.PULSE:
		strength *= strength
	if slot.cancelled_at >= 0.0:
		strength = minf(strength, slot.cancel_from * (1.0 - (_clock - slot.cancelled_at) / CANCEL_FADE_S))
	return maxf(strength, 0.0)


## Shows `slot` as it is now on the clock, and frees it once nothing of it shows.
func _show(slot: Slot) -> void:
	var strength: float = _strength(slot)
	if strength <= 0.0:
		slot.life = 0.0
		slot.node.visible = false
		return
	match slot.shows:
		Shows.DECAL:
			(slot.node as Decal).albedo_mix = strength
		Shows.PULSE:
			(slot.node as OmniLight3D).light_energy = slot.peak * strength
		Shows.RING:  # spreading fast, then fading
			var gone: float = 1.0 - strength
			var radius: float = lerpf(SHOCK_START, SHOCK_RADIUS, 1.0 - strength * strength)
			slot.node.scale = Vector3(radius, 1, radius)
			(slot.node as GeometryInstance3D).transparency = gone * gone
		Shows.TRACER:
			(slot.node as GeometryInstance3D).transparency = 1.0 - strength


## Counts the one-shot nodes and particles playing anew at a new frame, and zeroes each pool's starts.
func _count_frame() -> void:
	var frame: int = Engine.get_process_frames()
	if frame == _frame:
		return
	_frame = frame
	_live_nodes = 0
	_live_particles = 0
	for pool: Pool in _pools:
		pool.started = 0
		pool.spots.clear()
		for end: float in pool.ends:
			if end > _clock:
				_live_nodes += 1
				_live_particles += pool.amount


func _pool(scene: PackedScene, size: int) -> Pool:
	var pool := Pool.new()
	for _i: int in size:
		var particles: GPUParticles3D = scene.instantiate()
		particles.visible = false
		add_child(particles)
		pool.nodes.append(particles)
	pool.ends.resize(size)
	pool.ends.fill(0.0)
	pool.amount = pool.nodes[0].amount
	pool.lifetime = pool.nodes[0].lifetime
	return pool


func _slot(node: Node3D, shows: Shows) -> Slot:
	node.visible = false
	add_child(node)
	var slot := Slot.new()
	slot.node = node
	slot.shows = shows
	_slots.append(slot)
	return slot


## A pool of one one-shot kind's nodes, taken in turn, and its starts this frame.
class Pool:
	extends RefCounted
	var nodes: Array[GPUParticles3D] = []
	## When each node's particles are all gone, on the Effects clock.
	var ends: PackedFloat64Array = []
	## Its scene's particles a node, and their lifetime (seconds).
	var amount: int = 0
	var lifetime: float = 0.0
	## The index of the node take() gives next.
	var next: int = 0
	## How many started this frame, and where.
	var started: int = 0
	var spots: PackedVector3Array = []

	## The next node, the oldest in use.
	func take() -> GPUParticles3D:
		var node: GPUParticles3D = nodes[next]
		next = (next + 1) % nodes.size()
		return node


## A decal, a light pulse, a shock ring or a tracer: its node and its life on the Effects clock.
class Slot:
	extends RefCounted
	var node: Node3D
	var shows: Shows = Shows.DECAL
	## The event that left it (0: none), whether it lingers (an event's CANCELLED undoes it), and whether it is settled
	## (its event confirmed: nothing undoes it).
	var id: int = 0
	var lingers: bool = false
	var settled: bool = false
	## When it began, and how long it lasts (0: free).
	var born: float = 0.0
	var life: float = 0.0
	## When its event was cancelled (negative: it wasn't), and how strongly it showed then.
	var cancelled_at: float = -1.0
	var cancel_from: float = 1.0
	## A light pulse's energy at its start.
	var peak: float = 0.0
