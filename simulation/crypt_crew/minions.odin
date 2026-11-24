// The skeleton minions: rows of the State with no physics body, walking Floor 1's navigation mesh (unified:nav), so a
// crowd costs no Box3D bodies. Each tick: every minion picks its target (sliced: the nearest hero up by path, ties by
// slot), steers along that hero's distance field (memoized in the World), keeps apart from its neighbours over a grid
// (scratch, rebuilt from the block), is pushed out of heroes and props one way (they never feel it), carries a
// knockback of its own that decays, and moves with nav.move, which never leaves the mesh. In reach it winds up a
// telegraphed swing, which lands only if the hero is still in reach, in front and in sight. damage_minion is the only
// way a minion takes damage and dies; a dead minion falls (Dying) and its row is freed after DEATH_S.
package crypt_crew

import "unified:dmath"
import "unified:nav"
import "unified:physics"
import "unified:sim"

// What a minion is doing (Minion.phase), since Minion.since.
Minion_Phase :: enum u8 {
	Rise, // climbing out of a grave, RISE_S, harmless; then Chase
	Idle, // asleep in a pack until a hero comes into sight or it is hit (director.odin)
	Chase, // walking at its target
	Attack, // a swing: it lands MINION_WINDUP_S in, then the minion recovers until MINION_ATTACK_S
	Dying, // falling, DEATH_S, then the row is freed
}

// A minion, a row of the State's `minions`.
Minion :: struct {
	pos:    [3]f32, // its feet, on the navigation mesh
	vel:    [3]f32, // what it moved this tick, per second (where a rewound shot will find it)
	knock:  [2]f32, // a knockback's velocity (x, z), decaying at KNOCK_DECAY
	facing: [2]f32, // unit (x, z)
	poly:   nav.Poly, // the mesh polygon it stands on
	target: sim.Player, // the hero it chases ({}: none)
	since:  sim.Game_Time, // when `phase` began
	struck: sim.Game_Time, // when it was last hit (0: never; the view's flash)
	hp:     i16,
	phase:  Minion_Phase,
	pack:   u8, // its pack's index + 1 in the World's packs (0: none, a surge's or a spawned one): it wakes with them
}

// The live minions by cell on the floor plan (scratch in the World, rebuilt from the block by move_minions).
Minion_Grid :: sim.Grid(MINION_GRID_CELLS, MAX_MINIONS)

// A circle minions are pushed out of (a hero, a prop in the way), on the floor plan.
Obstacle :: struct {
	pos:    [2]f32,
	radius: f32,
}

// What blocks a minion's swing and a sleeper's sight: walls (low cover is swung and seen over).
SIGHT_FILTER :: physics.Filter {
	category = CAT_HERO,
	mask     = CAT_WALL,
}

// `player` hit `minion` for `damage` (sim.Position: where).
Event_Minion_Hit :: struct {
	minion:   sim.Handle(Minion),
	position: sim.Position,
	damage:   i16,
	player:   sim.Player,
}

// `minion` died, killed by `player` ({}: nobody's).
Event_Minion_Died :: struct {
	minion:   sim.Handle(Minion),
	position: sim.Position,
	player:   sim.Player,
}

// A minion in `phase` at `at` (a point of `poly`), facing `facing`, at full health, of pack `pack` (0: none); false
// when the table is full.
spawn_minion :: proc(
	state: ^State,
	at: [3]f32,
	poly: nav.Poly,
	facing: [2]f32,
	phase: Minion_Phase,
	now: sim.Game_Time,
	pack: u8 = 0,
) -> (
	handle: sim.Handle(Minion),
	ok: bool,
) {
	minion: ^Minion
	minion, handle = sim.spawn(&state.minions) or_return
	minion^ = {
		pos    = at,
		facing = facing,
		poly   = poly,
		since  = now,
		hp     = MINION_HP,
		phase  = phase,
		pack   = pack,
	}
	return handle, true
}

// Whether a live minion stands within `radius` of `point` (on the floor plan).
minion_near :: proc(t: ^Tick, point: [3]f32, radius: f32) -> bool {
	minions := sim.iterate(&t.state.minions)
	for minion in sim.next(&minions) {
		if minion.phase != .Dying && dmath.length_sq(minion.pos.xz - point.xz) < radius * radius do return true
	}
	return false
}

// How many minions are alive (not dying).
minions_alive :: proc(minions: ^sim.Table(Minion, MAX_MINIONS)) -> int {
	alive := 0
	walk := sim.iterate(minions)
	for minion in sim.next(&walk) do alive += int(minion.phase != .Dying)
	return alive
}

// `minion` takes `damage` (> 0) from `player` ({}: nobody), knocked along `knock_dir` (unit, x and z) at `knock`
// metres per second; asleep, it wakes, and its pack with it; at 0 it dies (Dying). A dying minion takes nothing. The
// only way a minion takes damage or dies.
damage_minion :: proc(
	t: ^Tick,
	handle: sim.Handle(Minion),
	damage: i16,
	knock_dir: [2]f32,
	knock: f32,
	player: sim.Player,
) {
	minion := sim.get(&t.state.minions, handle)
	if minion == nil || minion.phase == .Dying || damage <= 0 do return
	if minion.phase == .Idle do wake(t, minion)
	minion.hp -= damage
	minion.struck = t.time
	minion.knock += knock_dir * knock
	hit := Event_Minion_Hit {
		minion   = handle,
		position = sim.Position(minion.pos),
		damage   = damage,
		player   = player,
	}
	sim.emit(t, hit)
	if minion.hp > 0 do return
	minion.phase, minion.since, minion.target = .Dying, t.time, {}
	sim.emit(t, Event_Minion_Died{minion = handle, position = sim.Position(minion.pos), player = player})
}

// A sleeping minion wakes and chases: every sleeper of its pack with it (a lone one, alone).
wake :: proc(t: ^Tick, minion: ^Minion) {
	minion.phase, minion.since = .Chase, t.time
	if minion.pack == 0 do return
	minions := sim.iterate(&t.state.minions)
	for other in sim.next(&minions) {
		if other.phase == .Idle && other.pack == minion.pack do other.phase, other.since = .Chase, t.time
	}
}

// Each chasing minion's target, every RETARGET_S (time-sliced by its index), and at once for one without: the hero up
// nearest it along the floor (its field's cost; ties by slot), none when no hero up can be reached. A swinging minion
// keeps its target; a target that went down or left is dropped at once by every minion.
target_heroes :: proc(t: ^Tick) {
	minions := sim.iterate(&t.state.minions)
	for minion, handle in sim.next(&minions) {
		if minion.phase == .Idle || minion.phase == .Dying do continue
		if !hero_up(t, minion.target) do minion.target = {}
		if minion.phase == .Attack do continue
		if minion.target != {} && !sim.due(t, handle.index, RETARGET_TICKS) do continue
		best: sim.Player
		best_cost := nav.UNREACHABLE
		heroes := sim.iterate_present(t)
		for _, player in sim.next(&heroes) {
			spot := t.world.hero_spots[sim.player_slot(t, player)]
			if spot.poly == nav.NO_POLY do continue
			cost := nav.field(&t.world.fields, spot.poly).cost[minion.poly]
			if cost < best_cost do best, best_cost = player, cost
		}
		minion.target = best
	}
}

// Every minion moves (move_minion), against the grid and the obstacles of this tick's start.
move_minions :: proc(t: ^Tick) {
	build_grid(t)
	obstacles := obstacles_of(t)
	decay := dmath.exp_decay(KNOCK_DECAY, t.dt)
	minions := sim.iterate(&t.state.minions)
	for minion, handle in sim.next(&minions) do move_minion(t, minion, handle, sim.slice(&obstacles), decay)
}

// After the physics step, the minions' phases advance: a risen minion chases after RISE_S, a chaser with its target in
// reach starts a swing (its facing locked on the target), a swing lands at MINION_WINDUP_S (strike) and ends at
// MINION_ATTACK_S, and a dying minion's row is freed after DEATH_S.
age_minions :: proc(t: ^Tick) {
	minions := sim.iterate(&t.state.minions)
	for minion, handle in sim.next(&minions) {
		age := u32(t.time - minion.since)
		switch minion.phase {
		case .Rise:
			if age >= RISE_TICKS do minion.phase, minion.since = .Chase, t.time
		case .Attack:
			if age == MINION_WINDUP_TICKS do strike(t, minion)
			if age >= MINION_ATTACK_TICKS do minion.phase, minion.since = .Chase, t.time
		case .Chase:
			if !in_reach(t, minion) do continue
			minion.phase, minion.since = .Attack, t.time // its facing locks on the target: a swing has a direction
			if to_hero := dmath.normalize(sim.player_data(t, minion.target).pos.xz - minion.pos.xz); to_hero != {} {
				minion.facing = to_hero
			}
		case .Dying:
			if age >= DEATH_TICKS do sim.despawn(&t.state.minions, handle)
		case .Idle:
		}
	}
}

// The live minions into the World's grid (laid over the mesh in world_create), in table order, so a cell's minions
// come in index order.
@(private = "file")
build_grid :: proc(t: ^Tick) {
	sim.grid_begin(&t.world.grid, t.world.grid_origin, MINION_GRID_CELL, t.world.grid_columns, t.world.grid_rows)
	minions := sim.iterate(&t.state.minions)
	for minion, handle in sim.next(&minions) {
		if minion.phase != .Dying do sim.grid_add(&t.world.grid, i32(handle.index), minion.pos.xz)
	}
	sim.grid_end(&t.world.grid)
}

// What minions are pushed out of this tick: every present hero's capsule, and every prop held or at rest.
@(private = "file")
obstacles_of :: proc(t: ^Tick) -> (obstacles: sim.List(Obstacle, PLAYERS + MAX_PROPS)) {
	heroes := sim.iterate_present(t)
	for hero in sim.next(&heroes) do sim.append(&obstacles, Obstacle{hero.pos.xz, HERO_RADIUS})
	props := sim.iterate(&t.state.props)
	for prop in sim.next(&props) {
		if !prop_in_the_way(t.world.phys, prop) do continue
		centre := physics.body_position(t.world.phys, prop.body)
		sim.append(&obstacles, Obstacle{centre.xz, PROP_SPECS[prop.kind].footprint})
	}
	return
}

// One minion's move: its own velocity (toward its target while chasing), its neighbours' push and its knockback
// (`decay` is what a tick leaves of it), along the mesh; then out of what is in its way, along the mesh too. Its `vel`
// is what it moved.
@(private = "file")
move_minion :: proc(t: ^Tick, minion: ^Minion, handle: sim.Handle(Minion), obstacles: []Obstacle, decay: f32) {
	from := minion.pos
	velocity := minion.knock
	minion.knock *= decay
	if minion.phase == .Chase && minion.target != {} {
		spot := t.world.hero_spots[sim.player_slot(t, minion.target)]
		field := nav.field(&t.world.fields, spot.poly)
		next := nav.steer(&t.world.mesh, field, minion.poly, minion.pos, spot.point)
		heading := dmath.normalize((next - minion.pos).xz)
		if heading != {} do minion.facing = heading
		velocity += heading * MINION_SPEED
	}
	if minion.phase != .Dying && minion.phase != .Rise do velocity += separation(t, minion, handle)
	if velocity != {} {
		to := minion.pos + {velocity.x, 0, velocity.y} * t.dt
		minion.poly, minion.pos = nav.move(&t.world.mesh, minion.poly, minion.pos, to)
	}
	if minion.phase != .Dying {
		out := minion.pos.xz
		for obstacle in obstacles {
			away := out - obstacle.pos
			reach := obstacle.radius + MINION_RADIUS
			distance_sq := dmath.length_sq(away)
			if distance_sq >= reach * reach do continue
			if distance_sq < 0.0001 do away, distance_sq = minion.facing * -0.01, 0.0001 // on its centre: back off
			out = obstacle.pos + away * (reach / dmath.sqrt(distance_sq))
		}
		if out != minion.pos.xz {
			minion.poly, minion.pos = nav.move(&t.world.mesh, minion.poly, minion.pos, {out.x, minion.pos.y, out.y})
		}
	}
	minion.vel = (minion.pos - from) * TICK_HZ
}

// The push apart from the live minions within SEPARATION, at most SEPARATION_SPEED; two on the same spot part by index.
@(private = "file")
separation :: proc(t: ^Tick, minion: ^Minion, handle: sim.Handle(Minion)) -> [2]f32 {
	push: [2]f32
	for row in sim.grid_near(&t.world.grid, minion.pos.xz) {
		for other_index in row {
			if other_index == i32(handle.index) do continue
			away := minion.pos.xz - t.state.minions.items[other_index].pos.xz
			distance_sq := dmath.length_sq(away)
			if distance_sq >= SEPARATION * SEPARATION do continue
			if distance_sq < 0.0001 {
				away = {other_index < i32(handle.index) ? 0.01 : -0.01, 0} // stacked exactly: the later one steps aside
				distance_sq = 0.0001
			}
			distance := dmath.sqrt(distance_sq)
			push += away * ((SEPARATION - distance) / distance)
		}
	}
	return dmath.clamp_length(push * SEPARATION_SPEED, SEPARATION_SPEED)
}

// Whether a minion's target is close enough to swing at: its capsule within MINION_REACH of the minion's circle.
@(private = "file")
in_reach :: proc(t: ^Tick, minion: ^Minion) -> bool {
	if minion.target == {} do return false
	reach := MINION_RADIUS + HERO_RADIUS + MINION_REACH
	return dmath.length_sq(sim.player_data(t, minion.target).pos.xz - minion.pos.xz) <= reach * reach
}

// The swing lands: on the target if it is still up, in reach, in front of the facing the swing locked, and in sight
// (no wall between them).
@(private = "file")
strike :: proc(t: ^Tick, minion: ^Minion) {
	if !hero_up(t, minion.target) || !in_reach(t, minion) do return
	hero := sim.player_data(t, minion.target)
	to_hero := dmath.normalize(hero.pos.xz - minion.pos.xz)
	if to_hero != {} && dmath.dot(to_hero, minion.facing) < MINION_STRIKE_COS do return
	eye, seen := minion.pos + {0, EYE_HEIGHT, 0}, hero.pos + {0, EYE_HEIGHT, 0}
	if _, walled := physics.world_cast_ray_closest(t.world.phys, eye, seen - eye, SIGHT_FILTER); walled do return
	damage_hero(t, minion.target, MINION_DAMAGE, minion.pos)
}
