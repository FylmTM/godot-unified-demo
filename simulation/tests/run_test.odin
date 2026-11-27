// The run's rule tests (run.odin): the hub is harmless (no damage, no surge, no wipe) and a joiner arrives in it; its
// lift goes with everyone aboard and no hoard, into the run its shrines set; a shrine turns once for two presses on one
// tick, and locks while the lift boards; a wipe costs a life (the purse back at the save point's, the lives in the
// save), the last one ends the run, which shows its results and goes back to the hub; a run ended mid-choice closes
// the choice; Hard's numbers (a larger surge, tougher, harder-hitting skeletons, more gold) and the depth ramp; a
// second run's boon offers aren't the first's, and the card the HUD shows is the one a pick takes. Each on a
// sync-tested run (headless.Run) that ends synced.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

// A session that starts in the hub, as the app's New game does.
HUB :: g.Setup {
	floor = .Hub,
}

// Where slot `slot`'s hero stands aboard the floor's lift: its corner of the deck's top.
@(private = "file")
on_lift :: proc(run: ^headless.Run(g.Game), slot: int) -> [3]f32 {
	top := floor_of(run).places.lift.path.points[0] + {0, g.LIFT_HALF.y, 0}
	return top + [3]f32{f32(slot & 1) * 2 - 1, 0, f32(slot >> 1) * 2 - 1} * g.LIFT_SLOT_SPREAD
}

// The hub's shrine for `setting`.
@(private = "file")
shrine_at :: proc(run: ^headless.Run(g.Game), setting: g.Shrine_Setting) -> [3]f32 {
	return floor_of(run).places.shrines[setting].pos
}

// Steps until the whole party has stayed down and a life went (or `seconds` passed): the heroes of `slots` downed first.
@(private = "file")
wipe :: proc(run: ^headless.Run(g.Game), slots: int, seconds: f32 = 10) {
	lost := headless.run_events(run, g.Event_Life_Lost)
	for slot in 0 ..< slots do hurt(run, slot, 999)
	for _ in 0 ..< int(seconds * g.TICK_HZ) {
		if headless.run_events(run, g.Event_Life_Lost) > lost do break
		headless.run_step(run)
	}
}

// The hub hurts nobody: a dev blow and the swings of skeletons raised round the party take nothing, no surge rises in
// half a minute, nobody goes down so nobody wipes; a joiner arrives beside the party, whole.
@(test)
the_hub_is_harmless :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, HUB, seated = 2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	headless.run_step(&run)
	testing.expect_value(t, state.level.id, g.Level_Id.Hub)
	testing.expect_value(t, state.run.phase, g.Run_Phase.Hub)
	hurt(&run, 0, g.HERO_HP)
	headless.run_command(&run, 1, g.Command_Dev_Spawn_Minions{8})
	play(&run, {}, 30)
	testing.expect_value(t, headless.run_events(&run, g.Event_Surge), 0)
	testing.expect(t, headless.run_events(&run, g.Event_Hero_Hurt) == 0, "a hero was hurt in the hub")
	testing.expect_value(t, sim.slot_data(run.simulation, 0).hp, g.HERO_HP)
	testing.expect_value(t, headless.run_events(&run, g.Event_Party_Wiped), 0)
	headless.run_seat(&run, 2, 3)
	headless.run_step(&run)
	joiner := sim.slot_data(run.simulation, 2)
	testing.expect_value(t, joiner.hp, g.HERO_HP)
	spawned, _ := headless.run_last_event(&run, g.Event_Hero_Spawned)
	testing.expect(t, spawned.beside, "the joiner arrives beside the party")
	testing.expect_value(t, state.level.id, g.Level_Id.Hub)
	scenarios.expect_synced(t, &run)
}

// The hub's lift waits for everyone, and goes with no hoard: one hero aboard keeps it waiting; both aboard, it boards,
// goes down, and the run begins on the crypt's first floor with the difficulty's lives, its number 1.
@(test)
the_hub_lift_needs_everyone_and_no_hoard :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, HUB, seated = 2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	headless.run_step(&run)
	testing.expect(t, !floor_of(&run).places.lift.hoard && state.hoard.body == {}, "the hub's lift wants no hoard")
	place_hero(&run, 0, on_lift(&run, 0))
	play(&run, {}, 3)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Waiting)
	place_hero(&run, 1, on_lift(&run, 1))
	for _ in 0 ..< 10 * g.TICK_HZ {
		if headless.run_events(&run, g.Event_Run_Began) > 0 do break
		headless.run_step(&run)
	}
	began, ok := headless.run_last_event(&run, g.Event_Run_Began)
	testing.expect(t, ok, "the run began")
	testing.expect_value(t, began, g.Event_Run_Began{mode = .Crypt, difficulty = .Normal})
	testing.expect_value(t, state.level.id, g.FLOOR_ORDER[0])
	testing.expect_value(t, state.run.phase, g.Run_Phase.Playing)
	testing.expect_value(t, state.run.lives, g.DIFFICULTY[.Normal].lives)
	testing.expect_value(t, state.run.number, 1)
	scenarios.expect_synced(t, &run)
}

// Two heroes pressing Interact at a shrine on one tick turn it once; a press after its cooldown turns it again; the
// difficulty shrine turns to Hard; while the lift boards, a press turns nothing. The run then begins as the shrines say.
@(test)
a_shrine_turns_once_a_cooldown_and_locks_while_boarding :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, HUB, seated = 2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	headless.run_step(&run)
	mode := shrine_at(&run, .Mode)
	place_hero(&run, 0, mode + {-0.8, 0, 0.6})
	place_hero(&run, 1, mode + {0.8, 0, 0.6}, {-1, 0})
	both: [g.PLAYERS]g.Input
	both[0].buttons, both[1].buttons = {.Interact}, {.Interact}
	headless.run_step(&run, both)
	testing.expect_value(t, state.run.mode, g.Mode.Pit)
	testing.expect_value(t, headless.run_events(&run, g.Event_Shrine), 1)
	turned, _ := headless.run_last_event(&run, g.Event_Shrine)
	testing.expect_value(
		t,
		turned,
		g.Event_Shrine{player = sim.player_in_slot(run.simulation, 0), sets = .Mode, value = u8(g.Mode.Pit)},
	)
	play(&run, {}, g.SHRINE_COOLDOWN_S)
	press(&run, 1, .Interact)
	testing.expect_value(t, state.run.mode, g.Mode.Crypt)
	place_hero(&run, 0, shrine_at(&run, .Difficulty) + {0, 0, 0.8})
	press(&run, 0, .Interact)
	testing.expect_value(t, state.run.difficulty, g.Difficulty.Hard)
	play(&run, {}, g.SHRINE_COOLDOWN_S)
	state.lift.phase = .Boarding // as if the party were aboard: the shrines lock
	headless.run_pin(&run)
	press(&run, 0, .Interact)
	testing.expect_value(t, state.run.difficulty, g.Difficulty.Hard)
	testing.expect_value(t, headless.run_events(&run, g.Event_Shrine), 3)
	ride_lift(&run)
	testing.expect_value(t, state.run.difficulty, g.Difficulty.Hard)
	testing.expect_value(t, state.run.lives, g.DIFFICULTY[.Hard].lives)
	testing.expect_value(t, state.level.id, g.FLOOR_ORDER[0])
	scenarios.expect_synced(t, &run)
}

// A wipe costs a life: the floor starts over with the purse and the felled back at the save point's, the lives in the
// next save, and a Continue from it has no more; the last life ends the run (lost, its tally out), the results hold
// RUN_END_S with nobody hurt, and the party is back in the hub, whose save continues no run.
@(test)
a_wipe_costs_a_life_and_the_last_ends_the_run :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	clear_minions(&run)
	clear_elites(&run)
	saves := Saves {
		last = run.simulation.setup,
	}
	step_saving(&run, &saves)
	place_coin(&run, sim.slot_data(run.simulation, 0).pos, 4, g.LOOT_ARM_TICKS)
	headless.run_step(&run)
	testing.expect_value(t, state.gold, 4)
	wipe(&run, 2)
	take_save(&run, &saves)
	lost, _ := headless.run_last_event(&run, g.Event_Life_Lost)
	testing.expect_value(t, lost, g.Event_Life_Lost{lives = 2, gold = 0})
	testing.expect_value(t, state.run.lives, 2)
	testing.expect_value(t, state.gold, 0) // the save point's (the run's beginning)
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 1)
	testing.expect_value(t, saves.count, 2)
	testing.expect_value(t, saves.last.lives, 2)
	{ 	// a Continue: no life comes back
		continued := headless.run_begin(&g.GAME, 2, saves.last, seated = 1)
		defer headless.run_end(&continued)
		testing.expect_value(t, continued.simulation.state.run.lives, 2)
		scenarios.expect_synced(t, &continued)
	}
	wipe(&run, 2)
	testing.expect_value(t, state.run.lives, 1)
	wipe(&run, 2)
	take_save(&run, &saves)
	testing.expect_value(t, state.run.lives, 0)
	testing.expect_value(t, state.run.phase, g.Run_Phase.Lost)
	ended, over := headless.run_last_event(&run, g.Event_Run_Ended)
	testing.expect(t, over && !ended.won, "the run is lost")
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 2) // the last restarts nothing
	testing.expect_value(t, saves.last.floor, g.Level_Id.Hub) // no run to continue
	hurt(&run, 0, 10) // the results: nothing hurts
	headless.run_command(&run, 0, g.Command_Dev_Revive{})
	for _ in 0 ..< g.RUN_END_TICKS do headless.run_step(&run)
	testing.expect_value(t, state.level.id, g.Level_Id.Hub)
	testing.expect_value(t, state.run.phase, g.Run_Phase.Hub)
	scenarios.expect_synced(t, &run)
}

// A run ended while a choice is open (a dev end, at the lift's bottom) closes it: no pick counts after, the lift holds
// where it is, and the party goes back to the hub when the results are done.
@(test)
a_run_ended_mid_choice_closes_it :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	clear_elites(&run)
	ride_lift(&run)
	testing.expect_value(t, run.simulation.state.lift.phase, g.Lift_Phase.Choosing)
	headless.run_command(&run, 0, g.Command_Dev_End_Run{won = true})
	closed, ok := headless.run_last_event(&run, g.Event_Choice)
	testing.expect(t, ok && !closed.open, "the choice closed")
	ended, _ := headless.run_last_event(&run, g.Event_Run_Ended)
	testing.expect(t, ended.won, "won")
	headless.run_command(&run, 0, g.Command_Pick_Boon{0})
	testing.expect_value(t, headless.run_events(&run, g.Event_Boon_Picked), 0)
	for _ in 0 ..< g.BOON_TIMEOUT_TICKS / 4 do headless.run_step(&run)
	testing.expect_value(t, run.simulation.state.depth, 0) // nobody descends during the results
	for _ in 0 ..< g.RUN_END_TICKS do headless.run_step(&run)
	testing.expect_value(t, run.simulation.state.level.id, g.Level_Id.Hub)
	scenarios.expect_synced(t, &run)
}

// Hard: a surge rises DIFFICULTY's larger, its skeletons tougher (and tougher again each floor down) and hitting
// harder, its elites tougher, and the hoard pays more.
@(test)
hard_is_harder :: proc(t: ^testing.T) {
	heroes :: 2
	first_surge :: proc(difficulty: g.Difficulty) -> i32 {
		run := headless.run_begin(&g.GAME, 1, g.Setup{difficulty = difficulty}, seated = heroes)
		defer headless.run_end(&run)
		for headless.run_events(&run, g.Event_Surge) == 0 do headless.run_step(&run)
		surge, _ := headless.run_last_event(&run, g.Event_Surge)
		return surge.count
	}
	normal := g.SURGE_BASE + g.SURGE_PER_HERO * heroes
	testing.expect_value(t, first_surge(.Normal), i32(normal))
	testing.expect_value(t, first_surge(.Hard), i32(dmath.round(f32(normal) * g.DIFFICULTY[.Hard].surge)))
	testing.expect(t, first_surge(.Hard) > first_surge(.Normal), "Hard's surge is larger")

	run := headless.run_begin(&g.GAME, 1, g.Setup{difficulty = .Hard}, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	clear_elites(&run)
	state := &run.simulation.state
	place_hero(&run, 0, spawn_of(&run, 0), {1, 0})
	minion := sim.get(&state.minions, place_minion(&run, spawn_of(&run, 0) + {1.1, 0, 0}, .Chase, {-1, 0}))
	hard_hp := i16(dmath.round(f32(g.MINION_HP) * g.DIFFICULTY[.Hard].minion_hp))
	testing.expect_value(t, minion.hp, hard_hp)
	for headless.run_events(&run, g.Event_Hero_Hurt) == 0 && state.clock.time < 600 do headless.run_step(&run)
	struck, _ := headless.run_last_event(&run, g.Event_Hero_Hurt)
	testing.expect_value(t, struck.damage, i16(dmath.round(f32(g.MINION_DAMAGE) * g.DIFFICULTY[.Hard].minion_damage)))
	headless.run_command(&run, 0, g.Command_Dev_Spawn_Elite{.Warrior})
	elite, _, _ := sim.item_at(&state.elites, 0)
	testing.expect_value(t, elite.hp, i16(dmath.round(f32(g.ELITE_SPECS[.Warrior].hp) * g.DIFFICULTY[.Hard].elite_hp)))
	clear_minions(&run)
	clear_elites(&run)
	headless.run_command(&run, 0, g.Command_Dev_Revive{})
	descend(&run)
	testing.expect_value(t, state.gold, u32(dmath.round(f32(g.HOARD_GOLD) * g.DIFFICULTY[.Hard].gold)))
	deeper := sim.get(&state.minions, place_minion(&run, spawn_of(&run, 0) + {3, 0, 0}, .Idle))
	ramp := g.DIFFICULTY[.Hard].minion_hp * (1 + g.DEPTH_HP * f32(state.depth))
	testing.expect_value(t, deeper.hp, i16(dmath.round(f32(g.MINION_HP) * ramp)))
	testing.expect(t, deeper.hp > hard_hp, "a floor down, tougher")
	scenarios.expect_synced(t, &run)
}

// A second run's boon offers aren't the first's (the offer is keyed by the run's number too), and in each, the card
// the HUD shows before the pick is the boon the pick grants.
@(test)
each_run_deals_its_own_offers :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 4, HUB, seated = 1)
	defer headless.run_end(&run)
	state := &run.simulation.state
	player := sim.player_in_slot(run.simulation, 0)
	offers: [2]g.Boon_Offer
	for &offer, i in offers {
		ride_lift(&run) // the hub's: the run begins
		testing.expect_value(t, state.run.number, u32(i + 1))
		clear_minions(&run)
		clear_elites(&run)
		ride_lift(&run)
		testing.expect_value(t, state.lift.phase, g.Lift_Phase.Choosing)
		offer = g.boon_offer(
			run.simulation.seed,
			g.offer_index(&state.run),
			player,
			sim.slot_data(run.simulation, 0).boons,
		)
		play(&run, {}, 0.5) // the HUD shows it a while before the press
		headless.run_command(&run, 0, g.Command_Pick_Boon{2})
		picked, _ := headless.run_last_event(&run, g.Event_Boon_Picked)
		testing.expect_value(t, picked.boon, offer.boons[2])
		headless.run_command(&run, 0, g.Command_Dev_End_Run{won = false})
		for state.run.phase != .Hub do headless.run_step(&run)
	}
	testing.expect(t, offers[0].boons != offers[1].boons, "the second run deals the first's cards")
	scenarios.expect_synced(t, &run)
}
