// What the rule tests share: playing and pressing on a headless.Run, and putting a hero, a prop or a minion where a
// test needs one (the run is pinned there: a sync-test never restores to before a test changed the state). Places come
// from the floor's markers (World.places), never from numbers copied out of the level.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// Floor 1's props the tests move, by marker order (game/levels/floor_1.tscn): its first barrel, its first room's crate
// and heavy crate.
BARREL :: 0
CRATE :: 2
HEAVY_CRATE :: 3

// The run's active floor (its navigation, places and cap).
floor_of :: proc(run: ^headless.Run(g.Game)) -> ^g.Floor {
	return &run.simulation.world.floors[run.simulation.state.level.id]
}

// Slot `slot`'s hero_spawn on the run's floor.
spawn_of :: proc(run: ^headless.Run(g.Game), slot: int) -> [3]f32 {
	return floor_of(run).places.hero_spawns[slot]
}

// `seconds` of play with these inputs by slot (the seated members present).
play :: proc(run: ^headless.Run(g.Game), inputs: [g.PLAYERS]g.Input, seconds: f32 = 1) {
	for _ in 0 ..< int(seconds * g.TICK_HZ) do headless.run_step(run, inputs)
}

// One tick of slot `slot` pressing `button` with `input`, then one with the button up again (the next press is an
// edge), the other seated slots idle.
press :: proc(run: ^headless.Run(g.Game), slot: int, button: g.Button, input: g.Input = {}) {
	inputs: [g.PLAYERS]g.Input
	inputs[slot] = input
	inputs[slot].buttons += {button}
	headless.run_step(run, inputs)
	inputs[slot].buttons -= {button}
	headless.run_step(run, inputs)
}

// One tick in which slot 0 hurts slot `slot`'s hero for `damage` (Command_Dev_Hurt).
hurt :: proc(run: ^headless.Run(g.Game), slot: int, damage: i16) {
	headless.run_command(run, 0, g.Command_Dev_Hurt{sim.player_in_slot(run.simulation, slot), damage})
}

// One idle tick, in which slot 0 revives every hero down (Command_Dev_Revive) when one is: for a test whose idle heroes
// minions fight, which must not see the floor restart (a downed hero stays down until revived, so they would wipe).
step_up :: proc(run: ^headless.Run(g.Game)) {
	heroes := sim.iterate_present(&run.simulation.state.players)
	for hero in sim.next(&heroes) {
		if hero.action == .Down {
			headless.run_command(run, 0, g.Command_Dev_Revive{})
			return
		}
	}
	headless.run_step(run)
}

// The hero faces `want` (to within a Dir2's quantization).
expect_facing :: proc(t: ^testing.T, hero: ^g.Hero, want: [2]f32, loc := #caller_location) {
	testing.expectf(t, dmath.length(hero.facing - want) < 1e-3, "faces %v, not %v", hero.facing, want, loc = loc)
}

// Moves slot `slot`'s hero to stand at `feet`, at rest, facing `facing`, and pins the run there.
place_hero :: proc(run: ^headless.Run(g.Game), slot: int, feet: [3]f32, facing := [2]f32{1, 0}) {
	hero := sim.slot_data(run.simulation, slot)
	physics.character_teleport(run.simulation.world.phys, &hero.body, feet + {0, g.HERO_CENTRE_ABOVE_FEET, 0})
	hero.pos, hero.facing = feet, facing
	headless.run_pin(run)
}

// The prop of marker `index` (the props are made in marker order), and its handle.
prop_at :: proc(run: ^headless.Run(g.Game), index: int) -> (^g.Prop, sim.Handle(g.Prop)) {
	walk := sim.iterate(&run.simulation.state.props)
	for prop, handle in sim.next(&walk) {
		if int(handle.index) == index do return prop, handle
	}
	return nil, {}
}

// Moves the prop of marker `index` to stand at rest on `floor_point`, unturned, and pins the run there.
place_prop :: proc(run: ^headless.Run(g.Game), index: int, floor_point: [3]f32) {
	prop, _ := prop_at(run, index)
	centre := floor_point + {0, g.PROP_SPECS[prop.kind].half.y, 0}
	physics.body_teleport(run.simulation.world.phys, prop.body, centre)
	headless.run_pin(run)
}

// A minion in `phase` on the walkable floor nearest `near`, facing `facing`, pinned there.
place_minion :: proc(
	run: ^headless.Run(g.Game),
	near: [3]f32,
	phase: g.Minion_Phase,
	facing := [2]f32{0, 1},
	pack: u8 = 0,
) -> sim.Handle(g.Minion) {
	spot, on_floor := g.floor_spot(floor_of(run), near, 2)
	assert(on_floor, "a test's minion is off the floor")
	state := &run.simulation.state
	handle, spawned := g.spawn_minion(state, spot.point, spot.poly, facing, phase, state.clock.time, pack)
	assert(spawned, "the minion table is full")
	headless.run_pin(run)
	return handle
}

// Every minion goes (the floor's packs, for a test of its own minions), and the run is pinned.
clear_minions :: proc(run: ^headless.Run(g.Game)) {
	sim.despawn_all(&run.simulation.state.minions)
	headless.run_pin(run)
}

// The risers of a run as they rise, tick by tick (watch_rises): each grave's last riser's tick.
Rise_Watch :: struct {
	last: [g.MAX_GRAVES]sim.Game_Time,
	seen: [g.MAX_GRAVES]bool,
}

// The minions that rose this tick (Rise, or a sleeping crowd's Idle, born now): a grave's risers RISE_GAP_TICKS apart
// or more, and none within SEPARATION of another live minion (less a tick of their neighbours' moves). How many rose.
watch_rises :: proc(t: ^testing.T, run: ^headless.Run(g.Game), watch: ^Rise_Watch, loc := #caller_location) -> int {
	state := &run.simulation.state
	floor := floor_of(run)
	risen := 0
	minions := sim.iterate(&state.minions)
	for minion, handle in sim.next(&minions) {
		if minion.since != state.clock.time || (minion.phase != .Rise && minion.phase != .Idle) do continue
		risen += 1
		grave, best := 0, max(f32)
		for &place, i in sim.slice(&floor.places.graves) {
			if apart := dmath.length(place.point.xz - minion.pos.xz); apart < best do grave, best = i, apart
		}
		gap := state.clock.time - watch.last[grave]
		if watch.seen[grave] && gap < sim.Game_Time(g.RISE_GAP_TICKS) {
			testing.expectf(t, false, "grave %d raised again %d ticks on", grave, gap, loc = loc)
		}
		watch.last[grave], watch.seen[grave] = state.clock.time, true
		others := sim.iterate(&state.minions)
		for other, other_handle in sim.next(&others) {
			if other_handle == handle || other.phase == .Dying do continue
			if apart := dmath.length(other.pos.xz - minion.pos.xz);
			   apart < g.SEPARATION - 2 * g.MINION_SPEED / g.TICK_HZ {
				testing.expectf(t, false, "a riser %v m from another minion", apart, loc = loc)
			}
		}
	}
	return risen
}

// Whether `point` is where a trap of the floor can strike: over spikes, or within reach of a roller's path (within
// 1.5 m of any of its points).
on_a_trap :: proc(run: ^headless.Run(g.Game), point: [3]f32) -> bool {
	for &trap in sim.slice(&floor_of(run).places.traps) {
		switch trap.kind {
		case .Spikes:
			if g.within_square(trap.pos, trap.rot, g.SPIKES_HALF + g.MINION_RADIUS, point) do return true
		case .Roller:
			for k in 0 ..< int(trap.path.count) {
				if dmath.length(trap.path.points[k].xz - point.xz) < 1.5 + g.ROLLER_HALF.x do return true
			}
		}
	}
	return false
}

// ---- ragdolls

// Long enough for a downed hero's ragdoll to fall and come to rest (seconds).
SETTLE_S :: 2

// SETTLE_S of idle play: a ragdoll falls and comes to rest.
settle :: proc(run: ^headless.Run(g.Game)) {
	play(run, {}, SETTLE_S)
}

// The walkable floor's point under `near` (a downed hero's pelvis lies above it): where a test stands a hero beside one.
on_floor :: proc(run: ^headless.Run(g.Game), near: [3]f32) -> [3]f32 {
	spot, found := g.floor_spot(floor_of(run), near, 1)
	assert(found, "a test's spot is off the floor")
	return spot.point
}

// ---- the run (run.odin, saves.odin)

// Boards the floor's lift (Command_Dev_Board) and rides it to the bottom: a crypt floor's lift waits on picks there
// (Choosing); the hub's has begun the run.
ride_lift :: proc(run: ^headless.Run(g.Game)) {
	began := headless.run_events(run, g.Event_Run_Began)
	headless.run_command(run, 0, g.Command_Dev_Board{})
	for _ in 0 ..< 10 * g.TICK_HZ {
		if run.simulation.state.lift.phase == .Choosing || headless.run_events(run, g.Event_Run_Began) > began do break
		headless.run_step(run)
	}
}

// Rides the floor's lift down and has every present hero pick its first card: the party descends.
descend :: proc(run: ^headless.Run(g.Game)) {
	ride_lift(run)
	assert(run.simulation.state.lift.phase == .Choosing, "the lift didn't reach the bottom")
	inputs := headless.run_inputs(run)
	for slot in 0 ..< g.PLAYERS {
		if sim.slot_data(run.simulation, slot) != nil do sim.add_command(&inputs, slot, g.Command_Pick_Boon{0})
	}
	headless.run_step(run, &inputs)
}
