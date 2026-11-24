// The minions' rule tests (minions.odin, the packs of director.odin), each on a sync-tested run (headless.Run) that
// ends synced. A test raises a minion where it needs one (place_minion), or puts a hero somewhere (place_hero), and
// pins the run there.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:nav"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// Slot 0's spawn on Floor 1, in the first room; its east doorway leads to a corridor and the dirt floor past it.
@(private = "file")
SPAWN :: [3]f32{-15.5, 0, -1.2}
// On the dirt floor east of the first room's doorway: a walk through the doorway to the spawn.
@(private = "file")
PAST_THE_DOORWAY :: [3]f32{-2, 0, -2}

// A minion in `phase` on the walkable floor nearest `near`, facing `facing`, pinned there; its handle.
@(private = "file")
place_minion :: proc(
	run: ^headless.Run(g.Game),
	near: [3]f32,
	phase: g.Minion_Phase,
	facing := [2]f32{0, 1},
) -> sim.Handle(g.Minion) {
	spot, ok := g.floor_spot(run.simulation.world, near, 2)
	assert(ok, "a test's minion is off the floor")
	state := &run.simulation.state
	g.spawn_minion(state, spot.point, spot.poly, facing, phase, state.clock.time)
	headless.run_pin(run)
	handle: sim.Handle(g.Minion)
	walk := sim.iterate(&state.minions)
	for _, each in sim.next(&walk) do handle = each // the newest: the highest index, the table filling in order
	return handle
}

// Moves slot `slot`'s hero to stand at `feet`, at rest, and pins the run there.
@(private = "file")
place_hero :: proc(run: ^headless.Run(g.Game), slot: int, feet: [3]f32) {
	hero := sim.slot_data(run.simulation, slot)
	physics.character_teleport(run.simulation.world.phys, &hero.body, feet + {0, g.HERO_CENTRE_ABOVE_FEET, 0})
	hero.pos = feet
	headless.run_pin(run)
}

// Every minion goes (the packs, for a test of its own minions), and the run is pinned.
@(private = "file")
clear_minions :: proc(run: ^headless.Run(g.Game)) {
	sim.despawn_all(&run.simulation.state.minions)
	headless.run_pin(run)
}

// `seconds` of play with these inputs by slot, each tick's every minion on the mesh (nav.locate finds it on its
// polygon's floor).
@(private = "file")
play_on_the_mesh :: proc(t: ^testing.T, run: ^headless.Run(g.Game), inputs: [g.PLAYERS]g.Input, seconds: f32) {
	for _ in 0 ..< int(seconds * g.TICK_HZ) {
		headless.run_step(run, inputs)
		minions := sim.iterate(&run.simulation.state.minions)
		for minion in sim.next(&minions) {
			if nav.locate(&run.simulation.world.mesh, minion.pos, 0.1) == nav.NO_POLY {
				testing.expectf(t, false, "a minion left the mesh at %v", minion.pos)
				return
			}
		}
	}
}

// A chasing minion walks the floor to a hero in another room, through the doorway, never leaving the mesh, and
// swings once in reach.
@(test)
a_minion_reaches_a_hero_through_the_doorway :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	handle := place_minion(&run, PAST_THE_DOORWAY, .Chase)
	minion := sim.get(&run.simulation.state.minions, handle)
	reached := false
	for _ in 0 ..< 8 * g.TICK_HZ {
		play_on_the_mesh(t, &run, {}, 1.0 / g.TICK_HZ)
		if minion.phase == .Attack {
			reached = true
			break
		}
	}
	testing.expectf(t, reached, "never reached the hero: at %v, the hero at %v", minion.pos, SPAWN)
	scenarios.expect_synced(t, &run)
}

// A swing is telegraphed: in reach, the minion winds up, and the hero takes MINION_DAMAGE only when the windup ends;
// a hero who walks out of reach meanwhile takes nothing.
@(test)
a_swing_lands_after_its_windup :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	swinging := sim.get(&run.simulation.state.minions, place_minion(&run, SPAWN + {1.4, 0, 0}, .Chase, {-1, 0}))
	headless.run_step(&run)
	testing.expect_value(t, swinging.phase, g.Minion_Phase.Attack) // in reach at once
	for _ in 1 ..< g.MINION_WINDUP_TICKS do headless.run_step(&run)
	testing.expect_value(t, headless.run_events(&run, g.Event_Hero_Hurt), 0)
	headless.run_step(&run)
	testing.expect_value(t, headless.run_events(&run, g.Event_Hero_Hurt), 1)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).hp, g.HERO_HP - g.MINION_DAMAGE)
	scenarios.expect_synced(t, &run)

	dodge := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&dodge)
	clear_minions(&dodge)
	place_minion(&dodge, SPAWN + {1.6, 0, 0}, .Chase, {-1, 0})
	walk_away := [g.PLAYERS]g.Input {
		0 = {move_x = -127},
	}
	for _ in 0 ..< g.MINION_ATTACK_TICKS do headless.run_step(&dodge, walk_away)
	testing.expect_value(t, headless.run_events(&dodge, g.Event_Hero_Hurt), 0)
	scenarios.expect_synced(t, &dodge)
}

// Two minions on the same spot step apart, to about SEPARATION.
@(test)
minions_keep_apart :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	a := place_minion(&run, PAST_THE_DOORWAY, .Idle) // out of the hero's sight: they sleep
	b := place_minion(&run, PAST_THE_DOORWAY, .Idle)
	play_on_the_mesh(t, &run, {}, 1)
	minions := &run.simulation.state.minions
	apart := dmath.length(sim.get(minions, a).pos.xz - sim.get(minions, b).pos.xz)
	testing.expectf(
		t,
		apart > g.SEPARATION * 0.9,
		"only %v m apart: %v %v",
		apart,
		sim.get(minions, a)^,
		sim.get(minions, b)^,
	)
	scenarios.expect_synced(t, &run)
}

// A minion standing in a crate is pushed out of it (the crate never moves), and a knockback carries a minion along
// and dies away at KNOCK_DECAY.
@(test)
minions_are_pushed_out_of_props_and_knocked_back :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	crate_def := sim.slice(&run.simulation.world.places.props)[2] // the first room's crate (marker order)
	crate_at := physics.body_position(run.simulation.world.phys, run.simulation.state.props.items[2].body)
	handle := place_minion(&run, crate_def.pos + {0, 0, 0.3}, .Idle)
	minion := sim.get(&run.simulation.state.minions, handle)
	play_on_the_mesh(t, &run, {}, 0.25)
	clear_of := g.PROP_SPECS[crate_def.kind].footprint + g.MINION_RADIUS
	testing.expectf(
		t,
		dmath.length(minion.pos.xz - crate_def.pos.xz) >= clear_of - 0.01,
		"still in the crate: %v",
		minion.pos,
	)
	crate_now := physics.body_position(run.simulation.world.phys, run.simulation.state.props.items[2].body)
	testing.expectf(t, dmath.length(crate_now - crate_at) < 0.01, "the crate moved: %v from %v", crate_now, crate_at)

	pushed := place_minion(&run, PAST_THE_DOORWAY, .Idle)
	sim.get(&run.simulation.state.minions, pushed).knock = {6, 0}
	from := sim.get(&run.simulation.state.minions, pushed).pos
	headless.run_pin(&run)
	play_on_the_mesh(t, &run, {}, 1)
	knocked := sim.get(&run.simulation.state.minions, pushed)
	carried := knocked.pos.x - from.x
	testing.expectf(t, carried > 0.8 && carried < 1.05, "carried %v m by a 6 m/s knock", carried)
	testing.expectf(t, dmath.length(knocked.knock) < 0.05, "the knock is still %v", knocked.knock)
	scenarios.expect_synced(t, &run)
}

// A killed minion falls (Dying), is counted once, and its row is freed DEATH_S later.
@(test)
a_dead_minion_falls_and_is_freed :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	handle := place_minion(&run, PAST_THE_DOORWAY, .Idle)
	headless.run_command(&run, 0, g.Command_Dev_Kill_Minions{})
	testing.expect_value(t, sim.get(&run.simulation.state.minions, handle).phase, g.Minion_Phase.Dying)
	testing.expect_value(t, headless.run_events(&run, g.Event_Minion_Died), 1)
	testing.expect_value(t, run.simulation.state.kills, 1)
	for _ in 1 ..< g.DEATH_TICKS do headless.run_step(&run)
	testing.expect(t, sim.get(&run.simulation.state.minions, handle) != nil, "still falling just before DEATH_S")
	headless.run_step(&run)
	testing.expect(t, sim.get(&run.simulation.state.minions, handle) == nil, "freed at DEATH_S")
	scenarios.expect_synced(t, &run)
}

// A pack sleeps while no hero is near, and wakes to chase a hero who comes into sight within AGGRO_RADIUS.
@(test)
packs_sleep_until_a_hero_is_in_sight :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	headless.run_step(&run)
	state := &run.simulation.state
	testing.expect(t, state.minions.count > 0, "the floor's packs are asleep at its start")
	play_on_the_mesh(t, &run, {}, 2)
	minions := sim.iterate(&state.minions)
	for minion in sim.next(&minions) do testing.expect_value(t, minion.phase, g.Minion_Phase.Idle)
	pack := sim.slice(&run.simulation.world.places.packs)[0]
	place_hero(&run, 0, pack.pos + {0, 0, 3.5})
	play_on_the_mesh(t, &run, {}, 0.5)
	awake := 0
	minions = sim.iterate(&state.minions)
	for minion in sim.next(&minions) do awake += int(minion.phase == .Chase || minion.phase == .Attack)
	testing.expect(t, awake >= int(pack.count), "the pack woke")
	scenarios.expect_synced(t, &run)
}
