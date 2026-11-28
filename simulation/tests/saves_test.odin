// The save's rule tests (saves.odin), each on a sync-tested run (headless.Run): a save is made at the run's save
// points (its beginning, a descent, a life lost, its end) and never between, a surge's rise included; it holds the
// heroes' boons by profile id, and a Continue gives each member its own row back once (a second machine of the same id
// gets nothing), whatever slot it arrives in; another save version starts a new game; a save of a floor no run is saved
// on, or of a run with no life, is refused; its JSON reads back, the heroes' list included.
package test_crypt_crew

import "core:testing"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

// A run's saves as unified takes them (sim.save_changed, on every tick: each is verified offline).
Saves :: struct {
	last:  g.Setup, // the newest save (the session's Setup before the first)
	count: int, // how many were taken
}

// One step, and the save it gave.
step_saving :: proc(run: ^headless.Run(g.Game), saves: ^Saves) {
	headless.run_step(run)
	take_save(run, saves)
}

// The save this tick gave, if any.
take_save :: proc(run: ^headless.Run(g.Game), saves: ^Saves) {
	if sim.save_changed(run.simulation, run.simulation.tick, &saves.last) do saves.count += 1
}

// A profile of id `id` playing `class`.
profile :: proc(id: u64, class: g.Class) -> g.Profile {
	return {id = id, class = class}
}

// A new game on Floor 1 saves at once (the run begins there: its number, its lives, no tally), then nothing while
// surges rise and skeletons fall, then at the descent (the depth, the hoard's gold, each hero's boons by its id).
@(test)
a_save_is_made_at_each_save_point_and_never_between :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	saves := Saves {
		last = run.simulation.setup,
	}
	step_saving(&run, &saves)
	testing.expect_value(t, saves.count, 1)
	begun := saves.last
	testing.expect_value(t, begun.floor, g.Level_Id.Floor_1)
	testing.expect_value(t, begun.run_number, 1)
	testing.expect_value(t, begun.lives, g.DIFFICULTY[.Normal].lives)
	headless.run_command(&run, 0, g.Command_Dev_Kill_Minions{})
	limit := sim.Game_Time((g.SURGE_FIRST_S + 2 * g.SURGE_EVERY_S) * g.TICK_HZ)
	for run.simulation.state.surges < 2 && run.simulation.state.clock.time < limit {
		step_up(&run) // a hero the surges down is revived: no wipe (which would save)
		take_save(&run, &saves)
	}
	testing.expect_value(t, run.simulation.state.surges, 2)
	testing.expect(t, run.simulation.state.kills > 0, "the packs fell")
	testing.expect_value(t, saves.count, 1) // the surges and the kills made no save
	clear_minions(&run)
	clear_elites(&run)
	descend(&run)
	take_save(&run, &saves)
	testing.expect_value(t, saves.count, 2)
	testing.expect_value(t, saves.last.depth, 1)
	testing.expect_value(t, saves.last.gold, g.HOARD_GOLD)
	testing.expect_value(t, saves.last.surges, run.simulation.state.surges)
	testing.expect_value(t, int(saves.last.heroes.count), 2)
	for slot in 0 ..< 2 {
		row := sim.slice(&saves.last.heroes)[slot]
		hero := sim.slot_data(run.simulation, slot)
		testing.expect_value(t, row.id, u64(slot + 1)) // scripted_profile's
		testing.expect_value(t, row.boons, hero.boons)
		testing.expect_value(t, row.class, hero.class)
	}
	scenarios.expect_synced(t, &run)
}

// A Continue gives each member the row of its profile's id, whichever slot it sits in, and the class it played; a
// second machine of the same id is a duplicate, gets nothing, and a leave and a rejoin take nothing more; the rows of
// members who haven't come back are carried into the next save, and so is an absent member's own, its id's row kept
// from the duplicate present. The run (its number, lives and depth) and the tally (its surges, felled and purse) go on
// from the save.
@(test)
a_continue_gives_each_id_its_boons_once :: proc(t: ^testing.T) {
	saved := g.Setup {
		version    = g.SAVE_VERSION,
		floor      = .Floor_1,
		difficulty = .Hard,
		lives      = 1,
		surges     = 7,
		kills      = 312,
		gold       = 340,
		depth      = 1,
		run_number = 3,
	}
	sim.append(&saved.heroes, g.Saved_Hero{id = 11, boons = #partial{.Keen_Edge = 2}, class = .Mage})
	sim.append(
		&saved.heroes,
		g.Saved_Hero{id = 22, boons = #partial{.Thick_Hide = 1, .Swift_Boots = 1}, class = .Rogue},
	)
	sim.append(&saved.heroes, g.Saved_Hero{id = 33, boons = #partial{.Field_Medic = 3}, class = .Knight})
	run := headless.run_begin(&g.GAME, 1, saved)
	defer headless.run_end(&run)
	headless.run_seat(&run, 0, 1, profile(22, .Any)) // id 22 in slot 0: the second row's
	headless.run_seat(&run, 1, 2, profile(11, .Barbarian)) // id 11, wishing for a class: the first row's boons
	headless.run_seat(&run, 2, 3, profile(22, .Any)) // a second machine of id 22
	headless.run_step(&run)
	state := &run.simulation.state
	testing.expect_value(t, state.run.number, 3)
	testing.expect_value(t, state.run.lives, 1)
	testing.expect_value(t, state.run.difficulty, g.Difficulty.Hard)
	testing.expect_value(t, state.depth, 1)
	testing.expect_value(t, state.gold, 340)
	testing.expect_value(t, state.surges, 7)
	testing.expect_value(t, state.kills, 312)
	first, second := sim.slot_data(run.simulation, 0), sim.slot_data(run.simulation, 1)
	testing.expect_value(t, first.boons, #partial g.Boons{.Thick_Hide = 1, .Swift_Boots = 1})
	testing.expect_value(t, first.class, g.Class.Rogue) // the class it played, its Profile wishing for none
	testing.expect_value(t, first.hp, g.HERO_HP + g.THICK_HIDE_HP) // its body has its boons' health
	testing.expect_value(t, second.boons, #partial g.Boons{.Keen_Edge = 2})
	testing.expect_value(t, second.class, g.Class.Barbarian) // its wish
	testing.expect_value(t, sim.slot_data(run.simulation, 2).boons, g.Boons{}) // the row was taken
	testing.expect(
		t,
		sim.slot_data(run.simulation, 2).duplicate && !first.duplicate,
		"the second machine is the duplicate",
	)
	testing.expect_value(t, state.run.claimed, 0b011)
	headless.run_seat(&run, 2, 0)
	headless.run_step(&run)
	headless.run_seat(&run, 2, 4, profile(22, .Any))
	headless.run_step(&run)
	testing.expect_value(t, sim.slot_data(run.simulation, 2).boons, g.Boons{})
	saves := Saves {
		last = run.simulation.setup,
	}
	for _ in 0 ..< g.TICK_HZ do step_saving(&run, &saves)
	testing.expect_value(t, saves.count, 0) // the Continue's save stands until its next save point
	testing.expect(t, sim.slot_data(run.simulation, 2).duplicate, "a duplicate still, back again")
	headless.run_seat(&run, 0, 0) // id 22's own member steps away: its duplicate stays
	headless.run_step(&run)
	clear_minions(&run)
	clear_elites(&run)
	headless.run_command(&run, 1, g.Command_Dev_Board{}) // down with the two left: the duplicate picks a boon too
	for _ in 0 ..< 10 * g.TICK_HZ {
		if run.simulation.state.lift.phase == .Choosing do break
		headless.run_step(&run)
	}
	inputs := headless.run_inputs(&run)
	for slot in 1 ..< 3 do sim.add_command(&inputs, slot, g.Command_Pick_Boon{0})
	headless.run_step(&run, &inputs)
	take_save(&run, &saves)
	testing.expect_value(t, saves.count, 1)
	rows := sim.slice(&saves.last.heroes)
	testing.expect_value(t, len(rows), 3)
	if len(rows) == 3 {
		testing.expect(
			t,
			rows[0].id == 11 && rows[1].id == 22 && rows[2].id == 33,
			"the present, then the absent member, then the unclaimed row; the duplicate never",
		)
		testing.expect_value(t, rows[1].boons, #partial g.Boons{.Thick_Hide = 1, .Swift_Boots = 1})
		testing.expect_value(t, rows[2].boons, #partial g.Boons{.Field_Medic = 3})
	}
	testing.expect_value(t, saves.last.surges, 7)
	testing.expect_value(t, saves.last.kills, 312)
	testing.expect_value(t, saves.last.lives, 1)
	testing.expect_value(t, saves.last.depth, 2)
	testing.expect_value(t, saves.last.run_number, 3)
	scenarios.expect_synced(t, &run)
}

// A Setup of another save version (a version 1 save) starts a new game: no tally, no boons taken back, and its own
// run's save at once.
@(test)
another_save_version_starts_a_new_game :: proc(t: ^testing.T) {
	setup := g.Setup {
		version = 1,
		floor   = .Floor_1,
		surges  = 9,
		kills   = 99,
	}
	sim.append(&setup.heroes, g.Saved_Hero{id = 1, boons = #partial{.Keen_Edge = 3}, class = .Mage})
	run := headless.run_begin(&g.GAME, 1, setup, seated = 1)
	defer headless.run_end(&run)
	saves := Saves {
		last = run.simulation.setup,
	}
	step_saving(&run, &saves)
	testing.expect_value(t, run.simulation.state.surges, 0)
	testing.expect_value(t, run.simulation.state.kills, 0)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).boons, g.Boons{})
	testing.expect_value(t, saves.count, 1)
	testing.expect_value(t, saves.last.version, g.SAVE_VERSION)
	testing.expect_value(t, saves.last.surges, 0)
	testing.expect_value(t, saves.last.lives, g.DIFFICULTY[.Normal].lives)
	scenarios.expect_synced(t, &run)
}

// A save's JSON reads back as itself, the heroes' list included; one without the fields a later build added reads them
// as the defaults; one naming a floor this build lacks, a floor no run is saved on, or a run with no life is refused.
@(test)
a_save_reads_back_from_json :: proc(t: ^testing.T) {
	saved := g.Setup {
		version    = g.SAVE_VERSION,
		floor      = .Floor_1,
		mode       = .Crypt,
		difficulty = .Hard,
		lives      = 2,
		surges     = 4,
		kills      = 120,
		gold       = 340,
		depth      = 1,
		run_number = 2,
	}
	sim.append(
		&saved.heroes,
		g.Saved_Hero{id = 1 << 61 + 7, boons = #partial{.Keen_Edge = 2, .Field_Medic = 1}, class = .Mage},
	)
	sim.append(&saved.heroes, g.Saved_Hero{id = 9, boons = #partial{.Thick_Hide = 3}, class = .Knight})
	text := sim.setup_to_json(&saved, context.temp_allocator)
	read, problem := sim.setup_from_json(&g.GAME, text)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, read, saved)
	older, older_problem := sim.setup_from_json(&g.GAME, `{"version": 2, "floor": "Floor_1", "lives": 1, "surges": 4}`)
	testing.expect_value(t, older_problem, "")
	testing.expect_value(t, older, g.Setup{version = 2, floor = .Floor_1, lives = 1, surges = 4})
	hub, hub_problem := sim.setup_from_json(&g.GAME, `{"version": 2, "floor": "Hub"}`)
	testing.expect_value(t, hub_problem, "") // a run that ended: no life needed, no run to continue
	testing.expect_value(t, hub.floor, g.Level_Id.Hub)
	_, unknown := sim.setup_from_json(&g.GAME, `{"version": 2, "floor": "Floor_9", "lives": 1}`)
	testing.expect(t, unknown != "", "a floor this build lacks is refused")
	_, arena := sim.setup_from_json(&g.GAME, `{"version": 2, "floor": "Arena", "lives": 1}`)
	testing.expect(t, arena != "", "a floor no run is saved on is refused")
	_, lifeless := sim.setup_from_json(&g.GAME, `{"version": 2, "floor": "Floor_1", "lives": 0}`)
	testing.expect(t, lifeless != "", "a run with no life is refused")
	_, preset := sim.setup_from_json(&g.GAME, `{"floor": "Arena", "mode": "Pit"}`)
	testing.expect_value(t, preset, "") // a new game may start anywhere
}
