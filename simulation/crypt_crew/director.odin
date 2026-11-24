// The director: where minions come from. Packs sleep where the floor's `pack` markers put them (made when the party
// enters the floor) until a hero comes into sight; surges rise from graves on the clock, at graves far enough from
// every hero that they rise off screen and near enough to reach the party, picked by keyed rolls (the clock decides,
// never a command, so a roll named by the tick is the same on every peer and every re-simulation). A cap bounds the
// living. The standard benchmark holds a population instead (bench_prepare).
package crypt_crew

import "unified:dmath"
import "unified:nav"
import "unified:physics"
import "unified:sim"

// What the sim's keyed rolls are for (sim.roll_below's purpose).
Roll :: enum u8 {
	Pack_Angle,
	Pack_Distance,
	Surge_Grave,
	Surge_Angle,
	Surge_Distance,
}

ROLL_STEPS :: 4096 // a roll for a fraction draws one of this many steps

// A surge rose: `count` minions, the floor's `surge`-th.
Event_Surge :: struct {
	count: i32,
	surge: u32,
}

// What a hero's sight of a minion is blocked by: walls (low cover is seen over).
SIGHT_FILTER :: physics.Filter {
	category = CAT_HERO,
	mask     = CAT_WALL,
}

// A fraction in [0, 1) of a roll at tick 0, named by `purpose`, `key` and `index`: the same whenever it is rolled.
@(private = "file")
roll_fraction :: proc(seed: u64, purpose: Roll, key: u64, index: int) -> f32 {
	return f32(sim.roll_below_at(seed, 0, ROLL_STEPS, purpose, key, index)) / ROLL_STEPS
}

// Each pack's minions, asleep within PACK_RADIUS of its marker, each on the walkable floor and facing its own way: the
// offsets are keyed rolls naming tick 0 and the marker, so a pack stands the same on every entry to the floor.
spawn_packs :: proc(t: ^Tick) {
	for &pack in sim.slice(&t.world.places.packs) {
		for i in 0 ..< int(pack.count) {
			facing := dmath.angle_vec(roll_fraction(t.seed, .Pack_Angle, u64(pack.marker), i))
			distance := PACK_RADIUS * dmath.sqrt(roll_fraction(t.seed, .Pack_Distance, u64(pack.marker), i))
			spot, ok := floor_spot(t.world, pack.pos + {facing.x, 0, facing.y} * distance, PACK_RADIUS)
			if ok do spawn_minion(t.state, spot.point, spot.poly, facing, .Idle, t.time)
		}
	}
}

// Each sleeping minion looks every SIGHT_TICKS (sliced by its index): a hero up within AGGRO_RADIUS that no wall hides
// wakes it, and it chases.
wake_packs :: proc(t: ^Tick) {
	minions := sim.iterate(&t.state.minions)
	for minion, handle in sim.next(&minions) {
		if minion.phase != .Idle || !sim.due(t, handle.index, SIGHT_TICKS) do continue
		eye := minion.pos + {0, EYE_HEIGHT, 0}
		heroes := sim.iterate_present(t)
		for hero, player in sim.next(&heroes) {
			if !hero_up(t, player) do continue
			seen := hero.pos + {0, EYE_HEIGHT, 0}
			if dmath.length_sq(seen - eye) > AGGRO_RADIUS * AGGRO_RADIUS do continue
			if _, blocked := physics.world_cast_ray_closest(t.world.phys, eye, seen - eye, SIGHT_FILTER); blocked do continue
			minion.phase, minion.since = .Chase, t.time
			break
		}
	}
}

// When the surge timer runs out (and a hero is up), a surge rises: SURGE_BASE plus SURGE_PER_HERO for each hero
// present, at most up to MINION_CAP alive, each at a grave whose path from every hero up is at least SURGE_NEAR and
// from the nearest at most SURGE_FAR (none such: no surge this time). Each minion's grave and its place beside it are
// keyed rolls naming the floor's surge count. The standard benchmark holds its population instead (hold_population).
raise_surges :: proc(t: ^Tick) {
	if t.state.held > 0 {
		hold_population(t)
		return
	}
	if sim.timer_running(t, t.state.surge) do return
	sim.timer_start(t, &t.state.surge, SURGE_EVERY_S)
	graves := surge_graves(t)
	if graves.count == 0 do return
	room := MINION_CAP - minions_alive(&t.state.minions)
	count := dmath.min(SURGE_BASE + SURGE_PER_HERO * sim.present_count(t), room)
	if count <= 0 do return
	t.state.surges += 1
	risen := 0
	for i in 0 ..< count {
		key := u64(t.state.surges)
		grave := sim.slice(&graves)[sim.roll_below(t, u32(graves.count), Roll.Surge_Grave, key, i)]
		risen += int(raise_minion(t, grave, Roll.Surge_Angle, Roll.Surge_Distance, key, i))
	}
	sim.emit(t, Event_Surge{count = i32(risen), surge = t.state.surges})
}

// The graves a surge may rise at now, by index into the World's: those at least SURGE_NEAR along the floor from every
// hero up, and at most SURGE_FAR from the nearest.
surge_graves :: proc(t: ^Tick) -> (graves: sim.List(int, MAX_GRAVES)) {
	for &grave, i in sim.slice(&t.world.places.graves) {
		nearest := nav.UNREACHABLE
		heroes := sim.iterate_present(t)
		for _, player in sim.next(&heroes) {
			spot := t.world.hero_spots[sim.player_slot(t, player)]
			if spot.poly == nav.NO_POLY do continue
			nearest = dmath.min(nearest, nav.field(&t.world.fields, spot.poly).cost[grave.poly])
		}
		if nearest >= SURGE_NEAR && nearest <= SURGE_FAR do sim.append(&graves, i)
	}
	return
}

// A minion rising within SURGE_SPREAD of grave `grave` (an index into the World's), at a place on the walkable floor
// picked by rolls named `angle`, `distance`, `key` and `index`; false when none is there or the table is full.
@(private = "file")
raise_minion :: proc(t: ^Tick, grave: int, angle, distance: Roll, key: u64, index: int) -> bool {
	at := sim.slice(&t.world.places.graves)[grave].point
	facing := dmath.angle_vec(f32(sim.roll_below(t, ROLL_STEPS, angle, key, index)) / ROLL_STEPS)
	reach := SURGE_SPREAD * dmath.sqrt(f32(sim.roll_below(t, ROLL_STEPS, distance, key, index)) / ROLL_STEPS)
	spot := floor_spot(t.world, at + {facing.x, 0, facing.y} * reach, SURGE_SPREAD) or_return
	return spawn_minion(t.state, spot.point, spot.poly, facing, .Rise, t.time)
}

// The benchmark's population (State.held): the minions it lost rise again at graves, one grave by roll for each.
@(private = "file")
hold_population :: proc(t: ^Tick) {
	graves := t.world.places.graves.count
	missing := int(t.state.held) - minions_alive(&t.state.minions)
	for i in 0 ..< missing {
		grave := int(sim.roll_below(t, u32(graves), Roll.Surge_Grave, 0, i))
		raise_minion(t, grave, Roll.Surge_Angle, Roll.Surge_Distance, 0, i)
	}
}

// The standard benchmark's population (sim.Game.bench_prepare): `count` minions chasing from places on the walkable
// floor around the first room, held at that many alive (State.held) instead of the surges.
bench_prepare :: proc(state: ^State, world: ^World, count: int) {
	state.held = u32(count)
	rng := sim.rng_seed(u64(count))
	start := world.places.hero_spawns[0]
	for placed, tries := 0, 0; placed < count && tries < count * BENCH_TRIES; tries += 1 {
		offset := [2]f32 {
			f32(sim.rng_below(&rng, BENCH_SPREAD * 200)) / 100 - BENCH_SPREAD, // whole centimetres
			f32(sim.rng_below(&rng, BENCH_SPREAD * 200)) / 100 - BENCH_SPREAD,
		}
		spot := floor_spot(world, start + {offset.x, 0, offset.y}, 1) or_continue
		if !spawn_minion(state, spot.point, spot.poly, {0, 1}, .Chase, 0) do break
		placed += 1
	}
}
