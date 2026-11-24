// The heroes' rule tests (presence.odin, heroes.odin, pause.odin), each on a sync-tested run (headless.Run: every step
// re-simulated 8 ticks back and compared, the physics world's refs checked after every restore) that ends synced.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

// A second of play by slot with these inputs (the seated members present).
@(private = "file")
play_second :: proc(run: ^headless.Run(g.Game), inputs: [g.PLAYERS]g.Input) {
	for _ in 0 ..< g.TICK_HZ do headless.run_step(run, inputs)
}

// The hero faces `want` (to within a Dir2's quantization).
@(private = "file")
expect_facing :: proc(t: ^testing.T, hero: ^g.Hero, want: [2]f32, loc := #caller_location) {
	testing.expectf(t, dmath.length(hero.facing - want) < 1e-3, "faces %v, not %v", hero.facing, want, loc = loc)
}

// A hero walks where its stick points at about its class's speed, staying on its line, and turns to face its move.
@(test)
a_hero_walks_where_the_stick_points :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 0)
	start := hero.pos
	play_second(&run, {0 = {move_x = 127}})
	walked := hero.pos - start
	speed := g.CLASS_SPECS[hero.class].max_speed
	testing.expectf(t, walked.x > speed * 0.6 && walked.x <= speed, "walked %v in a second at %v m/s", walked, speed)
	testing.expectf(t, abs(walked.z) < 0.1 && abs(walked.y) < 0.1, "strayed off its line: %v", walked)
	expect_facing(t, hero, {1, 0})
	scenarios.expect_synced(t, &run)
}

// A hero faces its aim whatever it walks (a strafe), keeps that facing once the aim and the stick let go, and without an
// aim faces its move.
@(test)
a_hero_faces_its_aim :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 0)
	start := hero.pos
	play_second(&run, {0 = {move_x = 127, aim = dmath.dir2({0, 1})}})
	expect_facing(t, hero, {0, 1})
	testing.expectf(t, hero.pos.x - start.x > 2, "the strafe went nowhere: %v from %v", hero.pos, start)
	play_second(&run, {})
	expect_facing(t, hero, {0, 1})
	play_second(&run, {0 = {move_z = -127}})
	expect_facing(t, hero, {0, -1})
	scenarios.expect_synced(t, &run)
}

// Four heroes whose Profiles ask for Any play four classes, none of them Any, in slot order; one asking for a class
// gets it even when another hero plays it.
@(test)
any_class_resolves_to_one_nobody_plays :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1)
	defer headless.run_end(&run)
	for slot in 0 ..< g.PLAYERS - 1 do headless.run_seat(&run, slot, slot + 1, g.Profile{})
	headless.run_step(&run)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).class, g.Class.Knight)
	testing.expect_value(t, sim.slot_data(run.simulation, 1).class, g.Class.Barbarian)
	testing.expect_value(t, sim.slot_data(run.simulation, 2).class, g.Class.Mage)
	headless.run_seat(&run, 3, 4, g.Profile{class = .Knight})
	headless.run_step(&run)
	testing.expect_value(t, sim.slot_data(run.simulation, 3).class, g.Class.Knight)
	scenarios.expect_synced(t, &run)
}

// A leaver's body is gone at once and its class kept: back in another slot, asking for another class, it plays the one
// it played, with a body at that slot's spawn.
@(test)
a_leaver_comes_back_as_it_was :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2) // the scripted Profiles: a Knight and a Barbarian
	defer headless.run_end(&run)
	leaver := sim.player_in_slot(run.simulation, 1)
	hero := sim.player_data(&run.simulation.state.players, leaver)
	testing.expect_value(t, hero.class, g.Class.Barbarian)
	headless.run_seat(&run, 1, 0)
	headless.run_step(&run)
	testing.expect(t, !sim.player_present(&run.simulation.state.players, leaver), "it left")
	testing.expect_value(t, hero.body, g.Hero{}.body)
	testing.expect_value(t, hero.class, g.Class.Barbarian)
	headless.run_seat(&run, 3, 2, g.Profile{class = .Rogue})
	headless.run_step(&run)
	testing.expect_value(t, sim.player_in_slot(run.simulation, 3), leaver)
	testing.expect_value(t, hero.class, g.Class.Barbarian)
	testing.expect(t, hero.body != g.Hero{}.body, "it has a body again")
	spawn := run.simulation.world.places.hero_spawns[3]
	testing.expectf(t, dmath.length(hero.pos.xz - spawn.xz) < 0.01, "arrived at %v, its spawn is %v", hero.pos, spawn)
	scenarios.expect_synced(t, &run)
}

// The co-op pause: from the tick after anyone's Command_Set_Paused, no hero moves or turns whatever its input, and game
// time stands still; a resume lets them walk again. Each change is announced once.
@(test)
a_co_op_pause_holds_the_heroes :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	walk := [g.PLAYERS]g.Input {
		0 = {move_x = 127},
		1 = {move_z = 127, aim = dmath.dir2({-1, 0})},
	}
	play_second(&run, walk)
	pause := headless.run_inputs(&run)
	sim.add_command(&pause, 1, g.Command_Set_Paused{true})
	sim.add_command(&pause, 1, g.Command_Set_Paused{true}) // twice: one change, one event
	headless.run_step(&run, &pause)
	testing.expect_value(t, headless.run_events(&run, g.Event_Paused), 1)
	state := &run.simulation.state
	time := state.clock.time
	held := [2]g.Hero{sim.slot_data(run.simulation, 0)^, sim.slot_data(run.simulation, 1)^}
	play_second(&run, walk)
	testing.expect_value(t, state.clock.time, time)
	testing.expect_value(t, sim.slot_data(run.simulation, 0)^, held[0])
	testing.expect_value(t, sim.slot_data(run.simulation, 1)^, held[1])
	headless.run_command(&run, walk, 0, g.Command_Set_Paused{false})
	testing.expect_value(t, headless.run_events(&run, g.Event_Paused), 2) // so far: the pause and the resume
	play_second(&run, walk)
	testing.expect(t, sim.slot_data(run.simulation, 0).pos.x > held[0].pos.x + 1, "walks again after the resume")
	scenarios.expect_synced(t, &run)
}
