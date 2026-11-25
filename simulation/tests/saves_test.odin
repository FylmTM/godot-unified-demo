// The save's rule tests (saves.odin), each on a sync-tested run (headless.Run): a save is made at each surge and
// never between, holding the tally as it stood at the surge; a session started from it starts there; its JSON reads
// back, also without the fields an older build lacked.
package test_crypt_crew

import "core:testing"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

// A run's saves as unified takes them (sim.save_changed, on every tick: each is verified offline).
@(private = "file")
Saves :: struct {
	last:  g.Setup, // the newest save (the session's Setup before the first)
	count: int, // how many were taken
	at:    [4]u32, // the ticks the first four were taken on
}

// One step, and the save it gave.
@(private = "file")
step_saving :: proc(run: ^headless.Run(g.Game), saves: ^Saves) {
	headless.run_step(run)
	if sim.save_changed(run.simulation, run.simulation.tick, &saves.last) {
		if saves.count < len(saves.at) do saves.at[saves.count] = run.simulation.tick
		saves.count += 1
	}
}

// Steps until `surges` surges have risen (each SURGE_EVERY_S after the first), the heroes standing at their spawns.
@(private = "file")
until_surges :: proc(run: ^headless.Run(g.Game), saves: ^Saves, surges: u32) {
	limit := sim.Game_Time((g.SURGE_FIRST_S + f32(surges) * g.SURGE_EVERY_S) * g.TICK_HZ)
	for run.simulation.state.surges < surges && run.simulation.state.clock.time < limit do step_saving(run, saves)
}

// A new game saves nothing until its first surge rises; then it saves at each surge (the floor, the surges faced, the
// skeletons felled by then) and never between, however many fall after.
@(test)
a_save_is_made_at_each_surge :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	saves := Saves {
		last = run.simulation.setup,
	}
	headless.run_command(&run, 0, g.Command_Dev_Kill_Minions{}) // the floor's sleeping packs
	before := run.simulation.state.kills
	testing.expect_value(t, before, u32(headless.run_events(&run, g.Event_Minion_Died)))
	testing.expect(t, before > 0, "the packs fell")
	until_surges(&run, &saves, 1)
	testing.expect_value(t, saves.count, 1)
	testing.expect_value(
		t,
		saves.last,
		g.Setup{version = g.SAVE_VERSION, floor = .Floor_1, surges = 1, kills = before},
	)
	first := saves.at[0]
	testing.expect_value(t, first, run.simulation.state.level.since + g.SURGE_FIRST_TICKS)
	for run.simulation.state.rising > 0 do step_saving(&run, &saves) // the surge rises a few a tick
	headless.run_command(&run, 0, g.Command_Dev_Kill_Minions{})
	felled := run.simulation.state.kills
	testing.expect(t, felled > before, "the surge's skeletons fell")
	for _ in 0 ..< g.TICK_HZ do step_saving(&run, &saves)
	testing.expect_value(t, saves.count, 1) // kills between surges make no save
	until_surges(&run, &saves, 2)
	testing.expect_value(t, saves.count, 2)
	testing.expect_value(
		t,
		saves.last,
		g.Setup{version = g.SAVE_VERSION, floor = .Floor_1, surges = 2, kills = felled},
	)
	scenarios.expect_synced(t, &run)
}

// A session started from a save starts its floor with the save's tally, makes no save until its next surge, and that
// one carries the tally on.
@(test)
a_continue_starts_from_the_save :: proc(t: ^testing.T) {
	setup := g.Setup {
		version = g.SAVE_VERSION,
		floor   = .Floor_1,
		surges  = 7,
		kills   = 312,
	}
	run := headless.run_begin(&g.GAME, 1, setup, seated = 2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	testing.expect_value(t, state.level.id, g.Level_Id.Floor_1)
	testing.expect_value(t, state.surges, 7)
	testing.expect_value(t, state.kills, 312)
	saves := Saves {
		last = run.simulation.setup,
	}
	headless.run_command(&run, 0, g.Command_Dev_Kill_Minions{}) // the floor's sleeping packs
	felled := u32(headless.run_events(&run, g.Event_Minion_Died))
	testing.expect_value(t, state.kills, 312 + felled)
	for _ in 0 ..< g.TICK_HZ do step_saving(&run, &saves)
	testing.expect_value(t, saves.count, 0) // a second in, before the next surge: the save it continues stands
	until_surges(&run, &saves, 8)
	testing.expect_value(t, saves.count, 1)
	testing.expect_value(
		t,
		saves.last,
		g.Setup{version = g.SAVE_VERSION, floor = .Floor_1, surges = 8, kills = 312 + felled},
	)
	scenarios.expect_synced(t, &run)
}

// A Setup of another save version starts a new game: Floor 1, no tally, and no save before its first surge, whose
// save is a new game's (its own surges, not the Setup's).
@(test)
another_save_version_starts_a_new_game :: proc(t: ^testing.T) {
	setup := g.Setup {
		version = g.SAVE_VERSION + 1,
		surges  = 9,
		kills   = 99,
	}
	run := headless.run_begin(&g.GAME, 1, setup, seated = 1)
	defer headless.run_end(&run)
	testing.expect_value(t, run.simulation.state.surges, 0)
	testing.expect_value(t, run.simulation.state.kills, 0)
	saves := Saves {
		last = run.simulation.setup,
	}
	for _ in 0 ..< g.TICK_HZ do step_saving(&run, &saves)
	testing.expect_value(t, saves.count, 0)
	until_surges(&run, &saves, 1)
	testing.expect_value(t, saves.count, 1)
	testing.expect_value(t, saves.last, g.Setup{version = g.SAVE_VERSION, floor = .Floor_1, surges = 1})
	scenarios.expect_synced(t, &run)
}

// The tally outlives a wipe: the floor starts over (restart_floor) with the surges faced and the skeletons felled
// kept, no save is made by the restart, and the next surge's save carries them on.
@(test)
the_tally_outlives_a_wipe :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	saves := Saves {
		last = run.simulation.setup,
	}
	headless.run_command(&run, 0, g.Command_Dev_Kill_Minions{})
	until_surges(&run, &saves, 1)
	felled := run.simulation.state.kills
	for slot in 0 ..< 2 do hurt(&run, slot, g.HERO_HP)
	for _ in 0 ..< g.TICK_HZ / 4 do step_saving(&run, &saves)
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 1)
	testing.expect_value(t, run.simulation.state.surges, 1)
	testing.expect_value(t, run.simulation.state.kills, felled)
	testing.expect_value(t, saves.count, 1) // the restart makes no save
	until_surges(&run, &saves, 2)
	testing.expect_value(t, saves.count, 2)
	testing.expect_value(
		t,
		saves.last,
		g.Setup{version = g.SAVE_VERSION, floor = .Floor_1, surges = 2, kills = felled},
	)
	scenarios.expect_synced(t, &run)
}

// A save's JSON reads back as itself; one without the fields a later build added reads them as the defaults; one
// naming a floor this build lacks is refused, with the reason.
@(test)
a_save_reads_back_from_json :: proc(t: ^testing.T) {
	saved := g.Setup {
		version = g.SAVE_VERSION,
		floor   = .Floor_1,
		surges  = 4,
		kills   = 120,
	}
	text := sim.setup_to_json(&saved, context.temp_allocator)
	read, problem := sim.setup_from_json(&g.GAME, text)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, read, saved)
	older, older_problem := sim.setup_from_json(&g.GAME, `{"version": 1, "floor": "Floor_1", "surges": 4}`)
	testing.expect_value(t, older_problem, "")
	testing.expect_value(t, older, g.Setup{version = 1, floor = .Floor_1, surges = 4})
	_, refused := sim.setup_from_json(&g.GAME, `{"version": 1, "floor": "Floor_9", "surges": 4, "kills": 1}`)
	testing.expect(t, refused != "", "a floor this build lacks is refused")
}
