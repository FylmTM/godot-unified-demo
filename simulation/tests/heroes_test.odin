// The heroes' rule tests (presence.odin, heroes.odin, pause.odin, dev.odin), each on a sync-tested run (headless.Run:
// every step re-simulated 8 ticks back and compared, the physics world's refs checked after every restore) that ends
// synced.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

// Every hero stands on its floor: its feet stay within 2 cm of its slot's spawn after a second of standing.
@(test)
heroes_stand_at_their_spawns :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = g.PLAYERS)
	defer headless.run_end(&run)
	play(&run, {})
	for slot in 0 ..< g.PLAYERS {
		feet := sim.slot_data(run.simulation, slot).pos
		spawn := run.simulation.world.places.hero_spawns[slot]
		testing.expectf(
			t,
			dmath.length(feet - spawn) < 0.02,
			"slot %d stands at %v, its spawn is %v",
			slot,
			feet,
			spawn,
		)
	}
	scenarios.expect_synced(t, &run)
}

// A hero walks where its stick points, at full speed within about a tenth of a second and at its class's speed after,
// staying on its line, and turns to face its move.
@(test)
a_hero_walks_where_the_stick_points :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 0)
	speed := g.CLASS_SPECS[hero.class].max_speed
	start := hero.pos
	play(&run, {0 = {move_x = 127}}, 0.15)
	testing.expectf(t, hero.vel.x > speed * 0.9, "at %v m/s after 0.15 s, of %v", hero.vel.x, speed)
	play(&run, {0 = {move_x = 127}}, 0.85)
	walked := hero.pos - start
	testing.expectf(t, walked.x > speed * 0.85 && walked.x <= speed, "walked %v in a second at %v m/s", walked, speed)
	testing.expectf(t, abs(walked.z) < 0.1 && abs(walked.y) < 0.1, "strayed off its line: %v", walked)
	expect_facing(t, hero, {1, 0})
	scenarios.expect_synced(t, &run)
}

// A hero is stopped by a wall and by low cover (a barrier): it walks into them and stays on its side.
@(test)
a_hero_is_stopped_by_walls_and_low_cover :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1) // slot 0's spawn: x -15.5, z -1.2
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 0)
	play(&run, {0 = {move_z = 127}}, 2) // the barrier along z 4: its face at z 3.75, 1.1 m tall
	testing.expectf(t, hero.pos.z > 2.8 && hero.pos.z < 3.75, "stopped at %v, not against the barrier", hero.pos)
	testing.expectf(t, abs(hero.vel.z) < 0.1, "still moving at %v", hero.vel)
	play(&run, {0 = {move_x = -127}}, 2) // the room's west wall: its face at x -19.5
	testing.expectf(t, hero.pos.x > -19.5 && hero.pos.x < -18.8, "stopped at %v, not against the wall", hero.pos)
	testing.expectf(t, abs(hero.vel.x) < 0.1, "still moving at %v", hero.vel)
	scenarios.expect_synced(t, &run)
}

// A hero faces its aim whatever it walks (a strafe), keeps that facing once the aim and the stick let go, keeps it too
// for a stick inside TURN_STICK, and without an aim faces its move.
@(test)
a_hero_faces_its_aim :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 0)
	start := hero.pos
	play(&run, {0 = {move_x = 127, aim = dmath.dir2({0, 1})}})
	expect_facing(t, hero, {0, 1})
	testing.expectf(t, hero.pos.x - start.x > 2, "the strafe went nowhere: %v from %v", hero.pos, start)
	play(&run, {})
	expect_facing(t, hero, {0, 1})
	nudge := dmath.axis_i8(g.TURN_STICK * 0.9)
	play(&run, {0 = {move_x = nudge}})
	expect_facing(t, hero, {0, 1})
	play(&run, {0 = {move_z = -127}})
	expect_facing(t, hero, {0, -1})
	scenarios.expect_synced(t, &run)
}

// Four heroes whose Profiles ask for Any play the four classes in slot order; one asking for a class gets it even when
// another hero plays it.
@(test)
any_class_resolves_to_one_nobody_plays :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1)
	defer headless.run_end(&run)
	for slot in 0 ..< g.PLAYERS do headless.run_seat(&run, slot, slot + 1, g.Profile{})
	headless.run_step(&run)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).class, g.Class.Knight)
	testing.expect_value(t, sim.slot_data(run.simulation, 1).class, g.Class.Barbarian)
	testing.expect_value(t, sim.slot_data(run.simulation, 2).class, g.Class.Mage)
	testing.expect_value(t, sim.slot_data(run.simulation, 3).class, g.Class.Rogue)
	headless.run_seat(&run, 3, 5, g.Profile{class = .Knight})
	headless.run_step(&run)
	testing.expect_value(t, sim.slot_data(run.simulation, 3).class, g.Class.Knight)
	scenarios.expect_synced(t, &run)
}

// A leaver's body is gone at once and its class kept: back in another slot with no wish (Any), it plays the one it
// played, with a body beside the party; back with a wish, it plays that.
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
	headless.run_seat(&run, 3, 2, g.Profile{})
	headless.run_step(&run)
	testing.expect_value(t, sim.player_in_slot(run.simulation, 3), leaver)
	testing.expect_value(t, hero.class, g.Class.Barbarian)
	testing.expect(t, hero.body != g.Hero{}.body, "it has a body again")
	anchor := sim.slot_data(run.simulation, 0).pos // the party: it arrives beside slot 0's hero (arrival_spot)
	beside := dmath.length(hero.pos.xz - anchor.xz)
	testing.expectf(t, abs(beside - g.ARRIVAL_RING) < g.ARRIVAL_SNAP, "arrived %v m from the party", beside)
	headless.run_seat(&run, 3, 0)
	headless.run_step(&run)
	headless.run_seat(&run, 2, 2, g.Profile{class = .Rogue})
	headless.run_step(&run)
	testing.expect_value(t, hero.class, g.Class.Rogue)
	scenarios.expect_synced(t, &run)
}

// Command_Dev_Set_Class turns the sender's hero into the class, which walks at that class's speed; Any leaves it.
@(test)
a_dev_command_sets_the_class :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1) // the scripted Profile: a Knight
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 0)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Rogue})
	testing.expect_value(t, hero.class, g.Class.Rogue)
	play(&run, {0 = {move_x = 127}})
	speed := g.CLASS_SPECS[g.Class.Rogue].max_speed
	testing.expectf(t, abs(hero.vel.x - speed) < 0.05, "walks at %v m/s, a Rogue's is %v", hero.vel.x, speed)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Any})
	testing.expect_value(t, hero.class, g.Class.Rogue)
	scenarios.expect_synced(t, &run)
}

// The co-op pause: from the tick after anyone's Command_Set_Paused, no hero moves or turns whatever its input, and game
// time stands still; the State names who paused until anyone resumes, which lets them walk again. Each change is
// announced once.
@(test)
a_co_op_pause_holds_the_heroes :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	walk := [g.PLAYERS]g.Input {
		0 = {move_x = 127},
		1 = {move_z = 127, aim = dmath.dir2({-1, 0})},
	}
	play(&run, walk)
	pause := headless.run_inputs(&run)
	sim.add_command(&pause, 1, g.Command_Set_Paused{true})
	sim.add_command(&pause, 1, g.Command_Set_Paused{true}) // twice: one change, one event
	headless.run_step(&run, &pause)
	testing.expect_value(t, headless.run_events(&run, g.Event_Paused), 1)
	state := &run.simulation.state
	testing.expect_value(t, state.paused_by, sim.player_in_slot(run.simulation, 1))
	time := state.clock.time
	held := [2]g.Hero{sim.slot_data(run.simulation, 0)^, sim.slot_data(run.simulation, 1)^}
	play(&run, walk)
	testing.expect_value(t, state.clock.time, time)
	testing.expect_value(t, sim.slot_data(run.simulation, 0)^, held[0])
	testing.expect_value(t, sim.slot_data(run.simulation, 1)^, held[1])
	headless.run_command(&run, walk, 0, g.Command_Set_Paused{false})
	testing.expect_value(t, headless.run_events(&run, g.Event_Paused), 2) // so far: the pause and the resume
	testing.expect_value(t, state.paused_by, sim.Player{}) // another player resumed: nobody holds it
	play(&run, walk)
	testing.expect(t, sim.slot_data(run.simulation, 0).pos.x > held[0].pos.x + 1, "walks again after the resume")
	scenarios.expect_synced(t, &run)
}

// People come and go during the co-op pause: an arrival gets its body and a leaver loses its own on the paused tick,
// game time stands still, the State still names who paused (what a late joiner's snapshot shows it), and the newcomer
// walks once the game resumes.
@(test)
arrivals_and_leaves_while_paused :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	headless.run_command(&run, 0, g.Command_Set_Paused{true})
	time := run.simulation.state.clock.time
	leaver := sim.player_in_slot(run.simulation, 1)
	headless.run_seat(&run, 1, 0)
	headless.run_seat(&run, 2, 3)
	play(&run, {}, 0.25)
	testing.expect_value(t, run.simulation.state.clock.time, time)
	testing.expect_value(t, sim.player_data(&run.simulation.state.players, leaver).body, g.Hero{}.body)
	newcomer := sim.slot_data(run.simulation, 2)
	testing.expect(t, newcomer.body != g.Hero{}.body, "the newcomer has a body while paused")
	testing.expect_value(t, run.simulation.state.paused_by, sim.player_in_slot(run.simulation, 0))
	start := newcomer.pos
	headless.run_command(&run, 0, g.Command_Set_Paused{false})
	play(&run, {2 = {move_x = 127}}, 0.5)
	testing.expectf(
		t,
		newcomer.pos.x > start.x + 1,
		"the newcomer walks after the resume: %v from %v",
		newcomer.pos,
		start,
	)
	scenarios.expect_synced(t, &run)
}
