// The Pit's rule tests (arena.odin): a Pit run plays the arena with one life and saves only the hub's floor; wave n's
// size, and the clock between waves; the lull after wave PIT_FIRST_BOON (then every PIT_BOON_EVERY-th) holds the next
// until few are alive, minions and elites, then the rest fall, the downed rise and one choice opens (closing at its
// timeout for the late), after which the held wave rises; a lull ends at PIT_LULL_MAX_S however many stand; the
// elites keep the Pit's cadence; a fallen party gets no lull; a wipe ends the run, and a run ended in the lull's choice
// closes it. Each on a
// sync-tested run (headless.Run) that ends synced.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

// A session that plays the Pit at once (the shrines' mode, set as a preset).
PIT :: g.Setup {
	floor = .Arena,
	mode  = .Pit,
}

// Steps until the next surge (or `seconds` passed), and that surge; a hero the waves down is revived at once, so the
// one life lasts.
@(private = "file")
next_surge :: proc(run: ^headless.Run(g.Game), seconds: f32 = 30) -> (surge: g.Event_Surge, at: sim.Game_Time) {
	surges := headless.run_events(run, g.Event_Surge)
	for _ in 0 ..< int(seconds * g.TICK_HZ) {
		step_up(run)
		if headless.run_events(run, g.Event_Surge) > surges do break
	}
	surge, _ = headless.run_last_event(run, g.Event_Surge)
	return surge, run.simulation.state.clock.time
}

// The run's waves faced as if `faced` had risen, the next one due now (the surge clock run out), pinned.
@(private = "file")
as_if_faced :: proc(run: ^headless.Run(g.Game), faced: u32) {
	state := &run.simulation.state
	state.floor_surges, state.surges = faced, faced
	state.surge = {}
	headless.run_pin(run)
}

// A Pit run plays the arena with one life; its waves are pit_wave's (times the difficulty's), wave 1 SURGE_FIRST_S in
// and wave 2 PIT_SURGE_S after it; its only save is the hub's floor (none of the Pit's own).
@(test)
the_pits_waves_grow_and_it_saves_no_run :: proc(t: ^testing.T) {
	heroes :: 2
	run := headless.run_begin(&g.GAME, 1, PIT, seated = heroes)
	defer headless.run_end(&run)
	state := &run.simulation.state
	saves := Saves {
		last = run.simulation.setup,
	}
	step_saving(&run, &saves)
	testing.expect_value(t, state.run.lives, g.PIT_LIVES)
	testing.expect_value(t, saves.count, 1)
	testing.expect_value(t, saves.last.floor, g.Level_Id.Hub)
	first, first_at := next_surge(&run)
	testing.expect_value(t, first.count, i32(g.pit_wave(1, heroes)))
	testing.expect_value(t, u32(first_at) - state.level.since, g.SURGE_FIRST_TICKS)
	second, second_at := next_surge(&run)
	testing.expect_value(t, second.count, i32(g.pit_wave(2, heroes)))
	testing.expect_value(t, u32(second_at - first_at), g.PIT_SURGE_TICKS)
	testing.expect_value(t, int(second.count - first.count), g.PIT_EARLY_GROWTH)
	take_save(&run, &saves)
	testing.expect_value(t, saves.count, 1) // the waves make no save

	hard := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena, mode = .Pit, difficulty = .Hard}, seated = heroes)
	defer headless.run_end(&hard)
	hard_first, _ := next_surge(&hard)
	testing.expect_value(t, hard_first.count, i32(dmath.round(f32(g.pit_wave(1, heroes)) * g.DIFFICULTY[.Hard].surge)))
	scenarios.expect_synced(t, &run)
	scenarios.expect_synced(t, &hard)
}

// After wave PIT_FIRST_BOON the next holds while more than PIT_LULL stand; once few enough do, they fall, the
// downed rise at REVIVE_HP, and one choice opens (nobody hurt meanwhile); once everyone has picked, it closes and the
// held wave rises at once, and the next wave after it holds no lull.
@(test)
the_lull_opens_one_choice :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, PIT, seated = 2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	headless.run_step(&run)
	headless.run_command(&run, 0, g.Command_Dev_Spawn_Minions{g.PIT_LULL + 4})
	as_if_faced(&run, g.PIT_FIRST_BOON)
	play(&run, {}, 1)
	testing.expect_value(t, state.pit.stage, g.Pit_Stage.Lull)
	testing.expect_value(t, headless.run_events(&run, g.Event_Surge), 0)
	hurt(&run, 1, 999)
	clear_minions(&run)
	for _ in 0 ..< g.PIT_LULL do place_minion(&run, spawn_of(&run, 0) + {8, 0, 0}, .Idle)
	headless.run_step(&run)
	testing.expect_value(t, state.pit.stage, g.Pit_Stage.Choosing)
	testing.expect_value(t, headless.run_events(&run, g.Event_Choice), 1)
	testing.expect_value(t, int(headless.run_events(&run, g.Event_Minion_Died)), g.PIT_LULL)
	testing.expect_value(t, state.run.offers, 1)
	risen := sim.slot_data(run.simulation, 1)
	testing.expect_value(t, risen.action, g.Action.None)
	testing.expect_value(t, risen.hp, g.REVIVE_HP)
	hurt(&run, 0, 10)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).hp, g.HERO_HP) // nobody is hurt while choosing
	inputs := headless.run_inputs(&run)
	for slot in 0 ..< 2 do sim.add_command(&inputs, slot, g.Command_Pick_Boon{0})
	headless.run_step(&run, &inputs)
	testing.expect_value(t, headless.run_events(&run, g.Event_Boon_Picked), 2)
	testing.expect_value(t, state.pit.stage, g.Pit_Stage.Waves)
	testing.expect_value(t, headless.run_events(&run, g.Event_Surge), 1) // the held wave, at once
	testing.expect_value(t, state.floor_surges, g.PIT_FIRST_BOON + 1)
	closed, _ := headless.run_last_event(&run, g.Event_Choice)
	testing.expect(t, !closed.open, "the choice closed")
	next_surge(&run)
	testing.expect_value(t, state.pit.stage, g.Pit_Stage.Waves) // no second lull for the same waves
	testing.expect_value(t, headless.run_events(&run, g.Event_Choice), 2)
	scenarios.expect_synced(t, &run)
}

// A lull ends PIT_LULL_MAX_S on, however many stand: they all fall at once, by nobody's hand (Hit_Source.Fall).
@(test)
a_lull_ends_at_its_limit :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, PIT, seated = 1)
	defer headless.run_end(&run)
	state := &run.simulation.state
	headless.run_step(&run)
	for i in 0 ..< g.PIT_LULL + 6 {
		place_minion(&run, spawn_of(&run, 0) + {10 + f32(i % 4), 0, 10 + f32(i / 4)}, .Idle)
	}
	as_if_faced(&run, g.PIT_FIRST_BOON)
	headless.run_step(&run)
	testing.expect_value(t, state.pit.stage, g.Pit_Stage.Lull)
	for _ in 0 ..< g.PIT_LULL_MAX_TICKS - 2 do headless.run_step(&run)
	testing.expect_value(t, state.pit.stage, g.Pit_Stage.Lull)
	for _ in 0 ..< 4 {
		headless.run_step(&run)
		if state.pit.stage != .Lull do break
	}
	testing.expect_value(t, state.pit.stage, g.Pit_Stage.Choosing)
	died, _ := headless.run_last_event(&run, g.Event_Minion_Died)
	testing.expect_value(t, died.source, g.Hit_Source.Fall)
	testing.expect_value(t, g.minions_alive(&state.minions), 0)
	scenarios.expect_synced(t, &run)
}

// The Pit has one life: a wipe ends the run, lost, its save the hub's floor. A run ended in the lull's choice (a dev
// end) closes the choice: a pick after it counts for nothing.
@(test)
a_wipe_ends_the_pit_and_an_end_closes_its_choice :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, PIT, seated = 2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	saves := Saves {
		last = run.simulation.setup,
	}
	step_saving(&run, &saves)
	for slot in 0 ..< 2 do hurt(&run, slot, 999)
	for _ in 0 ..< 2 * g.WIPE_TICKS do step_saving(&run, &saves)
	testing.expect_value(t, state.run.phase, g.Run_Phase.Lost)
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 0)
	testing.expect_value(t, saves.last.floor, g.Level_Id.Hub)
	scenarios.expect_synced(t, &run)

	choosing := headless.run_begin(&g.GAME, 1, PIT, seated = 1)
	defer headless.run_end(&choosing)
	headless.run_step(&choosing)
	as_if_faced(&choosing, g.PIT_FIRST_BOON)
	play(&choosing, {}, 0.1)
	testing.expect_value(t, choosing.simulation.state.pit.stage, g.Pit_Stage.Choosing) // nobody stands: no wait
	headless.run_command(&choosing, 0, g.Command_Dev_End_Run{won = false})
	closed, _ := headless.run_last_event(&choosing, g.Event_Choice)
	testing.expect(t, !closed.open, "the choice closed with the run")
	testing.expect_value(t, choosing.simulation.state.pit, g.Pit{}) // the Pit's lulls end with the run
	headless.run_command(&choosing, 0, g.Command_Pick_Boon{0})
	testing.expect_value(t, headless.run_events(&choosing, g.Event_Boon_Picked), 0)
	scenarios.expect_synced(t, &choosing)
}

// A lull ends only on the skeletons it counts, minions and elites alike: PIT_LULL minions and an elite hold it. At its
// end every elite falls too and the waves' owed risers go; a choice one hero doesn't pick closes at BOON_TIMEOUT_S,
// giving it its first card (Event_Boon_Picked.auto); and the held wave rising nothing (the arena put back to the lull's
// wave) opens no second lull for the same waves.
@(test)
a_lull_holds_on_elites_and_its_choice_times_out :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, PIT, seated = 2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	headless.run_step(&run)
	for i in 0 ..< g.PIT_LULL do place_minion(&run, spawn_of(&run, 0) + {10 + f32(i % 3), 0, 10 + f32(i / 3)}, .Idle)
	headless.run_command(&run, 0, g.Command_Dev_Spawn_Elite{.Warrior})
	as_if_faced(&run, g.PIT_FIRST_BOON)
	play(&run, {}, 1)
	testing.expect_value(t, state.pit.stage, g.Pit_Stage.Lull)
	clear_minions(&run) // the elite alone: few enough
	state.rising = 5
	headless.run_pin(&run)
	headless.run_step(&run)
	testing.expect_value(t, state.pit.stage, g.Pit_Stage.Choosing)
	testing.expect_value(t, state.rising, 0)
	walk := sim.iterate(&state.elites)
	for elite in sim.next(&walk) do testing.expect_value(t, elite.phase, g.Elite_Phase.Dying)
	testing.expect_value(t, headless.run_events(&run, g.Event_Elite_Died), 1)
	headless.run_command(&run, 0, g.Command_Pick_Boon{1}) // slot 1 never picks
	for _ in 0 ..< g.BOON_TIMEOUT_TICKS - 2 do headless.run_step(&run)
	testing.expect_value(t, state.pit.stage, g.Pit_Stage.Choosing)
	for _ in 0 ..< 4 {
		headless.run_step(&run)
		if state.pit.stage != .Choosing do break
	}
	testing.expect_value(t, state.pit.stage, g.Pit_Stage.Waves)
	late, _ := headless.run_last_event(&run, g.Event_Boon_Picked)
	testing.expectf(
		t,
		late.auto && late.player == sim.player_in_slot(run.simulation, 1),
		"the late hero's pick, made for it: %v",
		late,
	)
	testing.expect_value(t, headless.run_events(&run, g.Event_Boon_Picked), 2)
	as_if_faced(&run, g.PIT_FIRST_BOON)
	clear_minions(&run)
	play(&run, {}, 0.5)
	testing.expect_value(t, state.pit.stage, g.Pit_Stage.Waves)
	scenarios.expect_synced(t, &run)
}

// Every PIT_ELITE_EVERY-th wave brings an elite, on Hard as on Normal (the Pit's cadence, not the difficulty's).
@(test)
the_pits_elites_keep_its_cadence :: proc(t: ^testing.T) {
	for difficulty in g.Difficulty {
		run := headless.run_begin(
			&g.GAME,
			1,
			g.Setup{floor = .Arena, mode = .Pit, difficulty = difficulty},
			seated = 1,
		)
		defer headless.run_end(&run)
		state := &run.simulation.state
		headless.run_step(&run)
		state.pit.lulls = 1 // past the first lull: the waves rise on
		for wave in 1 ..= u32(g.PIT_ELITE_EVERY) {
			as_if_faced(&run, wave - 1)
			headless.run_step(&run)
			alive := g.elites_alive(&state.elites)
			testing.expectf(
				t,
				(alive > 0) == (wave == g.PIT_ELITE_EVERY),
				"%v, wave %d: %d elites",
				difficulty,
				wave,
				alive,
			)
		}
		scenarios.expect_synced(t, &run)
	}
}

// Every present hero down, the wipe decides first: a lull at its limit neither ends nor stands the fallen party up (no
// choice, no boon), and the wipe ends the one-life run.
@(test)
a_fallen_party_gets_no_lull :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, PIT, seated = 2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	headless.run_step(&run)
	for i in 0 ..< g.PIT_LULL + 6 {
		place_minion(&run, spawn_of(&run, 0) + {10 + f32(i % 4), 0, 10 + f32(i / 4)}, .Idle)
	}
	as_if_faced(&run, g.PIT_FIRST_BOON)
	headless.run_step(&run)
	testing.expect_value(t, state.pit.stage, g.Pit_Stage.Lull)
	for _ in 0 ..< g.PIT_LULL_MAX_TICKS - g.TICK_HZ do headless.run_step(&run)
	for slot in 0 ..< 2 do hurt(&run, slot, 999)
	play(&run, {}, g.WIPE_S + 0.5)
	testing.expect_value(t, headless.run_events(&run, g.Event_Choice), 0)
	testing.expect_value(t, state.run.phase, g.Run_Phase.Lost)
	scenarios.expect_synced(t, &run)
}
