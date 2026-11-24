// crypt_crew's rule tests, each on a sync-tested run (headless.Run: every step re-simulated 8 ticks back and
// compared), the shape a game's own scenarios take.
package test_crypt_crew

import "core:testing"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

// A throw emits its event at once, at most THROW_SPEED_MAX, and the ball is gone once it lands.
@(test)
a_thrown_ball_lands_and_is_gone :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	headless.run_command(&run, 0, g.Command_Throw_Ball{speed = 255})
	testing.expect_value(t, headless.run_events(&run, g.Event_Ball_Thrown), 1)
	thrown, _ := headless.run_last_event(&run, g.Event_Ball_Thrown)
	testing.expect_value(t, thrown.speed, g.THROW_SPEED_MAX)
	testing.expect_value(t, run.simulation.state.balls.count, 1)
	for _ in 0 ..< 2 * g.TICK_HZ do headless.run_step(&run)
	testing.expect_value(t, run.simulation.state.balls.count, 0)
	scenarios.expect_synced(t, &run)
}

// A throw inside THROW_COOLDOWN_S of the last one is dropped; one after it throws.
@(test)
a_throw_waits_out_the_cooldown :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	twice := headless.run_inputs(&run)
	sim.add_command(&twice, 0, g.Command_Throw_Ball{speed = 4})
	sim.add_command(&twice, 0, g.Command_Throw_Ball{speed = 4}) // the second in the same tick: dropped
	headless.run_step(&run, &twice)
	headless.run_command(&run, 0, g.Command_Throw_Ball{speed = 4}) // a tick later: dropped
	testing.expect_value(t, run.simulation.state.balls.count, 1)
	for _ in 0 ..< sim.ticks(g.THROW_COOLDOWN_S, g.TICK_HZ) do headless.run_step(&run)
	headless.run_command(&run, 0, g.Command_Throw_Ball{speed = 4})
	testing.expect_value(t, run.simulation.state.balls.count, 2)
	scenarios.expect_synced(t, &run)
}

// A full table: every slot throws every tick, and the balls in the air stop at MAX_BALLS (a throw then is lost) and stay
// there while everyone throws.
@(test)
a_full_table_loses_the_throw :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = g.PLAYERS)
	defer headless.run_end(&run)
	most, full_ticks := 0, 0
	for _ in 0 ..< 4 * g.TICK_HZ {
		inputs := headless.run_inputs(&run)
		for slot in 0 ..< g.PLAYERS do sim.add_command(&inputs, slot, g.Command_Throw_Ball{speed = 255})
		headless.run_step(&run, &inputs)
		count := int(run.simulation.state.balls.count)
		most = max(most, count)
		full_ticks += int(count == g.MAX_BALLS)
	}
	testing.expect_value(t, most, g.MAX_BALLS)
	testing.expect(t, full_ticks > g.TICK_HZ, "the table stays full while everyone throws")
	scenarios.expect_synced(t, &run)
}

// The co-op pause: from the tick after anyone's Command_Set_Paused, nothing moves (players, balls), a throw sent while
// paused is dropped, game time stands still, and a cooldown started before it is still running after it, by exactly
// the pause; a resume takes it back. Each change is announced once.
@(test)
a_co_op_pause_stops_the_game :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	headless.run_command(&run, 0, g.Command_Throw_Ball{speed = 8})
	pause := headless.run_inputs(&run)
	sim.add_command(&pause, 1, g.Command_Set_Paused{true})
	sim.add_command(&pause, 1, g.Command_Set_Paused{true}) // twice: one change, one event
	headless.run_step(&run, &pause)
	testing.expect_value(t, headless.run_events(&run, g.Event_Paused), 1)
	state := &run.simulation.state
	time := state.clock.time
	ball := state.balls.items[0]
	moved := sim.slot_data(run.simulation, 0).position
	for _ in 0 ..< 30 {
		inputs := headless.run_inputs(&run)
		inputs.input[0] = {
			dx = 127,
		}
		sim.add_command(&inputs, 0, g.Command_Throw_Ball{speed = 4})
		headless.run_step(&run, &inputs)
	}
	testing.expect_value(t, state.clock.time, time)
	testing.expect_value(t, state.balls.count, 1) // the throws sent while paused are gone
	testing.expect_value(t, state.balls.items[0], ball)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).position, moved)
	data := sim.slot_data(run.simulation, 0)
	testing.expect(t, sim.timer_running(state.clock.time, data.throw_ready), "the cooldown waits out the pause")
	headless.run_command(&run, 0, g.Command_Set_Paused{false})
	headless.run_step(&run)
	testing.expect_value(t, state.clock.time, time + 1)
	testing.expect_value(t, headless.run_events(&run, g.Event_Paused), 2) // so far: the pause and the resume
	scenarios.expect_synced(t, &run)
}
