// The minions' rule tests (minions.odin, the packs of director.odin), each on a sync-tested run (headless.Run) that
// ends synced. A test raises a minion where it needs one, or puts a hero somewhere (support_test.odin), and the run is
// pinned there. Slot 0's spawn is in the first room, whose east doorway leads to a corridor and the dirt floor past it.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:nav"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// On the dirt floor past the first room's east doorway, out of sight of slot 0's spawn: a walk through the doorway.
@(private = "file")
PAST_THE_DOORWAY :: [3]f32{-2, 0, -2}

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
	minion := sim.get(&run.simulation.state.minions, place_minion(&run, PAST_THE_DOORWAY, .Chase))
	reached := false
	for _ in 0 ..< 8 * g.TICK_HZ {
		play_on_the_mesh(t, &run, {}, 1.0 / g.TICK_HZ)
		if minion.phase == .Attack {
			reached = true
			break
		}
	}
	testing.expectf(t, reached, "never reached the hero: at %v", minion.pos)
	scenarios.expect_synced(t, &run)
}

// A swing is telegraphed: in reach, the minion winds up, and the hero takes MINION_DAMAGE only when the windup ends;
// a hero who walks out of reach meanwhile takes nothing.
@(test)
a_swing_lands_after_its_windup :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	spawn := spawn_of(&run, 0)
	swinging := sim.get(&run.simulation.state.minions, place_minion(&run, spawn + {1.4, 0, 0}, .Chase, {-1, 0}))
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
	place_minion(&dodge, spawn + {1.6, 0, 0}, .Chase, {-1, 0})
	walk_away := [g.PLAYERS]g.Input {
		0 = {move_x = -127},
	}
	for _ in 0 ..< g.MINION_ATTACK_TICKS do headless.run_step(&dodge, walk_away)
	testing.expect_value(t, headless.run_events(&dodge, g.Event_Hero_Hurt), 0)
	scenarios.expect_synced(t, &dodge)
}

// A swing has a direction: a hero who steps behind the swinging minion, still in reach, takes nothing.
@(test)
a_swing_misses_behind :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	spawn := spawn_of(&run, 0)
	swinging := sim.get(&run.simulation.state.minions, place_minion(&run, spawn + {1.4, 0, 0}, .Chase, {-1, 0}))
	headless.run_step(&run)
	testing.expect_value(t, swinging.phase, g.Minion_Phase.Attack)
	place_hero(&run, 0, swinging.pos + {1.4, -swinging.pos.y, 0}) // the same distance, behind its locked facing
	for _ in 0 ..< g.MINION_WINDUP_TICKS do headless.run_step(&run)
	testing.expect_value(t, headless.run_events(&run, g.Event_Hero_Hurt), 0)
	scenarios.expect_synced(t, &run)
}

// A swinging minion keeps its target, however near another hero comes; it picks again once the swing is over.
@(test)
a_swing_keeps_its_target :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	clear_minions(&run)
	first := sim.player_in_slot(run.simulation, 0)
	spawn := spawn_of(&run, 0)
	place_hero(&run, 1, spawn + {0, 0, 6})
	swinging := sim.get(&run.simulation.state.minions, place_minion(&run, spawn + {1.4, 0, 0}, .Chase, {-1, 0}))
	headless.run_step(&run)
	testing.expect_value(t, swinging.phase, g.Minion_Phase.Attack)
	testing.expect_value(t, swinging.target, first)
	place_hero(&run, 1, swinging.pos + {0, -swinging.pos.y, 1.2}) // nearer than its target now
	for _ in 1 ..< g.MINION_ATTACK_TICKS {
		headless.run_step(&run)
		if swinging.target != first {
			testing.expect(t, false, "it changed targets mid-swing")
			break
		}
	}
	scenarios.expect_synced(t, &run)
}

// Two minions on the same spot step apart, to about SEPARATION.
@(test)
minions_keep_apart :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	left := place_minion(&run, PAST_THE_DOORWAY, .Idle) // out of the hero's sight: they sleep
	right := place_minion(&run, PAST_THE_DOORWAY, .Idle)
	play_on_the_mesh(t, &run, {}, 1)
	minions := &run.simulation.state.minions
	apart := dmath.length(sim.get(minions, left).pos.xz - sim.get(minions, right).pos.xz)
	testing.expectf(t, apart > g.SEPARATION * 0.9, "only %v m apart", apart)
	scenarios.expect_synced(t, &run)
}

// A minion standing in a crate is pushed out of it (the crate never moves), and a knockback carries a minion along
// and dies away at KNOCK_DECAY.
@(test)
minions_are_pushed_out_of_props_and_knocked_back :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	crate, _ := prop_at(&run, 2) // the first room's crate (marker order)
	crate_at := physics.body_position(run.simulation.world.phys, crate.body)
	minion := sim.get(&run.simulation.state.minions, place_minion(&run, crate_at + {0, -crate_at.y, 0.3}, .Idle))
	play_on_the_mesh(t, &run, {}, 0.25)
	clear_of := g.PROP_SPECS[crate.kind].footprint + g.MINION_RADIUS
	out := dmath.length(minion.pos.xz - crate_at.xz)
	testing.expectf(t, out >= clear_of - 0.01, "still in the crate: %v m from its centre", out)
	crate_now := physics.body_position(run.simulation.world.phys, crate.body)
	testing.expectf(t, dmath.length(crate_now - crate_at) < 0.01, "the crate moved: %v from %v", crate_now, crate_at)

	knocked := sim.get(&run.simulation.state.minions, place_minion(&run, PAST_THE_DOORWAY, .Idle))
	knocked.knock = {6, 0}
	from := knocked.pos
	headless.run_pin(&run)
	play_on_the_mesh(t, &run, {}, 1)
	carried := knocked.pos.x - from.x
	testing.expectf(t, carried > 0.8 && carried < 1.05, "carried %v m by a 6 m/s knock", carried)
	testing.expectf(t, dmath.length(knocked.knock) < 0.05, "the knock is still %v", knocked.knock)
	scenarios.expect_synced(t, &run)
}

// A killed minion falls (Dying), its death announced once, and its row is freed DEATH_S later.
@(test)
a_dead_minion_falls_and_is_freed :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	handle := place_minion(&run, PAST_THE_DOORWAY, .Idle)
	headless.run_command(&run, 0, g.Command_Dev_Kill_Minions{})
	testing.expect_value(t, sim.get(&run.simulation.state.minions, handle).phase, g.Minion_Phase.Dying)
	testing.expect_value(t, headless.run_events(&run, g.Event_Minion_Died), 1)
	for _ in 1 ..< g.DEATH_TICKS do headless.run_step(&run)
	testing.expect(t, sim.get(&run.simulation.state.minions, handle) != nil, "still falling just before DEATH_S")
	headless.run_step(&run)
	testing.expect(t, sim.get(&run.simulation.state.minions, handle) == nil, "freed at DEATH_S")
	scenarios.expect_synced(t, &run)
}

// A pack sleeps while no hero is near, and wakes as a whole to chase a hero who comes into sight within AGGRO_RADIUS.
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
	minions = sim.iterate(&state.minions)
	for minion in sim.next(&minions) {
		if minion.pack == 1 do testing.expect(t, minion.phase != .Idle, "every member of the pack woke")
	}
	scenarios.expect_synced(t, &run)
}

// A sleeping minion that is hit, and lives, wakes and chases.
@(test)
a_hit_wakes_a_sleeper :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	sleeper := sim.get(&run.simulation.state.minions, place_minion(&run, PAST_THE_DOORWAY, .Idle))
	sleeper.hp = g.MINION_HP + 1 // dev_kill_minions deals MINION_HP: this one lives
	headless.run_pin(&run)
	headless.run_command(&run, 0, g.Command_Dev_Kill_Minions{})
	testing.expect_value(t, sleeper.phase, g.Minion_Phase.Chase)
	testing.expect_value(t, sleeper.hp, 1)
	scenarios.expect_synced(t, &run)
}
