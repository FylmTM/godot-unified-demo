// The director: where minions come from. Packs sleep where the floor's `pack` markers put them (their places are the
// World's, laid out in world_create) until a hero comes into sight or one of them is hit, and then the whole pack
// wakes; surges rise from graves on the surge clock, at graves out of sight of every hero and near enough to reach the
// party.
// That clock is game time, which a pause (a command) holds, so the tick a surge rises on depends on when commands
// landed: its rolls name state, never the tick (unified/docs/gameplay.md, Randomness). Each raised minion's rolls are
// keyed by the session's count of them (State.rises), which no restart rewinds. A surge is a quota (State.rising)
// that rises a few a tick, at most one per grave per RISE_GAP_TICKS, each riser where no live minion stands within
// SEPARATION (a grave with no such place lets its turn pass), so no tick raises hundreds and no riser climbs out on
// another. The floor's cap bounds the living (Floor.minion_cap), and a raise never asks for more rows than the table
// has free: the dying keep theirs for DEATH_S, so after a mass death the alive are few while the table is full.
// A held crowd (Setup.crowd: the benchmark rows', the scale tests', a look at hundreds) replaces packs and surges: a
// population placed on the first tick (place_crowd) and held alive, the felled rising again at the graves
// (refill_held).
package crypt_crew

import "unified:dmath"
import "unified:nav"
import "unified:physics"
import "unified:sim"

// What the sim's keyed rolls are for (sim.roll_below_at's purpose).
Roll :: enum u8 {
	Pack_Facing, // a pack member's facing
	Rise_Angle, // its direction from the grave, and its facing
	Rise_Distance, // its distance from the grave
	Crowd_Place, // where a held crowd's minions stand (a stream: place_crowd's at key 0, a sleeping refill's after)
	Drop, // a felled minion's drop: whether it drops (index 0) and its value (1), keyed by State.drops (loot.odin)
	Boon, // a hero's boons offered at a choice, keyed by its player and indexed by the run and the choice (boons.odin)
}

// A held crowd (Setup.crowd, which the rules and the scripted player read): what the population does while it is held.
// Its heroes take no damage (but under Wipe), none of them going down wipes the party (a restart would empty the
// floor), and the scripted player sends no dev command and no pause, so the population stays what was asked.
Crowd :: enum u8 {
	None, // play: the director's packs and surges
	Idle, // asleep out of the heroes' sight, the scripted heroes standing still: what sleepers cost
	Chase, // chasing scripted heroes who walk and never attack: what a crowd on the move costs
	Fight, // around scripted heroes who walk and hold Attack: blows, bursts, deaths and the felled rising again
	// The fight, its heroes taking the crowd's blows: they go down as ragdolls under it one by one, and lie there
	// (nobody revives them, no wipe restarts the floor): what the most ragdolls a party has cost under a crowd.
	Wipe,
}

ROLL_STEPS :: 4096 // a roll for a fraction draws one of this many steps

// A surge began: `count` minions owed (its quota, rising over the next ticks), the session's `surge`-th.
Event_Surge :: struct {
	count: i32,
	surge: u32,
}

// A sleeping minion's place, laid out in world_create (pack_places): on the walkable floor, at least SEPARATION from
// the rest of its pack, facing its own way.
Pack_Place :: struct {
	spot:   Nav_Point,
	facing: [2]f32,
	pack:   u8, // its pack's index + 1 (Minion.pack)
}

// A fraction in [0, 1) of a roll named by `purpose`, `key` and `index` at tick 0: the same whenever it is rolled.
roll_fraction :: proc(seed: u64, purpose: Roll, key: u64, index: int) -> f32 {
	return f32(sim.roll_below_at(seed, 0, ROLL_STEPS, purpose, key, index)) / ROLL_STEPS
}

// Every pack's sleeping places (world_create): member 0 on the marker, the next 6 on a ring PACK_SPACING around it,
// the next 12 on one twice as far, and so on; the rings turned by the first of PACK_TURNS steps at which every member
// stands on the walkable floor (moved at most PACK_SNAP onto it) and SEPARATION from the rest. The layout depends on
// the level alone, so a pack that fits no turn fails every session alike: a level problem, asserted, never a member
// silently dropped. Each member faces its own way, a roll keyed by the marker.
pack_places :: proc(floor: ^Floor, seed: u64) {
	for &pack, index in sim.slice(&floor.places.packs) {
		first := floor.pack_places.count
		fits := false
		for turn in 0 ..< PACK_TURNS {
			floor.pack_places.count = first // a try that doesn't fit is overwritten by the next
			fits = place_pack(floor, seed, &pack, u8(index + 1), f32(turn) / PACK_TURNS)
			if fits do break
		}
		assert(fits, "crypt_crew: a pack's minions don't fit on the floor around its marker: move the marker")
	}
}

// One try of pack_places: the pack's members on rings turned by `turn` (in turns); false when one is off the floor or
// too near another.
@(private = "file")
place_pack :: proc(floor: ^Floor, seed: u64, pack: ^Pack_Def, number: u8, turn: f32) -> bool {
	first := int(floor.pack_places.count)
	ring, on_ring, ring_size := 0, 0, 1
	for i in 0 ..< int(pack.count) {
		if on_ring == ring_size do ring, on_ring, ring_size = ring + 1, 0, 6 * (ring + 1)
		dir := dmath.angle_vec(turn + f32(on_ring) / f32(ring_size))
		on_ring += 1
		at := pack.pos + [3]f32{dir.x, 0, dir.y} * (f32(ring) * PACK_SPACING)
		spot := floor_spot(floor, at, PACK_SNAP) or_return
		for &other in sim.slice(&floor.pack_places)[first:] {
			if dmath.length_sq(other.spot.point.xz - spot.point.xz) < SEPARATION * SEPARATION do return false
		}
		facing := dmath.angle_vec(roll_fraction(seed, .Pack_Facing, u64(pack.marker), i))
		added := sim.append(&floor.pack_places, Pack_Place{spot = spot, facing = facing, pack = number})
		assert(added, "crypt_crew: more pack minions than MAX_PACK_MINIONS")
	}
	return true
}

// Every pack's minions, asleep in their places (entering a floor).
spawn_packs :: proc(t: ^Tick) {
	for &place in sim.slice(&floor_of(t).pack_places) {
		spawn_minion(t.state, place.spot.point, place.spot.poly, place.facing, .Idle, t.time, place.pack)
	}
}

// Each sleeping minion looks every SIGHT_TICKS (sliced by its index): a hero up within AGGRO_RADIUS that no wall hides
// wakes it, and its pack with it.
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
			_, walled := physics.world_cast_ray_closest(t.world.phys, eye, seen - eye, SIGHT_FILTER)
			if walled do continue
			wake(t, minion)
			break
		}
	}
}

// When the surge clock runs out (and a grave is eligible), a surge is owed (State.rising): surge_size's (run.odin: the
// crypt's SURGE_BASE, SURGE_PER_HERO for each hero present, SURGE_GROWTH for each surge faced on this floor and
// SURGE_PER_DEPTH for each floor gone down, or the Pit's wave, times the difficulty's), at most up to the floor's cap
// alive and into the table's free rows, less what earlier surges still owe. Every tick the owed rise (rise_owed) at
// surge_graves', up to the cap alive. A held population is refilled instead (refill_held), and gets no elite. Nothing
// rises while the director rests (director_runs, run.odin: the hub, a run's end, the Pit's lull).
raise_surges :: proc(t: ^Tick) {
	if t.state.held > 0 {
		refill_held(t)
		return
	}
	if !director_runs(t) do return
	due := !sim.timer_running(t, t.state.surge)
	if !due && t.state.rising == 0 do return
	graves := surge_graves(t)
	if due {
		sim.timer_start_ticks(t, &t.state.surge, surge_clock(t)) // the floor's (surge_every) or the Pit's (run.odin)
		owed := int(t.state.rising)
		room := dmath.min(floor_of(t).minion_cap - minions_alive(&t.state.minions), free_rows(&t.state.minions))
		wanted := surge_size(t) // run.odin
		if count := dmath.min(wanted, room - owed); count > 0 && graves.count > 0 {
			t.state.surges += 1
			t.state.floor_surges += 1
			t.state.rising += u32(count)
			sim.emit(t, Event_Surge{count = i32(count), surge = t.state.surges})
			raise_surge_elite(t, sim.slice(&graves)) // every elite_every-th brings an elite (elites.odin)
		}
	}
	if t.state.rising == 0 do return
	room := floor_of(t).minion_cap - minions_alive(&t.state.minions)
	t.state.rising -= u32(rise_owed(t, sim.slice(&graves), dmath.min(int(t.state.rising), room), .Rise))
}

// The graves a surge may rise at now, by index into the floor's: those at least SURGE_NEAR in a straight line from
// every hero up (off screen), and at most SURGE_FAR along the floor from the nearest (it reaches the party).
surge_graves :: proc(t: ^Tick) -> (graves: sim.List(int, MAX_GRAVES)) {
	floor := floor_of(t)
	for &grave, i in sim.slice(&floor.places.graves) {
		nearest := nav.UNREACHABLE
		out_of_sight := true
		heroes := sim.iterate_present(t)
		for hero, player in sim.next(&heroes) {
			spot := t.world.hero_spots[sim.player_slot(t, player)]
			if spot.poly == nav.NO_POLY do continue
			out_of_sight &= dmath.length_sq(grave.point.xz - hero.pos.xz) >= SURGE_NEAR * SURGE_NEAR
			nearest = dmath.min(nearest, nav.field(&floor.fields, spot.poly).cost[grave.poly])
		}
		if out_of_sight && nearest <= SURGE_FAR do sim.append(&graves, i)
	}
	return
}

// Up to `count` minions in `phase` rising this tick into the table's free rows: one at each of `graves` (indices into
// the floor's) whose turn it is (one in RISE_GAP_TICKS, sliced by its index), in their order; so a tick raises at most
// as many as there are graves on their turn. How many rose (a grave with no free place lets its turn pass).
@(private = "file")
rise_owed :: proc(t: ^Tick, graves: []int, count: int, phase: Minion_Phase) -> int {
	budget := dmath.min(count, free_rows(&t.state.minions)) // taken first: each raise takes a row
	raised := 0
	for grave in graves {
		if raised >= budget do break
		if sim.due(t, grave, RISE_GAP_TICKS) && raise_minion(t, grave, phase) do raised += 1
	}
	return raised
}

// A minion in `phase` (Rise; a sleeping crowd's Idle) within SURGE_SPREAD of grave `grave` (an index into the
// floor's), at the first of RISE_TRIES places (each rolled by the session's count of raises and the try) on the
// walkable floor with no live minion within SEPARATION, facing its roll; false when none is free or the table is full.
@(private = "file")
raise_minion :: proc(t: ^Tick, grave: int, phase: Minion_Phase) -> bool {
	key := u64(t.state.rises)
	t.state.rises += 1
	floor := floor_of(t)
	tries: for try in 0 ..< RISE_TRIES {
		facing := dmath.angle_vec(roll_fraction(t.seed, .Rise_Angle, key, try))
		reach := SURGE_SPREAD * dmath.sqrt(roll_fraction(t.seed, .Rise_Distance, key, try))
		at := sim.slice(&floor.places.graves)[grave].point + [3]f32{facing.x, 0, facing.y} * reach
		spot := floor_spot(floor, at, SURGE_SPREAD) or_continue
		minions := sim.iterate(&t.state.minions)
		for minion in sim.next(&minions) {
			near := dmath.length_sq(minion.pos.xz - spot.point.xz) < SEPARATION * SEPARATION
			if minion.phase != .Dying && near do continue tries
		}
		_, raised := spawn_minion(t.state, spot.point, spot.poly, facing, phase, t.time)
		return raised
	}
	return false
}

// A held population (State.held): the minions it lost come back, a few a tick into the table's free rows (the dying
// hold theirs: raising against the alive alone would try, and fail, a raise per missing minion every tick until the
// dead are gone). A fighting or chasing crowd's rise at the graves (rise_owed); a sleeping crowd's are placed asleep as
// place_crowd places them, out of sight (a sleeper never leaves its grave's side, so graves would fill), one for each
// grave on its turn, so both come back at the same pace.
@(private = "file")
refill_held :: proc(t: ^Tick) {
	floor := floor_of(t)
	missing := dmath.min(int(t.state.held) - minions_alive(&t.state.minions), free_rows(&t.state.minions))
	if missing <= 0 do return
	graves: sim.List(int, MAX_GRAVES)
	for _, i in sim.slice(&floor.places.graves) do sim.append(&graves, i)
	if t.setup.crowd != .Idle {
		rise_owed(t, sim.slice(&graves), missing, .Rise)
		return
	}
	turns := 0
	for grave in sim.slice(&graves) do turns += int(sim.due(t, grave, RISE_GAP_TICKS))
	if turns == 0 do return
	rng := sim.rng_keyed(t.seed, Roll.Crowd_Place, u64(t.state.rises) + 1) // 0 is place_crowd's own stream
	t.state.rises += 1
	place_more(t, &rng, dmath.min(missing, turns))
}

// The table's free rows: what may be raised now, whatever the alive.
free_rows :: proc(minions: ^sim.Table(Minion, MAX_MINIONS)) -> int {
	return MAX_MINIONS - int(minions.count)
}

// `count` minions held alive (State.held) as the session's crowd does (Setup.crowd): placed on the walkable floor,
// each at least SEPARATION from the rest and clear of the props (which would push it out onto a neighbour); asleep
// (each alone, no pack) at least CROWD_IDLE_CLEAR from every hero_spawn, out of sight, or chasing at least CROWD_CLEAR
// from them. Places are drawn uniformly over the floor's area (floor_point) from a stream keyed by the session's seed,
// so the crowd spreads over the whole floor whatever its shape; fewer stand when the floor has no room for `count`
// (CROWD_TRIES draws each), and refill_held raises the rest at the graves.
place_crowd :: proc(t: ^Tick, count: int) {
	t.state.held = u32(count)
	rng := sim.rng_keyed(t.seed, Roll.Crowd_Place)
	place_more(t, &rng, count)
}

// Up to `count` of the held crowd placed as place_crowd says, drawn from `rng`; how many stood.
@(private = "file")
place_more :: proc(t: ^Tick, rng: ^sim.Rng, count: int) -> (placed: int) {
	floor := floor_of(t)
	asleep := t.setup.crowd == .Idle
	clear := CROWD_IDLE_CLEAR if asleep else CROWD_CLEAR
	tries: for try := 0; placed < count && try < count * CROWD_TRIES; try += 1 {
		spot := floor_point(floor, rng)
		facing := dmath.angle_vec(f32(sim.rng_below(rng, ROLL_STEPS)) / ROLL_STEPS)
		for spawn in floor.places.hero_spawns {
			if dmath.length_sq(spawn.xz - spot.point.xz) < clear * clear do continue tries
		}
		props := sim.iterate(&t.state.props)
		for prop in sim.next(&props) {
			reach := PROP_SPECS[prop.kind].footprint + MINION_RADIUS
			centre := physics.body_position(t.world.phys, prop.body)
			if dmath.length_sq(centre.xz - spot.point.xz) < reach * reach do continue tries
		}
		others := sim.iterate(&t.state.minions)
		for other in sim.next(&others) {
			if dmath.length_sq(other.pos.xz - spot.point.xz) < SEPARATION * SEPARATION do continue tries
		}
		_, ok := spawn_minion(t.state, spot.point, spot.poly, facing, .Idle if asleep else .Chase, t.time)
		if !ok do break
		placed += 1
	}
	return
}

// The standard benchmarks' population (sim.Game.bench_prepare), `count` minions held alive: the Setup's held crowd at
// that count instead of the floor's cap (the crowd rows); without one, a held surge among the props (a floor's own
// row): chasers from places within BENCH_SPREAD of slot 0's spawn, beside the floor's sleeping packs, and on the vault
// the King roused (its row is the fight's).
bench_prepare :: proc(t: ^Tick, count: int) {
	if t.setup.crowd != .None {
		sim.despawn_all(&t.state.minions)
		place_crowd(t, count)
		return
	}
	t.state.held = u32(count)
	rng := sim.rng_seed(u64(count))
	floor := floor_of(t)
	start := floor.places.hero_spawns[0]
	for placed, tries := 0, 0; placed < count && tries < count * BENCH_TRIES; tries += 1 {
		offset := [2]f32 {
			f32(sim.rng_below(&rng, u32(BENCH_SPREAD * 200))) / 100 - BENCH_SPREAD, // whole centimetres
			f32(sim.rng_below(&rng, u32(BENCH_SPREAD * 200))) / 100 - BENCH_SPREAD,
		}
		spot := floor_spot(floor, start + {offset.x, 0, offset.y}, 1) or_continue
		if _, ok := spawn_minion(t.state, spot.point, spot.poly, {0, 1}, .Chase, 0); !ok do break
		placed += 1
	}
	if king := boss_elite(t); king != nil do rouse_elite(t.world.phys, king, t.time)
}
