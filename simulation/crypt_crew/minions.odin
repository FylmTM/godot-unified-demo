// The skeleton minions: rows of the State with no physics body, walking the floor's navigation mesh (unified:nav), so a
// crowd costs no Box3D bodies. Each tick: every minion picks its target (sliced: the nearest hero up by path, ties by
// slot), steers along that hero's distance field (memoized in the World; sliced too while it is far off), keeps apart
// from its neighbours over a grid (scratch, rebuilt from the block), is pushed out of heroes and props one way (they
// never feel it), carries a knockback of its own that decays, and moves with nav.move, which never leaves the mesh.
// In reach it winds up a telegraphed swing, which lands only if the hero is still in reach, in front and in sight.
// damage_minion is the only way a minion takes damage and dies; a dead minion falls (Dying) and its row is freed after
// DEATH_S.
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
	since:  sim.Game_Time, // when `phase` began (a chaser's: when it took its target)
	struck: sim.Game_Time, // when it was last hit (0: never; the view's flash)
	hp:     i16,
	phase:  Minion_Phase,
	pack:   u8, // its pack's index + 1 in its floor's packs (0: none, a surge's or a spawned one): it wakes with them
}

// The live minions by cell on the floor plan (scratch in the World, rebuilt from the block by move_minions and again
// before the strikes).
Minion_Grid :: sim.Grid(MINION_GRID_CELLS, MAX_MINIONS)

// The live minions within a reach of a point, after the physics step (minions_within): `for minion, handle in
// next_within(&walk)`, in the grid's order: a row of cells at a time from the smallest z, each row by cell and then
// index, a fixed order whatever the reach.
Minions_Within :: struct {
	box:      sim.Grid_Box(MINION_GRID_CELLS, MAX_MINIONS),
	row:      []i32, // the row of cells being walked, and where in it
	at:       int,
	centre:   [2]f32,
	reach_sq: f32,
	minions:  ^sim.Table(Minion, MAX_MINIONS),
}

// What a box of cells reaches past a query's reach: a minion exactly at the reach, filed in the next cell by a last
// bit of rounding, is still walked (the exact distance test decides).
GRID_BOX_PAD :: f32(0.01)

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

// What hit a minion.
Hit_Source :: enum u8 {
	Blow, // a Knight's or a Barbarian's swing
	Bolt, // a Mage's bolt, or its burst
	Crossbow, // a Rogue's shot
	Prop, // a thrown prop
	Dev, // dev_kill_minions
	Charge, // a Knight's shield charge
	Fireball, // a Mage's fireball's burst
	Heave, // a body a Barbarian threw, landing (barbarian.odin)
}

// `player` hit `minion` for `damage` with `source` (sim.Position: where).
Event_Minion_Hit :: struct {
	minion:   sim.Handle(Minion),
	position: sim.Position,
	damage:   i16,
	player:   sim.Player,
	source:   Hit_Source,
}

// `minion` died, killed by `player` ({}: nobody's) with `source`.
Event_Minion_Died :: struct {
	minion:   sim.Handle(Minion),
	position: sim.Position,
	player:   sim.Player,
	source:   Hit_Source,
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

// `minion` takes `damage` (> 0; Keen_Edge's more, from a hero: edged_damage) from `player` ({}: nobody) by `source`, knocked along `knock_dir` (unit, x and z) at
// `knock` metres per second (added to its knockback, at most KNOCK_MAX); asleep, it wakes, and its pack with it; at
// 0 it dies (Dying). A dying minion takes nothing. The only way a minion takes damage or dies.
damage_minion :: proc(
	t: ^Tick,
	handle: sim.Handle(Minion),
	damage: i16,
	knock_dir: [2]f32,
	knock: f32,
	player: sim.Player,
	source: Hit_Source,
) {
	minion := sim.get(&t.state.minions, handle)
	if minion == nil || minion.phase == .Dying || damage <= 0 do return
	dealt := edged_damage(t, player, damage) // the blamed hero's Keen_Edge (boons.odin)
	if minion.phase == .Idle do wake(t, minion)
	minion.hp -= dealt
	minion.struck = t.time
	minion.knock = dmath.clamp_length(minion.knock + knock_dir * knock, KNOCK_MAX)
	hit := Event_Minion_Hit {
		minion   = handle,
		position = sim.Position(minion.pos),
		damage   = dealt,
		player   = player,
		source   = source,
	}
	sim.emit(t, hit)
	if minion.hp > 0 do return
	minion.phase, minion.since, minion.target = .Dying, t.time, {}
	t.state.kills += 1
	died := Event_Minion_Died {
		minion   = handle,
		position = sim.Position(minion.pos),
		player   = player,
		source   = source,
	}
	sim.emit(t, died)
	drop_minion_loot(t, minion.pos) // loot.odin
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
	fields := &floor_of(t).fields
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
			cost := nav.field(fields, spot.poly).cost[minion.poly]
			if cost < best_cost do best, best_cost = player, cost
		}
		if best != minion.target && minion.phase == .Chase do minion.since = t.time // a new chase: steered at once
		minion.target = best
	}
}

// Every minion moves (move_minion), against the grid and the obstacles of this tick's start.
move_minions :: proc(t: ^Tick) {
	t.world.strike_grid = false // the grid is about to hold the moves' picture
	build_grid(t)
	starts := sim.iterate(&t.state.minions)
	for minion, handle in sim.next(&starts) {
		t.world.starts[handle.index] = minion.pos.xz
		place := Queue_Place{} // in no queue: asleep, rising, dying, reeling, or chasing nobody
		if (minion.phase == .Chase || minion.phase == .Attack) && minion.target != {} && !staggered(minion) {
			place.hero = i32(sim.player_slot(t, minion.target)) + 1
			place.gap_sq = dmath.length_sq(sim.player_data(t, minion.target).pos.xz - minion.pos.xz)
		}
		t.world.queues[handle.index] = place
	}
	obstacles := obstacles_of(t)
	mark_in_way(t, sim.slice(&obstacles), true) // a minion in no marked cell is in no obstacle's way: it skips them
	decay := dmath.exp_decay(KNOCK_DECAY, t.dt)
	floor := floor_of(t)
	minions := sim.iterate(&t.state.minions)
	for minion, handle in sim.next(&minions) do move_minion(t, floor, minion, handle, sim.slice(&obstacles), decay)
	mark_in_way(t, sim.slice(&obstacles), false)
}

// Sets (or clears) World.in_way over the grid's cells each obstacle's reach (its radius and a minion's) touches.
@(private = "file")
mark_in_way :: proc(t: ^Tick, obstacles: []Obstacle, value: bool) {
	grid := &t.world.grid
	for obstacle in obstacles {
		reach := obstacle.radius + MINION_RADIUS + GRID_BOX_PAD
		first_column, first_row := sim.grid_cell(grid, obstacle.pos - reach)
		last_column, last_row := sim.grid_cell(grid, obstacle.pos + reach)
		for row in first_row ..= last_row {
			for column in first_column ..= last_column do t.world.in_way[row * grid.columns + column] = value
		}
	}
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
			if staggered(minion) || !in_reach(t, minion) do continue
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

// The live minions into the World's grid, in table order, so a cell's minions come in index order: scratch, rebuilt
// by each pass that asks it (the moves; the strikes after the step, strike_grid).
build_grid :: proc(t: ^Tick) {
	fill_grid(&t.world.grid, floor_of(t), &t.state.minions)
}

// The grid of the minions where the physics step left them, built by the tick's first strike query (a tick whose
// strikes ask nothing builds none) and kept for the rest of the strikes: World.strike_grid, cleared as they begin.
strike_grid :: proc(t: ^Tick) -> ^Minion_Grid {
	if !t.world.strike_grid do build_grid(t)
	t.world.strike_grid = true
	return &t.world.grid
}

// `minions` (the live ones) into `grid`, laid over `floor`'s mesh (its grid_origin, columns and rows).
fill_grid :: proc(grid: ^Minion_Grid, floor: ^Floor, minions: ^sim.Table(Minion, MAX_MINIONS)) {
	sim.grid_begin(grid, floor.grid_origin, MINION_GRID_CELL, floor.grid_columns, floor.grid_rows)
	walk := sim.iterate(minions)
	for minion, handle in sim.next(&walk) {
		if minion.phase != .Dying do sim.grid_add(grid, i32(handle.index), minion.pos.xz)
	}
	sim.grid_end(grid)
}

// Every live minion within `reach` of `centre` on the floor plan where the physics step left them (every strike's
// query: a blow, a burst, a bolt's segment, a thrown prop): the strike grid's cells over the reach (padded by
// GRID_BOX_PAD), each minion measured exactly. Walk it with next_within.
minions_within :: proc(t: ^Tick, centre: [2]f32, reach: f32) -> Minions_Within {
	return walk_within(strike_grid(t), &t.state.minions, centre, reach)
}

// The walk minions_within makes, over `grid` filled with `minions` (fill_grid): a test's own grid, say.
walk_within :: proc(
	grid: ^Minion_Grid,
	minions: ^sim.Table(Minion, MAX_MINIONS),
	centre: [2]f32,
	reach: f32,
) -> Minions_Within {
	return {
		box      = sim.grid_box(grid, centre - (reach + GRID_BOX_PAD), centre + (reach + GRID_BOX_PAD)),
		centre   = centre,
		reach_sq = reach * reach,
		minions  = minions,
	}
}

// The walk's next live minion within its reach; ok is false past the last.
next_within :: proc(walk: ^Minions_Within) -> (minion: ^Minion, handle: sim.Handle(Minion), ok: bool) {
	for {
		for walk.at < len(walk.row) {
			index := walk.row[walk.at]
			walk.at += 1
			minion, handle, _ = sim.item_at(walk.minions, int(index))
			within := dmath.length_sq(minion.pos.xz - walk.centre) <= walk.reach_sq
			if minion.phase != .Dying && within do return minion, handle, true
		}
		walk.row = sim.grid_box_next(&walk.box) or_return
		walk.at = 0
	}
}

// What minions are pushed out of this tick: every present hero's capsule, every prop held or at rest, every live
// elite's capsule, the hoard, and the lift's shaft once the deck has gone down.
@(private = "file")
obstacles_of :: proc(t: ^Tick) -> (obstacles: sim.List(Obstacle, PLAYERS + MAX_PROPS + MAX_ELITES + 2)) {
	heroes := sim.iterate_present(t)
	for hero in sim.next(&heroes) do sim.append(&obstacles, Obstacle{hero.pos.xz, HERO_RADIUS})
	props := sim.iterate(&t.state.props)
	for prop in sim.next(&props) {
		if !prop_in_the_way(t.world.phys, prop) do continue
		centre := physics.body_position(t.world.phys, prop.body)
		sim.append(&obstacles, Obstacle{centre.xz, PROP_SPECS[prop.kind].footprint})
	}
	elites := sim.iterate(&t.state.elites)
	for elite in sim.next(&elites) {
		if elite.phase != .Dying do sim.append(&obstacles, Obstacle{elite.pos.xz, ELITE_RADIUS})
	}
	// ---- the hoard and the lift (hoard.odin, lift.odin): the deck's walkable while it is up; gone down, its shaft
	// is kept clear (the navigation still has the deck's floor)
	if hoard := &t.state.hoard; hoard.body != {} {
		sim.append(&obstacles, Obstacle{physics.body_position(t.world.phys, hoard.body).xz, HOARD_FOOTPRINT})
	}
	if lift := &t.state.lift; lift.body != {} && lift_gone(t) {
		sim.append(&obstacles, Obstacle{floor_of(t).places.lift.path.points[0].xz, LIFT_SHAFT_REACH})
	}
	return
}

// One minion's move: its own velocity (toward its target while chasing), its neighbours' push and its knockback
// (`decay` is what a tick leaves of it), along the mesh; then out of what is in its way, along the mesh too. Its `vel`
// is what it moved.
@(private = "file")
move_minion :: proc(
	t: ^Tick,
	floor: ^Floor,
	minion: ^Minion,
	handle: sim.Handle(Minion),
	obstacles: []Obstacle,
	decay: f32,
) {
	from := minion.pos
	velocity := minion.knock
	reeling := staggered(minion) // before the decay: the knock that moves it this tick
	minion.knock *= decay
	heading: [2]f32 // where its chase walks ({}: it walks at nothing)
	// Well in reach already (MINION_STAND inside it), it stands where it is to swing: pressing on to the hero would crowd
	// the front row inward, and a ring shrinks as it closes.
	if minion.phase == .Chase && minion.target != {} && !reeling && !in_reach(t, minion, MINION_STAND) {
		// Steered every tick within STEER_NEAR of its target (the last turns are quick), in its chase's first
		// STEER_TICKS (it woke, rose, ended a swing or took a new target: its facing says nothing of the way yet), and
		// while the target is off the floor (no field: it stands); otherwise every STEER_TICKS (sliced by its index),
		// walking its facing between: the heading a steer up to three ticks old gave, kept in the state, so a rollback
		// resumes it.
		spot := t.world.hero_spots[sim.player_slot(t, minion.target)]
		heading = minion.facing
		near := dmath.length_sq(spot.point.xz - minion.pos.xz) < STEER_NEAR * STEER_NEAR
		fresh := u32(t.time - minion.since) < STEER_TICKS
		if near || fresh || spot.poly == nav.NO_POLY || sim.due(t, handle.index, STEER_TICKS) {
			field := nav.field(&floor.fields, spot.poly)
			next := nav.steer(&floor.mesh, field, minion.poly, minion.pos, spot.point)
			heading = dmath.normalize((next - minion.pos).xz)
			if heading != {} do minion.facing = heading
		}
	}
	if minion.phase != .Dying && minion.phase != .Rise {
		push, chase := neighbours(t, minion, handle, heading * MINION_SPEED)
		velocity += chase + push
	}
	if velocity != {} {
		to := minion.pos + {velocity.x, 0, velocity.y} * t.dt
		minion.poly, minion.pos = nav.move(&floor.mesh, minion.poly, minion.pos, to)
	}
	if minion.phase != .Dying && t.world.in_way[sim.grid_cell_index(&t.world.grid, minion.pos.xz)] {
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
			minion.poly, minion.pos = nav.move(&floor.mesh, minion.poly, minion.pos, {out.x, minion.pos.y, out.y})
		}
	}
	minion.vel = (minion.pos - from) * TICK_HZ
}

// A minion's place in its hero's queue when the moves began (World.queues): which hero's (its slot + 1; 0: in none)
// and how far from it, squared. One is ahead of another in a queue when it is in the same one and nearer its hero
// (ties by row): a strict order, so no two ever wait for each other.
Queue_Place :: struct {
	gap_sq: f32,
	hero:   i32,
}

// A neighbour within QUEUE_REACH, as neighbours' second look sees it: the way to it, how close (0 at QUEUE_REACH, 1
// at QUEUE_STOP and nearer), and whether it is ahead in the chaser's own queue.
@(private = "file")
Queued :: struct {
	toward:    [2]f32,
	closeness: f32,
	ahead:     bool,
	behind:    bool, // in the chaser's own queue, farther from the hero: it will wait, so it doesn't block a step aside
}

// The live minions within QUEUE_REACH where the moves began (World.starts: so nothing depends on which neighbours
// moved before it): their push apart, those within SEPARATION, at most SEPARATION_SPEED (two on the same spot part by
// index); and the chase `wanted` (its heading at MINION_SPEED) as the queue lets it walk. The push alone can't hold a
// crowd apart (the chase outruns it), so a chaser gives way: the part of its chase toward each close neighbour goes,
// as much as the neighbour is close (from QUEUE_REACH to all of it at QUEUE_STOP), so it slides round the one in its
// way; then, if the slide still heads at a close one, it waits as much as the closest is close. The back rows stop
// behind the front instead of pressing it onto the hero, and the front fills the ring round it.
@(private = "file")
neighbours :: proc(
	t: ^Tick,
	minion: ^Minion,
	handle: sim.Handle(Minion),
	wanted: [2]f32,
) -> (
	push: [2]f32,
	chase: [2]f32,
) {
	chase = wanted
	queueing := wanted != {} // one that walks at nothing only keeps apart
	reach := QUEUE_REACH if queueing else SEPARATION
	close: [QUEUE_NEIGHBOURS]Queued // the neighbours within QUEUE_REACH, for the second look
	closes := 0
	mine := t.world.queues[handle.index]
	for row in sim.grid_near(&t.world.grid, minion.pos.xz) {
		for other_index in row {
			if other_index == i32(handle.index) do continue
			away := minion.pos.xz - t.world.starts[other_index]
			distance_sq := dmath.length_sq(away)
			if distance_sq >= reach * reach do continue
			if distance_sq < 0.0001 {
				away = {other_index < i32(handle.index) ? 0.01 : -0.01, 0} // stacked exactly: the later one steps aside
				distance_sq = 0.0001
			}
			distance := dmath.sqrt(distance_sq)
			if distance < SEPARATION do push += away * ((SEPARATION - distance) / distance)
			if !queueing || closes == QUEUE_NEIGHBOURS do continue
			toward := -away / distance
			closeness := dmath.clamp((QUEUE_REACH - distance) / (QUEUE_REACH - QUEUE_STOP), 0, 1)
			if along := dmath.dot(chase, toward); along > QUEUE_ALONG do chase -= toward * (along * closeness) // slide by
			theirs := t.world.queues[other_index]
			nearer := theirs.gap_sq < mine.gap_sq || (theirs.gap_sq == mine.gap_sq && other_index < i32(handle.index))
			same := mine.hero != 0 && theirs.hero == mine.hero
			close[closes] = {toward, closeness, same && nearer, same && !nearer}
			closes += 1
		}
	}
	// Held up, it steps sideways (to its clearer side, ties by row), as much as it was held and that side is clear (those
	// behind it in its queue don't count: they wait for it): a column fans out round its hero, and a chaser passes a
	// sleeper in its way instead of standing behind it.
	if held := 1 - dmath.length(chase) / MINION_SPEED; queueing && closes > 0 && held > QUEUE_HELD {
		left := [2]f32{-wanted.y, wanted.x} / MINION_SPEED
		left_close, right_close: f32
		for queued in close[:closes] {
			if queued.behind do continue
			across := dmath.dot(left, queued.toward)
			// as much as it is close and lies that way (one mostly ahead hardly blocks a step aside)
			if across > QUEUE_ALONG do left_close = dmath.max(left_close, queued.closeness * across)
			if across < -QUEUE_ALONG do right_close = dmath.max(right_close, queued.closeness * -across)
		}
		side, side_close := left, left_close
		if right_close < left_close || (right_close == left_close && handle.index % 2 == 1) {
			side, side_close = -left, right_close
		}
		chase += side * (MINION_SPEED * QUEUE_SIDE * held * (1 - side_close))
	}
	// The slide and the step may head at a close one again: it waits for it, as much as it is close and only along the
	// way to it (the part past it stays), but for those behind it in its queue, which wait for it instead.
	for _ in 0 ..< QUEUE_PASSES { 	// each pass may head it at an earlier one again: a few passes settle it
		waited := false
		for queued in close[:closes] {
			along := dmath.dot(chase, queued.toward)
			if along > QUEUE_ALONG {
				chase -= queued.toward * (along * queued.closeness)
				waited = true
			}
		}
		if !waited do break // a pass that changed nothing: the next would change nothing either
	}
	return dmath.clamp_length(push * SEPARATION_SPEED, SEPARATION_SPEED), chase
}

// Whether a minion reels from a knock (faster than KNOCK_STAGGER): it walks at nothing and its swings miss.
staggered :: proc(minion: ^Minion) -> bool {
	return dmath.length_sq(minion.knock) > KNOCK_STAGGER * KNOCK_STAGGER
}

// `source`'s blast at `at` (a bolt's burst, a fireball's, a charging shield, a heaved body's landing): every live
// minion within `radius` on the floor plan that no wall shields (a ray from `at` to its chest) other than `skip` takes
// `damage` and is knocked away from `at`, at `knock` at the centre falling off to BLAST_RIM of it at the rim (dot
// products and one sqrt a minion, no trig), in the strikes' order (minions_within). Through damage_minion, so a pile of
// blasts knocks no faster than KNOCK_MAX. The elites in it take the same, other than `skip_elite`, a Warrior's guard
// broken first when `breaks_guard` (knock_elites).
knock_area :: proc(
	t: ^Tick,
	at: [3]f32,
	radius: f32,
	damage: i16,
	knock: f32,
	player: sim.Player,
	source: Hit_Source,
	skip: sim.Handle(Minion) = {},
	skip_elite: sim.Handle(Elite) = {},
	breaks_guard := false,
) {
	walk := minions_within(t, at.xz, radius)
	for minion, handle in next_within(&walk) {
		if handle == skip do continue
		target := minion.pos + {0, CHEST_HEIGHT, 0}
		if _, walled := physics.world_cast_ray_closest(t.world.phys, at, target - at, SIGHT_FILTER); walled do continue
		offset := minion.pos.xz - at.xz
		distance := dmath.length(offset)
		away := offset / distance if distance > 0 else [2]f32{1, 0}
		damage_minion(t, handle, damage, away, knock * (1 - (1 - BLAST_RIM) * distance / radius), player, source)
	}
	knock_elites(t, at, radius, damage, knock, player, source, skip_elite, breaks_guard)
}

// Whether a minion's target is close enough to swing at: its capsule within MINION_REACH of the minion's circle (less
// `inside`).
@(private = "file")
in_reach :: proc(t: ^Tick, minion: ^Minion, inside: f32 = 0) -> bool {
	if minion.target == {} do return false
	reach := MINION_RADIUS + HERO_RADIUS + MINION_REACH - inside
	return dmath.length_sq(sim.player_data(t, minion.target).pos.xz - minion.pos.xz) <= reach * reach
}

// The swing lands: on the target if it is still up, in reach, in front of the facing the swing locked, and in sight
// (no wall between them).
@(private = "file")
strike :: proc(t: ^Tick, minion: ^Minion) {
	if staggered(minion) || !hero_up(t, minion.target) || !in_reach(t, minion) do return
	hero := sim.player_data(t, minion.target)
	to_hero := dmath.normalize(hero.pos.xz - minion.pos.xz)
	if to_hero != {} && dmath.dot(to_hero, minion.facing) < MINION_STRIKE_COS do return
	eye, seen := minion.pos + {0, EYE_HEIGHT, 0}, hero.pos + {0, EYE_HEIGHT, 0}
	if _, walled := physics.world_cast_ray_closest(t.world.phys, eye, seen - eye, SIGHT_FILTER); walled do return
	damage_hero(t, minion.target, MINION_DAMAGE, minion.pos)
}
