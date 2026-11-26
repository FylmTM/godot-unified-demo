// The revive's rule tests (revive.odin): tending a downed ally by holding Interact beside them, two tending at twice
// the speed, a revive nobody tends decaying, a blow breaking it off, the press grabbing nothing, and the dev revive.
// Each on a sync-tested run (headless.Run) that ends synced, so every revive here also rolls back.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

// A run of `seated` heroes with no minion, slot `downed`'s hero down at its spawn and every other slot standing
// beside it within REVIVE_RANGE (a ring around it), each facing it.
@(private = "file")
one_down :: proc(seated: int, downed := 0) -> headless.Run(g.Game) {
	run := headless.run_begin(&g.GAME, 1, seated = seated)
	clear_minions(&run)
	at := spawn_of(&run, downed)
	place_hero(&run, downed, at)
	for slot in 0 ..< seated {
		if slot == downed do continue
		dir := dmath.DIR8[(slot * 3) % len(dmath.DIR8)]
		beside := [3]f32{dir.x, 0, dir.y} * (g.REVIVE_RANGE - 0.4)
		place_hero(&run, slot, at + beside, -dir)
	}
	hurt(&run, downed, g.HERO_HP)
	return run
}

// `slots` hold Interact for `ticks` ticks (its first tick a press, when they weren't holding it already).
@(private = "file")
tend :: proc(run: ^headless.Run(g.Game), slots: []int, ticks: int) {
	inputs: [g.PLAYERS]g.Input
	for slot in slots do inputs[slot].buttons = {.Interact}
	for _ in 0 ..< ticks do headless.run_step(run, inputs)
}

// Holding Interact beside a downed ally revives them in REVIVE_TICKS of tending, not a tick sooner: they rise where they
// lie at REVIVE_HP, in their grace (a blow does nothing), and the reviver is free again.
@(test)
a_revive_takes_its_time :: proc(t: ^testing.T) {
	run := one_down(2)
	defer headless.run_end(&run)
	downed, reviver := sim.slot_data(run.simulation, 0), sim.slot_data(run.simulation, 1)
	lying := downed.pos
	tend(&run, {1}, int(g.REVIVE_TICKS) - 1)
	testing.expect_value(t, reviver.action, g.Action.Revive)
	testing.expect_value(t, downed.action, g.Action.Down)
	testing.expect_value(t, downed.revive, g.REVIVE_TICKS - 1)
	tend(&run, {1}, 1)
	testing.expect_value(t, downed.action, g.Action.None)
	testing.expect_value(t, downed.hp, g.REVIVE_HP)
	testing.expect_value(t, reviver.action, g.Action.None)
	testing.expectf(t, dmath.length(downed.pos - lying) < 0.05, "rose at %v, not where it lay (%v)", downed.pos, lying)
	revived, _ := headless.run_last_event(&run, g.Event_Hero_Revived)
	testing.expect_value(t, revived.player, sim.player_in_slot(run.simulation, 0))
	testing.expect_value(t, revived.by, sim.player_in_slot(run.simulation, 1))
	hurt(&run, 0, 10) // in its grace
	testing.expect_value(t, downed.hp, g.REVIVE_HP)
	scenarios.expect_synced(t, &run)
}

// Two allies tending at once revive twice as fast: REVIVE_TICKS / 2 ticks, the first in slot order the reviver.
@(test)
two_revive_twice_as_fast :: proc(t: ^testing.T) {
	run := one_down(3)
	defer headless.run_end(&run)
	downed := sim.slot_data(run.simulation, 0)
	tend(&run, {1, 2}, int(g.REVIVE_TICKS / 2) - 1)
	testing.expect_value(t, downed.action, g.Action.Down)
	tend(&run, {1, 2}, 1)
	testing.expect_value(t, downed.action, g.Action.None)
	revived, _ := headless.run_last_event(&run, g.Event_Hero_Revived)
	testing.expect_value(t, revived.by, sim.player_in_slot(run.simulation, 1))
	scenarios.expect_synced(t, &run)
}

// A revive let go of decays by REVIVE_DECAY a tick, down to none, and a new press carries on from what is left.
@(test)
a_revive_let_go_decays :: proc(t: ^testing.T) {
	run := one_down(2)
	defer headless.run_end(&run)
	downed, reviver := sim.slot_data(run.simulation, 0), sim.slot_data(run.simulation, 1)
	tend(&run, {1}, 60)
	testing.expect_value(t, downed.revive, 60)
	play(&run, {}, 10.0 / g.TICK_HZ)
	testing.expect_value(t, reviver.action, g.Action.None)
	testing.expect_value(t, downed.revive, 60 - 10 * g.REVIVE_DECAY)
	tend(&run, {1}, 5)
	testing.expect_value(t, downed.revive, 60 - 10 * g.REVIVE_DECAY + 5)
	play(&run, {}, 1)
	testing.expect_value(t, downed.revive, 0)
	scenarios.expect_synced(t, &run)
}

// A blow breaks a revive off: the reviver stops tending though it still holds Interact, the revive decays, and only a
// new press starts it again. Attack held stops it too.
@(test)
a_hit_or_an_attack_breaks_a_revive_off :: proc(t: ^testing.T) {
	run := one_down(2)
	defer headless.run_end(&run)
	downed, reviver := sim.slot_data(run.simulation, 0), sim.slot_data(run.simulation, 1)
	tend(&run, {1}, 30)
	holding := [g.PLAYERS]g.Input {
		1 = {buttons = {.Interact}},
	}
	headless.run_command(&run, holding, 0, g.Command_Dev_Hurt{sim.player_in_slot(run.simulation, 1), 10})
	testing.expect_value(t, reviver.action, g.Action.None)
	for _ in 0 ..< 10 do headless.run_step(&run, holding)
	testing.expect_value(t, reviver.action, g.Action.None)
	testing.expect_value(t, downed.revive, 30 - 11 * g.REVIVE_DECAY)
	play(&run, {}, 1.0 / g.TICK_HZ)
	tend(&run, {1}, 5)
	testing.expect_value(t, reviver.action, g.Action.Revive)
	attacking := [g.PLAYERS]g.Input {
		1 = {buttons = {.Interact, .Attack}},
	}
	headless.run_step(&run, attacking)
	testing.expect(t, reviver.action != .Revive, "Attack held stops the revive")
	scenarios.expect_synced(t, &run)
}

// The press that starts a revive grabs nothing, though a crate stands in reach in front of the reviver; the reviver
// moves at REVIVE_SPEED while it tends.
@(test)
the_revive_press_grabs_nothing :: proc(t: ^testing.T) {
	run := one_down(2)
	defer headless.run_end(&run)
	reviver := sim.slot_data(run.simulation, 1)
	lying := sim.slot_data(run.simulation, 0).pos
	place_hero(&run, 1, lying + {0, 0, 1.1}, {0, -1}) // facing the downed hero, 1.1 m off
	place_prop(&run, CRATE, reviver.pos + {1.1, 0, -1.1}) // 45° off its facing: in the grab's cone, clear of the downed
	state := &run.simulation.state
	in_reach := g.hands_target(run.simulation.world.phys, &state.props, reviver, reviver.facing) != {}
	testing.expect(t, in_reach, "the crate is in reach: a press would grab it but for the revive")
	tend(&run, {1}, 2)
	testing.expect_value(t, reviver.action, g.Action.Revive)
	testing.expect_value(t, reviver.held, sim.Handle(g.Prop){})
	crate, _ := prop_at(&run, CRATE)
	testing.expect_value(t, crate.held_by, sim.Player{})
	creeping := [g.PLAYERS]g.Input { 	// sideways, away from the crate, staying in range
		1 = {buttons = {.Interact}, move_x = -127},
	}
	for _ in 0 ..< 30 do headless.run_step(&run, creeping)
	testing.expect_value(t, reviver.action, g.Action.Revive)
	want := g.CLASS_SPECS[reviver.class].max_speed * g.REVIVE_SPEED
	testing.expectf(t, abs(-reviver.vel.x - want) < 0.15, "tends at %v m/s, not %v", -reviver.vel.x, want)
	scenarios.expect_synced(t, &run)
}

// The dev revive revives a hero down at once (its sender the reviver), or every hero down when it names nobody.
@(test)
the_dev_revive_revives :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 3)
	defer headless.run_end(&run)
	clear_minions(&run)
	hurt(&run, 1, g.HERO_HP)
	hurt(&run, 2, g.HERO_HP)
	headless.run_command(&run, 0, g.Command_Dev_Revive{sim.player_in_slot(run.simulation, 1)})
	testing.expect_value(t, sim.slot_data(run.simulation, 1).hp, g.REVIVE_HP)
	testing.expect_value(t, sim.slot_data(run.simulation, 2).action, g.Action.Down)
	revived, _ := headless.run_last_event(&run, g.Event_Hero_Revived)
	testing.expect_value(t, revived.by, sim.player_in_slot(run.simulation, 0))
	headless.run_command(&run, 0, g.Command_Dev_Revive{})
	testing.expect_value(t, sim.slot_data(run.simulation, 2).action, g.Action.None)
	scenarios.expect_synced(t, &run)
}
