// The elites: skeleton Warriors, Rogues and Mages, few and tough, each a Box3D character (physics.Character, a
// capsule in CAT_ELITE tagged with its handle's key), so they body-block heroes, props bounce off them, and bolts and
// the crossbow's rewound ray meet them through Box3D. They walk the heroes' navigation fields as minions do, but by
// their own drive, and minions are pushed out of them (obstacles_of). Each kind's approach and attack is its own file
// (elite_warrior, elite_rogue, elite_mage); this file is what they share: where they come from (a level's `elite`
// markers, asleep until a hero comes into sight or one is hit; every elite_every-th surge; a dev command), their
// drive and facing, the attack's clock, damage and knocks (damage_elite, the only way in), the guard's break
// (break_guard, the one entry a charge, a fireball and a thrown prop call), and dying.
//
// None rise under a held crowd (its population is exactly what was asked), and an empty table costs a walk of nothing.
package crypt_crew

import "unified:dmath"
import "unified:nav"
import "unified:physics"
import "unified:sim"

// What kind of elite (an `elite` marker's `kind`, by name).
Elite_Kind :: enum u8 {
	Warrior, // shielded: blows from its front barely hurt it until its guard is broken (elite_warrior.odin)
	Rogue, // a flanker: it circles behind its target, lunges and backs off (elite_rogue.odin)
	Mage, // keeps its distance, casts bone bolts and raises minions (elite_mage.odin)
}

// What an elite is doing (Elite.phase), since Elite.since.
Elite_Phase :: enum u8 {
	Idle, // asleep at its marker until a hero comes into sight or it is hit
	Rise, // climbing out of the floor (a surge's, a dev spawn's), RISE_S, harmless; then Chase
	Chase, // its kind's approach: the Warrior at its target, the Rogue round to its back, the Mage to its band
	Attack, // its kind's attack, its spec's windup then the rest of its duration (a Rogue's is a lunge)
	Retreat, // a Rogue after its lunge, backing off for FLANK_RETREAT_S
	Summon, // a Mage raising minions: SUMMON_CAST_S, then they rise round it
	// Heaved by a Barbarian (barbarian.odin), its body limp and its rules still: held up on the hold (HEAVE_MAX_S at
	// most), then thrown until it lands (land_heaves), when it chases again, staggered.
	Held,
	Thrown,
	Dying, // falling, DEATH_S, its body already gone (heroes walk over it); then the row is freed
}

// An elite, a row of the State's `elites`.
Elite :: struct {
	body:        physics.Character, // zero while it dies
	pos:         [3]f32, // its feet, read back after the physics step (read_back_elites)
	vel:         [3]f32, // its body's velocity, read back with `pos`
	facing:      [2]f32, // unit (x, z): it turns at most ELITE_TURN_COS a tick (turn_toward)
	target:      sim.Player, // the hero it is after ({}: none)
	heaved_by:   sim.Player, // Held or Thrown: the Barbarian holding it, or who threw it (the landing's blow is theirs)
	since:       sim.Game_Time, // when `phase` began
	struck:      sim.Game_Time, // when it was last hit (0: never; the view's flash)
	stagger:     sim.Timer, // while it runs: no walking, no attack, a Warrior's shield down (ELITE_STAGGER_KNOCK)
	guard_down:  sim.Timer, // a Warrior's guard is broken while it runs (break_guard)
	next_bolt:   sim.Timer, // a Mage's next bone bolt waits for it
	next_summon: sim.Timer, // a Mage's next summoning waits for it
	// A Rogue circling its target is patient while it runs (FLANK_GIVE_UP_TICKS from when it began to circle); zero
	// while it isn't circling.
	patience:    sim.Timer,
	hp:          i16,
	kind:        Elite_Kind,
	phase:       Elite_Phase,
	_pad:        [4]u8,
}

// What a skeleton Mage casts (Event_Elite_Cast).
Elite_Spell :: enum u8 {
	Bone_Bolt,
	Summon,
}

// `player` hit `elite` for `damage` with `source` (sim.Position: where); `guarded` when a Warrior's shield took most
// of it.
Event_Elite_Hit :: struct {
	elite:    sim.Handle(Elite),
	position: sim.Position,
	damage:   i16,
	player:   sim.Player,
	source:   Hit_Source,
	guarded:  bool,
}

// `elite`, of kind `elite_kind`, died, felled by `player` ({}: nobody's) with `source`.
Event_Elite_Died :: struct {
	elite:      sim.Handle(Elite),
	position:   sim.Position,
	player:     sim.Player,
	source:     Hit_Source,
	elite_kind: Elite_Kind,
}

// `elite`'s guard was broken by `player` ({}: nobody's).
Event_Guard_Broken :: struct {
	elite:    sim.Handle(Elite),
	position: sim.Position,
	player:   sim.Player,
}

// `elite` (a Mage) began casting `spell`.
Event_Elite_Cast :: struct {
	elite:    sim.Handle(Elite),
	position: sim.Position,
	spell:    Elite_Spell,
}

// An elite's place (an `elite` marker): where it sleeps, facing the marker's +Z.
Elite_Def :: struct {
	pos:    [3]f32,
	facing: [2]f32,
	kind:   Elite_Kind,
}

// Each kind's controller: a hero's, but heavier and with a stronger drive (ELITE_DENSITY, ELITE_GROUND_FORCE: a hero
// walking into one barely moves it), its own max_speed, in CAT_ELITE.
// It reports no hits of its own: a prop's shape does (props.odin), which is all elite_impacts reads, and an elite's
// would add a hit for every wall or hero it is knocked into.
elite_def :: proc(kind: Elite_Kind) -> physics.Character_Def {
	def := physics.CHARACTER_DEFAULT
	def.radius = ELITE_RADIUS
	def.half_height = ELITE_HALF_HEIGHT
	def.pogo_rest = HERO_POGO_REST
	def.density = ELITE_DENSITY
	def.max_ground_force = ELITE_GROUND_FORCE
	def.accelerate = HERO_ACCELERATE
	def.category = CAT_ELITE
	def.sensor_events = true // spikes feel it (traps.odin)
	def.max_speed = ELITE_SPECS[kind].max_speed
	return def
}

// An elite of `kind` standing at `feet` on the floor, facing `facing`, in `phase` since `now` (Idle: asleep; Rise:
// rising), at full health, with its body in `world`; false when the table is full.
spawn_elite :: proc(
	state: ^State,
	world: ^World,
	kind: Elite_Kind,
	feet: [3]f32,
	facing: [2]f32,
	phase: Elite_Phase,
	now: sim.Game_Time,
) -> (
	handle: sim.Handle(Elite),
	ok: bool,
) {
	elite: ^Elite
	elite, handle = sim.spawn(&state.elites) or_return
	elite^ = {
		pos    = feet,
		facing = facing,
		since  = now,
		hp     = elite_hp(state, kind), // the difficulty's (run.odin)
		kind   = kind,
		phase  = phase,
	}
	if phase != .Idle && phase != .Rise do start_mage_clocks(elite, now) // it chases at once: as if it just woke
	physics.character_create(
		world.phys,
		&elite.body,
		world.elite_defs[kind],
		feet + {0, ELITE_CENTRE_ABOVE_FEET, 0},
		tag = sim.handle_key(handle),
	)
	// A sleeper is a dormant character (no joints, a kinematic capsule Box3D lets sleep) until rouse_elite wakes it: a
	// character awake is driven every tick, which made each sleeper cost what a fighting elite does. It stands where
	// its pogo would hold it, and nothing shoves it; casts still find it.
	if phase == .Idle do physics.character_set_dormant(world.phys, &elite.body, true)
	return handle, true
}

// Every elite marker's elite, asleep in its place (entering a floor, in marker order).
spawn_marker_elites :: proc(t: ^Tick) {
	for &def in sim.slice(&floor_of(t).places.elites) {
		spawn_elite(t.state, t.world, def.kind, def.pos, def.facing, .Idle, t.time)
	}
}

// How many elites are alive (not dying).
elites_alive :: proc(elites: ^sim.Table(Elite, MAX_ELITES)) -> int {
	alive := 0
	walk := sim.iterate(elites)
	for elite in sim.next(&walk) do alive += int(elite.phase != .Dying)
	return alive
}

// Whether a live elite stands within `radius` of `point` (on the floor plan).
elite_near :: proc(t: ^Tick, point: [3]f32, radius: f32) -> bool {
	elites := sim.iterate(&t.state.elites)
	for elite in sim.next(&elites) {
		if elite.phase != .Dying && dmath.length_sq(elite.pos.xz - point.xz) < radius * radius do return true
	}
	return false
}

// An elite of `kind` rising at `near` (a surge's grave, a dev spawn's place), or the first of the eight spots
// ELITE_RISE_RING round it that is: on the walkable floor and clear of every live elite and present hero; none while
// a population is held, ELITES_ALIVE_MAX are alive or the table is full, or no spot is free.
raise_elite :: proc(
	t: ^Tick,
	kind: Elite_Kind,
	near: [3]f32,
	facing: [2]f32,
) -> (
	handle: sim.Handle(Elite),
	ok: bool,
) {
	if t.state.held > 0 || elites_alive(&t.state.elites) >= ELITES_ALIVE_MAX do return
	floor := floor_of(t)
	for k in -1 ..< len(dmath.DIR8) {
		at := near
		if k >= 0 do at += [3]f32{dmath.DIR8[k].x, 0, dmath.DIR8[k].y} * ELITE_RISE_RING
		spot := floor_spot(floor, at, 1) or_continue
		if !elite_room(t, spot.point) do continue
		return spawn_elite(t.state, t.world, kind, spot.point, facing, .Rise, t.time)
	}
	return
}

// Whether an elite's capsule fits at `point`: clear of every live elite's and every present hero's.
@(private = "file")
elite_room :: proc(t: ^Tick, point: [3]f32) -> bool {
	if elite_near(t, point, 2 * ELITE_RADIUS + ARRIVAL_ROOM) do return false
	heroes := sim.iterate_present(t)
	for hero in sim.next(&heroes) {
		if hero.body != {} && dmath.length(hero.pos.xz - point.xz) < ELITE_RADIUS + HERO_RADIUS + ARRIVAL_ROOM {
			return false
		}
	}
	return true
}

// The director's hook (raise_surges): every elite_every-th surge on a floor brings an elite (run.odin), the kinds in turn
// (Warrior, Rogue, Mage), rising at one of the surge's graves (indices into the floor's), the graves taken in turn too.
raise_surge_elite :: proc(t: ^Tick, graves: []int) {
	every := elite_every(t)
	if len(graves) == 0 || t.state.floor_surges % every != 0 do return
	turn := int(t.state.floor_surges / every - 1)
	grave := sim.slice(&floor_of(t).places.graves)[graves[turn % len(graves)]]
	raise_elite(t, Elite_Kind(turn % len(Elite_Kind)), grave.point, {0, 1})
}

// An elite's first chase (it woke, or rose): a sleeper's dormant character wakes (spawn_elite), so move_elites drives
// it, and a knock, a blast's push or a heave moves it, all of which come after this; a Mage's clocks start
// (start_mage_clocks), from `now`.
rouse_elite :: proc(phys: ^physics.World, elite: ^Elite, now: sim.Game_Time) {
	if elite.phase == .Idle do physics.character_set_dormant(phys, &elite.body, false)
	elite.phase, elite.since = .Chase, now
	start_mage_clocks(elite, now)
}

// A Mage's clocks at its first chase, from `now`: its first bolt BONE_BOLT_FIRST_S off and its first summoning
// SUMMON_EVERY_S (any other kind keeps none).
start_mage_clocks :: proc(elite: ^Elite, now: sim.Game_Time) {
	if elite.kind != .Mage do return
	elite.next_bolt = {now, now + sim.Game_Time(BONE_BOLT_FIRST_TICKS)}
	elite.next_summon = {now, now + sim.Game_Time(SUMMON_EVERY_TICKS)}
}

// Whether an elite reels from a knock (ELITE_STAGGER_KNOCK): it walks at nothing and starts no attack.
elite_staggered :: proc(t: ^Tick, elite: ^Elite) -> bool {
	return sim.timer_running(t, elite.stagger)
}

// Each sleeping elite looks every SIGHT_TICKS (sliced by its index), as a pack's sleepers do: a hero up within
// AGGRO_RADIUS that no wall hides wakes it.
wake_elites :: proc(t: ^Tick) {
	elites := sim.iterate(&t.state.elites)
	for elite, handle in sim.next(&elites) {
		if elite.phase != .Idle || !sim.due(t, handle.index, SIGHT_TICKS) do continue
		heroes := sim.iterate_present(t)
		for _, player in sim.next(&heroes) {
			if !elite_sees(t, elite, player, AGGRO_RADIUS) do continue
			rouse_elite(t.world.phys, elite, t.time)
			break
		}
	}
}

// Whether `player`'s hero is up within `reach` of the elite and no wall stands between their eyes.
elite_sees :: proc(t: ^Tick, elite: ^Elite, player: sim.Player, reach: f32) -> bool {
	if !hero_up(t, player) do return false
	eye := elite.pos + {0, EYE_HEIGHT, 0}
	seen := sim.player_data(t, player).pos + {0, EYE_HEIGHT, 0}
	if dmath.length_sq(seen - eye) > reach * reach do return false
	_, walled := physics.world_cast_ray_closest(t.world.phys, eye, seen - eye, SIGHT_FILTER)
	return !walled
}

// Each live elite awake picks its target (retarget_elite), then its drive (its kind's way, or none while rising,
// summoning, staggered or swinging) and its facing, and its controller is driven: before the physics step. A sleeper
// has no controller to drive (spawn_elite), and a heaved one's limp body is the hold's, or its throw's.
move_elites :: proc(t: ^Tick) {
	floor := floor_of(t)
	elites := sim.iterate(&t.state.elites)
	for elite, handle in sim.next(&elites) {
		if elite.phase == .Dying || elite.phase == .Idle || elite.phase == .Held || elite.phase == .Thrown do continue
		spot, on_floor := floor_spot(floor, elite.pos, HERO_NAV_REACH)
		if !on_floor do spot.poly = nav.NO_POLY // on a crate's top, say: it stands until it is down
		retarget_elite(t, floor, elite, handle, spot)
		heading, look, scale := elite_drive(t, floor, elite, spot)
		// an attack holds the facing it locked, but a Rogue's lunge homes (elite_drive's look)
		if elite.phase != .Attack || look != {} do elite.facing = turn_toward(elite.facing, look if look != {} else heading)
		def := t.world.elite_defs[elite.kind]
		physics.character_update(t.world.phys, &elite.body, def, heading, false, scale)
	}
}

// Where an elite walks this tick (`heading`, unit or zero), where it would look (`look`; zero: along its heading) and
// its drive's speed scale.
@(private = "file")
elite_drive :: proc(t: ^Tick, floor: ^Floor, elite: ^Elite, spot: Nav_Point) -> (heading, look: [2]f32, scale: f32) {
	scale = 1
	if elite_staggered(t, elite) do return
	to_target: [2]f32 // toward its target, unit ({}: none)
	near := false // its target is within ELITE_FACE_NEAR: it looks at it
	if elite.target != {} {
		offset := sim.player_data(t, elite.target).pos.xz - elite.pos.xz
		to_target = dmath.normalize(offset)
		near = dmath.length_sq(offset) < ELITE_FACE_NEAR * ELITE_FACE_NEAR
	}
	#partial switch elite.phase {
	case .Chase:
		if elite.target == {} do return
		switch elite.kind {
		case .Warrior:
			heading = warrior_heading(t, floor, elite, spot)
		case .Rogue:
			heading = rogue_heading(t, floor, elite, spot)
		case .Mage:
			heading, look = mage_heading(t, floor, elite, spot)
		}
		if look == {} && near do look = to_target
	case .Attack:
		// A Rogue's lunge drives it along its facing through the windup, the facing turning toward its target as any
		// turn does (it homes, but no faster than ELITE_TURN_COS: a hero who steps aside still makes it miss); every
		// other attack stands, its facing locked.
		if elite.kind == .Rogue && u32(t.time - elite.since) < ELITE_SPECS[.Rogue].windup {
			heading, look, scale = elite.facing, to_target, LUNGE_SPEED / ELITE_SPECS[.Rogue].max_speed
		}
	case .Retreat:
		heading = open_heading(floor, spot, -to_target)
	}
	return
}

// The elite's target: kept while it attacks, backs off or summons, and while it is up; else, every RETARGET_TICKS
// (sliced by its index) and at once without one, the hero up nearest along the floor (its field's cost from the
// elite's polygon; ties by slot). An elite off the floor keeps its target. Asleep, rising, heaved or dying, none.
@(private = "file")
retarget_elite :: proc(t: ^Tick, floor: ^Floor, elite: ^Elite, handle: sim.Handle(Elite), spot: Nav_Point) {
	if elite.phase == .Idle || elite.phase == .Rise do return
	if !hero_up(t, elite.target) do elite.target = {}
	if elite.phase != .Chase || spot.poly == nav.NO_POLY do return
	if elite.target != {} && !sim.due(t, handle.index, RETARGET_TICKS) do return
	best: sim.Player
	best_cost := nav.UNREACHABLE
	heroes := sim.iterate_present(t)
	for _, player in sim.next(&heroes) {
		hero_spot := t.world.hero_spots[sim.player_slot(t, player)]
		if hero_spot.poly == nav.NO_POLY do continue
		cost := nav.field(&floor.fields, hero_spot.poly).cost[spot.poly]
		if cost < best_cost do best, best_cost = player, cost
	}
	elite.target = best
}

// The way along the floor from the elite (`spot`, its place on the mesh) to its target, unit: the target's field
// steered (nav.steer); zero when either is off the floor or there is no way.
path_heading :: proc(t: ^Tick, floor: ^Floor, elite: ^Elite, spot: Nav_Point) -> [2]f32 {
	goal := t.world.hero_spots[sim.player_slot(t, elite.target)]
	if goal.poly == nav.NO_POLY || spot.poly == nav.NO_POLY do return {}
	next := nav.steer(&floor.mesh, nav.field(&floor.fields, goal.poly), spot.poly, spot.point, goal.point)
	return dmath.normalize((next - spot.point).xz)
}

// A way to back off along `want` (unit) from `spot` that the floor leaves open: `want` itself, else the first of it
// turned an eighth, then a quarter of a turn, each way (left first), along which a nav.move of OPEN_LOOK gets at least
// OPEN_GOT of the way; zero when none does (backed into a corner, it stands).
open_heading :: proc(floor: ^Floor, spot: Nav_Point, want: [2]f32) -> [2]f32 {
	if want == {} || spot.poly == nav.NO_POLY do return {}
	for turn in ([5]f32{0, 0.125, -0.125, 0.25, -0.25}) {
		way := dmath.rotate2(want, turn)
		_, to := nav.move(&floor.mesh, spot.poly, spot.point, spot.point + {way.x, 0, way.y} * OPEN_LOOK)
		if dmath.dot((to - spot.point).xz, way) >= OPEN_LOOK * OPEN_GOT do return way
	}
	return {}
}

// `facing` turned toward `want` (unit; zero: it stays) by at most ELITE_TURN_COS: a rotation by the turn's cosine and
// sine the short way round, renormalized.
turn_toward :: proc(facing, want: [2]f32) -> [2]f32 {
	if want == {} || dmath.dot(facing, want) >= ELITE_TURN_COS do return want if want != {} else facing
	sine := ELITE_TURN_SIN if dmath.cross2(facing, want) >= 0 else -ELITE_TURN_SIN
	turned := [2]f32{facing.x * ELITE_TURN_COS - facing.y * sine, facing.x * sine + facing.y * ELITE_TURN_COS}
	return dmath.normalize(turned)
}

// After the physics step: each live elite's feet and velocity, from its body.
read_back_elites :: proc(t: ^Tick) {
	elites := sim.iterate(&t.state.elites)
	for elite in sim.next(&elites) {
		if elite.phase == .Dying do continue
		elite.pos = physics.body_position(t.world.phys, elite.body.body) - {0, ELITE_CENTRE_ABOVE_FEET, 0}
		elite.vel = physics.body_linear_velocity(t.world.phys, elite.body.body)
	}
}

// After the physics step, the elites' phases advance: a riser chases after RISE_S; a chaser starts its kind's attack
// (or a Mage its summoning) when its kind says; an attack lands at its kind's windup and ends at its duration (a
// Rogue's into its retreat); a retreat ends after FLANK_RETREAT_S; a summoning raises its minions after SUMMON_CAST_S;
// a dying elite's row is freed after DEATH_S. A heaved elite's phase is the heave's (barbarian.odin).
age_elites :: proc(t: ^Tick) {
	elites := sim.iterate(&t.state.elites)
	for elite, handle in sim.next(&elites) {
		age := u32(t.time - elite.since)
		spec := &ELITE_SPECS[elite.kind]
		switch elite.phase {
		case .Rise:
			if age >= RISE_TICKS do rouse_elite(t.world.phys, elite, t.time)
		case .Chase:
			if elite.target == {} || elite_staggered(t, elite) do continue
			switch elite.kind {
			case .Warrior:
				warrior_ready(t, elite)
			case .Rogue:
				rogue_ready(t, elite)
			case .Mage:
				mage_ready(t, elite, handle)
			}
		case .Attack:
			if age == spec.windup {
				switch elite.kind {
				case .Warrior, .Rogue:
					elite_swing_lands(t, elite)
				case .Mage:
					cast_bone_bolt(t, elite, handle)
				}
			}
			if age >= spec.duration do elite.phase, elite.since = Elite_Phase.Retreat if elite.kind == .Rogue else .Chase, t.time
		case .Retreat:
			if age >= FLANK_RETREAT_TICKS do elite.phase, elite.since = .Chase, t.time
		case .Summon:
			if age >= SUMMON_CAST_TICKS do mage_summons(t, elite)
		case .Dying:
			if age >= DEATH_TICKS do physics.despawn(t.world.phys, &t.state.elites, handle)
		case .Idle, .Held, .Thrown:
		}
	}
}

// The elite starts its kind's attack now, facing as it does (the facing is locked until the attack ends).
start_elite_attack :: proc(t: ^Tick, elite: ^Elite) {
	elite.phase, elite.since = .Attack, t.time
}

// Whether the elite's target is in reach of its swing: its capsule within ELITE_REACH of the elite's (less `inside`).
elite_in_reach :: proc(t: ^Tick, elite: ^Elite, inside: f32 = 0) -> bool {
	if elite.target == {} do return false
	reach := ELITE_RADIUS + HERO_RADIUS + ELITE_REACH - inside
	return dmath.length_sq(sim.player_data(t, elite.target).pos.xz - elite.pos.xz) <= reach * reach
}

// Whether the elite's target is in front of it, within ELITE_STRIKE_COS of its facing.
elite_faces_target :: proc(t: ^Tick, elite: ^Elite) -> bool {
	to_target := dmath.normalize(sim.player_data(t, elite.target).pos.xz - elite.pos.xz)
	return to_target == {} || dmath.dot(to_target, elite.facing) >= ELITE_STRIKE_COS
}

// A Warrior's swing or a Rogue's lunge lands: on its target if it is still up, in reach, in front of the facing the
// attack locked and in sight, for its kind's damage.
@(private = "file")
elite_swing_lands :: proc(t: ^Tick, elite: ^Elite) {
	if !hero_up(t, elite.target) || !elite_in_reach(t, elite) || !elite_faces_target(t, elite) do return
	if !elite_sees(t, elite, elite.target, ELITE_RADIUS + HERO_RADIUS + ELITE_REACH) do return
	damage_hero(t, elite.target, ELITE_SPECS[elite.kind].damage, elite.pos)
}

// `elite` takes `damage` (> 0; Keen_Edge's more, from a hero: edged_damage) from `player` ({}: nobody) by `source`, the blow coming from `from` (on the floor
// plan: what a Warrior's shield judges), knocked along `knock_dir` (unit) by `knock` metres per second; asleep, it
// wakes (a sleeper doesn't guard: that blow lands whole). A Warrior's guard (warrior_guards) takes all but
// ELITE_GUARD_TAKE of a blow from its front, which then neither knocks nor staggers it; otherwise the knock moves it
// (knock_elite). At 0 it dies: Dying, its body gone (a held one let go of first), and its coins fall
// (drop_elite_loot). A dying elite takes nothing. The only way an elite takes damage or dies.
damage_elite :: proc(
	t: ^Tick,
	handle: sim.Handle(Elite),
	damage: i16,
	knock_dir: [2]f32,
	knock: f32,
	player: sim.Player,
	source: Hit_Source,
	from: [2]f32,
) {
	elite := sim.get(&t.state.elites, handle)
	if elite == nil || elite.phase == .Dying || damage <= 0 do return
	dealt := edged_damage(t, player, damage) // the blamed hero's Keen_Edge (boons.odin)
	guarded := warrior_guards(t, elite, from) // before it wakes: a sleeper's shield is down
	if elite.phase == .Idle do rouse_elite(t.world.phys, elite, t.time)
	taken := guard_take(dealt) if guarded else dealt
	elite.hp -= taken
	elite.struck = t.time
	if !guarded do knock_elite(t, elite, knock_dir, knock)
	hit := Event_Elite_Hit {
		elite    = handle,
		position = sim.Position(elite.pos),
		damage   = taken,
		player   = player,
		source   = source,
		guarded  = guarded,
	}
	sim.emit(t, hit)
	if elite.hp > 0 do return
	// the hold lets go before the body goes
	if elite.phase == .Held do release_heave(t, elite.heaved_by, thrown = false)
	elite.phase, elite.since, elite.target, elite.heaved_by = .Dying, t.time, {}, {}
	physics.character_destroy(t.world.phys, &elite.body)
	t.state.kills += 1
	died := Event_Elite_Died {
		elite      = handle,
		position   = sim.Position(elite.pos),
		player     = player,
		source     = source,
		elite_kind = elite.kind,
	}
	sim.emit(t, died)
	drop_elite_loot(t, elite.pos, elite.kind) // loot.odin
}

// A knock: `knock` times ELITE_KNOCK_TAKE along `dir` (shove_elite); a knock of ELITE_STAGGER_KNOCK or more staggers
// it for ELITE_STAGGER_TICKS, which cuts off an attack or a summoning (tried again SUMMON_RETRY_S on).
@(private = "file")
knock_elite :: proc(t: ^Tick, elite: ^Elite, dir: [2]f32, knock: f32) {
	if knock <= 0 || elite.body == {} do return
	shove_elite(t, elite, [3]f32{dir.x, 0, dir.y} * (knock * ELITE_KNOCK_TAKE))
	if knock < ELITE_STAGGER_KNOCK do return
	sim.timer_start_ticks(t, &elite.stagger, ELITE_STAGGER_TICKS)
	if elite.phase == .Summon do sim.timer_start_ticks(t, &elite.next_summon, SUMMON_RETRY_TICKS)
	if elite.phase == .Attack || elite.phase == .Summon do elite.phase, elite.since = .Chase, t.time
}

// `elite`'s body shoved by `change` (a velocity change, metres per second: a blow's knock, a blast's push), its speed
// along the floor at most ELITE_KNOCK_MAX after it however the shoves add up (its drive's friction then slows it). A
// held elite takes none: its body is its hold's (a heaved one is let go of first, or the hold flings it).
shove_elite :: proc(t: ^Tick, elite: ^Elite, change: [3]f32) {
	if elite.body == {} || elite.phase == .Held do return
	velocity := physics.body_linear_velocity(t.world.phys, elite.body.body) + change
	along := dmath.clamp_length(velocity.xz, ELITE_KNOCK_MAX)
	physics.body_set_linear_velocity(t.world.phys, elite.body.body, {along.x, velocity.y, along.y})
}

// `elite`'s guard breaks for GUARD_BREAK_TICKS (a Warrior's; the other kinds carry no shield): what a Knight's charge,
// a Mage's fireball, a thrown prop and a heaved body's landing do (knock_elites, elite_impacts), and
// `dev_break_guards`. Announced when it was up. A break of a broken guard starts its clock again.
break_guard :: proc(t: ^Tick, handle: sim.Handle(Elite), player: sim.Player) {
	elite := sim.get(&t.state.elites, handle)
	if elite == nil || elite.kind != .Warrior || elite.phase == .Dying do return
	was_up := !sim.timer_running(t, elite.guard_down)
	sim.timer_start_ticks(t, &elite.guard_down, GUARD_BREAK_TICKS)
	if was_up do sim.emit(t, Event_Guard_Broken{elite = handle, position = sim.Position(elite.pos), player = player})
}

// The blast of knock_area at `at` on the elites: every live one within `radius` (its centre, on the floor plan) that
// no wall shields (a ray to its chest), other than `skip`, takes `damage` and a knock away from `at` falling off to
// BLAST_RIM of it at the rim, as a minion does; a blast that `breaks_guard` (a charge's, a fireball's, a landing's)
// breaks a Warrior's first (break_guard), so the blow lands whole and knocks it.
knock_elites :: proc(
	t: ^Tick,
	at: [3]f32,
	radius: f32,
	damage: i16,
	knock: f32,
	player: sim.Player,
	source: Hit_Source,
	skip: sim.Handle(Elite),
	breaks_guard: bool,
) {
	elites := sim.iterate(&t.state.elites)
	for elite, handle in sim.next(&elites) {
		if handle == skip || elite.phase == .Dying do continue
		offset := elite.pos.xz - at.xz
		distance := dmath.length(offset)
		if distance > radius do continue
		target := elite.pos + {0, CHEST_HEIGHT, 0}
		if _, walled := physics.world_cast_ray_closest(t.world.phys, at, target - at, SIGHT_FILTER); walled do continue
		away := offset / distance if distance > 0 else [2]f32{1, 0}
		falloff := knock * (1 - (1 - BLAST_RIM) * distance / radius)
		if breaks_guard do break_guard(t, handle, player)
		damage_elite(t, handle, damage, away, falloff, player, source, at.xz)
	}
}

// After the props' impacts (prop_impacts filled the World's contacts): a thrown prop (its throw running) that hit an
// elite at PROP_HIT_SPEED or faster breaks its guard and hurts it as it hurts a minion (PROP_HIT_DAMAGE, knocked
// away from the prop at PROP_HIT_KNOCK), its thrower's blow, once per throw (Prop.elites_hit: a bounce back is no
// new hit). Box3D's own hit (a contact's start), since the elite is a body the prop bounces off.
elite_impacts :: proc(t: ^Tick) {
	if t.state.elites.count == 0 do return // no elite: the step's contacts are left unread (a crowd's throws make many)
	for &hit in t.world.contacts {
		if hit.kind != .Hit || hit.speed < PROP_HIT_SPEED do continue
		prop_shape, elite_shape := hit.a, hit.b
		if prop_shape.category & CAT_PROP == 0 do prop_shape, elite_shape = elite_shape, prop_shape
		if prop_shape.category & CAT_PROP == 0 || elite_shape.category & CAT_ELITE == 0 do continue
		prop := sim.get(&t.state.props, sim.handle_of_key(Prop, prop_shape.tag))
		handle := sim.handle_of_key(Elite, elite_shape.tag)
		elite := sim.get(&t.state.elites, handle)
		if prop == nil || elite == nil || !sim.timer_running(t, prop.thrown) do continue
		if prop_hit_elite(prop, handle) || !sim.append(&prop.elites_hit, handle) do continue
		centre := physics.body_position(t.world.phys, prop.body).xz
		break_guard(t, handle, prop.thrown_by)
		away := dmath.normalize(elite.pos.xz - centre)
		damage_elite(t, handle, PROP_HIT_DAMAGE, away, PROP_HIT_KNOCK, prop.thrown_by, .Prop, centre)
	}
}

// Whether a prop's throw already hurt `elite`.
@(private = "file")
prop_hit_elite :: proc(prop: ^Prop, elite: sim.Handle(Elite)) -> bool {
	for hit in sim.slice(&prop.elites_hit) {
		if hit == elite do return true
	}
	return false
}
