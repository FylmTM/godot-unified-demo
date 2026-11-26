// The boons' rule tests (boons.odin): the offer a pure keyed roll (the same whenever it is asked, distinct, never a
// boon at its top rank), a pick counting once and only while the lift waits on picks, the timeout's picks, a late
// joiner waited for and a leaver not, picks during a co-op pause, everyone picking on one tick, boons kept through a
// leave, a wipe and a level change, and what each boon does. Each on a sync-tested run (headless.Run) that ends synced.
package test_crypt_crew

import "core:testing"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

// A run of `seated` heroes, no minion or elite, its lift at the bottom waiting on picks (dev_board, then the ride).
@(private = "file")
choosing_run :: proc(seated: int, seed: u64 = 1) -> headless.Run(g.Game) {
	run := headless.run_begin(&g.GAME, seed, seated = seated)
	clear_minions(&run)
	clear_elites(&run)
	headless.run_command(&run, 0, g.Command_Dev_Board{})
	for _ in 0 ..< 10 * g.TICK_HZ {
		if run.simulation.state.lift.phase == .Choosing do break
		headless.run_step(&run)
	}
	assert(run.simulation.state.lift.phase == .Choosing, "the lift didn't reach the bottom")
	return run
}

// Slot `slot`'s offer now, as the HUD asks it (boon_offer on the state).
@(private = "file")
offer_of :: proc(run: ^headless.Run(g.Game), slot: int) -> g.Boon_Offer {
	hero := sim.slot_data(run.simulation, slot)
	return g.boon_offer(
		run.simulation.seed,
		run.simulation.state.depth,
		sim.player_in_slot(run.simulation, slot),
		hero.boons,
	)
}

// The offer is BOON_OFFER distinct boons, none at its top rank, the same whenever and however often it is asked (a
// keyed roll of the seed, the depth and the player, never the tick), and another player's or depth's differs somewhere.
@(test)
the_offer_is_a_keyed_roll :: proc(t: ^testing.T) {
	player := sim.Player {
		index = 1,
		id    = 1,
	}
	offer := g.boon_offer(7, 0, player, {})
	testing.expect_value(t, offer.count, g.BOON_OFFER)
	for boon, i in offer.boons {
		for other in offer.boons[i + 1:] do testing.expectf(t, boon != other, "%v offered twice", boon)
	}
	testing.expect_value(t, g.boon_offer(7, 0, player, {}), offer)
	differs := false
	for depth in u32(1) ..< 8 do differs ||= g.boon_offer(7, depth, player, {}).boons != offer.boons
	testing.expect(t, differs, "another depth, another offer")
	maxed := g.Boons{}
	for &rank, boon in maxed do if boon != .Keen_Edge && boon != .Field_Medic do rank = g.BOON_RANK_MAX
	two := g.boon_offer(7, 0, player, maxed)
	testing.expect_value(t, two.count, 2)
	testing.expect(t, two.boons[0] == .Keen_Edge && two.boons[1] == .Field_Medic, "the two left, in order")
	for _ in 0 ..< 32 { 	// none at the top rank, whatever the roll
		maxed = {}
		maxed[.Swift_Boots], maxed[.Quick_Hands] = g.BOON_RANK_MAX, g.BOON_RANK_MAX
		for depth in u32(0) ..< 16 {
			for boon in g.boon_offer(7, depth, player, maxed).boons {
				testing.expectf(t, maxed[boon] < g.BOON_RANK_MAX, "%v offered at its top rank", boon)
			}
		}
	}
}

// The boon a pick grants is the HUD's card at its index, asked before the pick and any number of ticks before it: the
// tick and the HUD compute the same offer (three heroes, each picking another card, in a few sessions).
@(test)
a_pick_grants_the_card_the_hud_showed :: proc(t: ^testing.T) {
	for seed in u64(1) ..= 3 {
		run := choosing_run(3, seed)
		defer headless.run_end(&run)
		shown: [3]g.Boon_Offer
		for &offer, slot in shown do offer = offer_of(&run, slot)
		play(&run, {}, 0.7) // the HUD showed them a while before the presses
		inputs := headless.run_inputs(&run)
		for slot in 0 ..< 3 do sim.add_command(&inputs, slot, g.Command_Pick_Boon{u8(slot)})
		headless.run_step(&run, &inputs)
		for slot in 0 ..< 3 {
			hero := sim.slot_data(run.simulation, slot)
			testing.expectf(
				t,
				hero.boons[shown[slot].boons[slot]] == 1,
				"seed %d slot %d: not the card shown",
				seed,
				slot,
			)
		}
		picked, _ := headless.run_last_event(&run, g.Event_Boon_Picked)
		testing.expect(t, !picked.auto, "their own picks")
		scenarios.expect_synced(t, &run)
	}
}

// A pick counts once a depth: a second one, sent before the lift leaves, changes nothing; and a pick sent while the
// lift isn't waiting on picks counts for nothing.
@(test)
a_pick_counts_once :: proc(t: ^testing.T) {
	run := choosing_run(2)
	defer headless.run_end(&run)
	before := offer_of(&run, 0)
	headless.run_command(&run, 0, g.Command_Pick_Boon{0})
	headless.run_command(&run, 0, g.Command_Pick_Boon{1}) // slot 1 hasn't picked: the lift still waits
	hero := sim.slot_data(run.simulation, 0)
	testing.expect_value(t, hero.boons[before.boons[0]], 1)
	testing.expect_value(t, hero.boons[before.boons[1]], 0)
	testing.expect_value(t, headless.run_events(&run, g.Event_Boon_Picked), 1)
	testing.expect_value(t, hero.picked, run.simulation.state.depth + 1)
	scenarios.expect_synced(t, &run)

	fresh := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&fresh)
	headless.run_command(&fresh, 0, g.Command_Pick_Boon{0}) // the lift waits at the top
	testing.expect_value(t, sim.slot_data(fresh.simulation, 0).boons, g.Boons{})
	scenarios.expect_synced(t, &fresh)
}

// Nobody picking, the lift leaves at BOON_TIMEOUT_S, each hero given its first offer (auto); a hero who picked keeps
// its pick.
@(test)
the_timeout_picks_the_first_offer :: proc(t: ^testing.T) {
	run := choosing_run(2)
	defer headless.run_end(&run)
	since := run.simulation.state.lift.since
	late := offer_of(&run, 1)
	headless.run_command(&run, 0, g.Command_Pick_Boon{1})
	for _ in 0 ..< g.BOON_TIMEOUT_TICKS {
		if run.simulation.state.depth > 0 do break
		headless.run_step(&run)
	}
	testing.expect_value(t, u32(run.simulation.state.clock.time - since), g.BOON_TIMEOUT_TICKS)
	testing.expect_value(t, sim.slot_data(run.simulation, 1).boons[late.boons[0]], 1)
	picked, _ := headless.run_last_event(&run, g.Event_Boon_Picked)
	testing.expect(t, picked.auto && picked.player == sim.player_in_slot(run.simulation, 1), "the late one's, auto")
	testing.expect_value(t, headless.run_events(&run, g.Event_Boon_Picked), 2)
	scenarios.expect_synced(t, &run)
}

// A joiner arriving at the bottom is waited for, and offered its boons; a leaver isn't waited for.
@(test)
a_joiner_is_waited_for_and_a_leaver_isnt :: proc(t: ^testing.T) {
	run := choosing_run(2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	headless.run_seat(&run, 2, 3)
	headless.run_step(&run)
	headless.run_command(&run, 0, g.Command_Pick_Boon{0})
	headless.run_command(&run, 1, g.Command_Pick_Boon{0})
	play(&run, {}, 0.5)
	testing.expect_value(t, state.depth, 0) // the joiner hasn't picked
	testing.expect_value(t, offer_of(&run, 2).count, g.BOON_OFFER)
	headless.run_seat(&run, 2, 0)
	headless.run_step(&run)
	testing.expect_value(t, state.depth, 1) // gone: nobody left to wait for
	scenarios.expect_synced(t, &run)
}

// Picks sent during a co-op pause count (a command arrives once), and the lift leaves once the game runs again;
// everyone picking on the same tick takes the party down on that tick.
@(test)
picks_count_while_paused_and_together :: proc(t: ^testing.T) {
	run := choosing_run(2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	headless.run_command(&run, 0, g.Command_Set_Paused{true})
	headless.run_command(&run, 0, g.Command_Pick_Boon{0})
	headless.run_command(&run, 1, g.Command_Pick_Boon{0})
	testing.expect_value(t, headless.run_events(&run, g.Event_Boon_Picked), 2)
	testing.expect_value(t, state.depth, 0) // paused: the lift waits
	headless.run_command(&run, 0, g.Command_Set_Paused{false})
	headless.run_step(&run)
	testing.expect_value(t, state.depth, 1)

	together := choosing_run(3)
	defer headless.run_end(&together)
	inputs := headless.run_inputs(&together)
	for slot in 0 ..< 3 do sim.add_command(&inputs, slot, g.Command_Pick_Boon{u8(slot)})
	headless.run_step(&together, &inputs)
	testing.expect_value(t, headless.run_events(&together, g.Event_Boon_Picked), 3)
	testing.expect_value(t, together.simulation.state.depth, 1)
	scenarios.expect_synced(t, &run)
	scenarios.expect_synced(t, &together)
}

// A hero keeps its boons through a leave (and its rejoin after the floor changed), a wipe and the descent; a leaver's
// boons survive the level change that forgets everything else it would have brought back.
@(test)
boons_outlive_a_leave_a_wipe_and_a_floor :: proc(t: ^testing.T) {
	run := choosing_run(2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	headless.run_command(&run, 1, g.Command_Pick_Boon{0})
	kept := sim.slot_data(run.simulation, 1).boons
	headless.run_seat(&run, 1, 0) // slot 1 leaves, its boon picked
	headless.run_step(&run)
	headless.run_command(&run, 0, g.Command_Pick_Boon{0}) // the party descends: the level change forgets the leaver
	testing.expect_value(t, state.depth, 1)
	headless.run_seat(&run, 1, 2) // and it comes back
	headless.run_step(&run)
	testing.expect_value(t, sim.slot_data(run.simulation, 1).boons, kept)
	first := sim.slot_data(run.simulation, 0).boons
	hurt(&run, 0, 999)
	hurt(&run, 1, 999)
	for _ in 0 ..< 2 * g.WIPE_TICKS {
		if headless.run_events(&run, g.Event_Floor_Restarted) > 0 do break
		headless.run_step(&run)
	}
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 1)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).boons, first)
	testing.expect_value(t, sim.slot_data(run.simulation, 1).boons, kept)
	scenarios.expect_synced(t, &run)
}

// What each boon does: Thick_Hide's health, Swift_Boots' speed, Keen_Edge's damage, Quick_Hands' cooldown,
// Strong_Back's load and Field_Medic's revive, each rank on top of the last.
@(test)
each_boon_does_its_part :: proc(t: ^testing.T) {
	hero: g.Hero
	testing.expect_value(t, g.hero_max_hp(&hero), g.HERO_HP)
	hero.boons = {
		.Thick_Hide  = 2,
		.Swift_Boots = 3,
		.Keen_Edge   = 1,
		.Quick_Hands = 2,
		.Strong_Back = 1,
		.Field_Medic = 1,
	}
	testing.expect_value(t, g.hero_max_hp(&hero), g.HERO_HP + 2 * g.THICK_HIDE_HP)
	testing.expect_value(t, g.boots_scale(&hero), 1 + 3 * g.SWIFT_BOOTS)
	testing.expect_value(t, g.hands_cooldown(&hero, 100), 76)
	testing.expect_value(t, g.back_speed(&hero, 0.5), 1 - 0.5 * g.STRONG_BACK)
	testing.expect_value(t, g.revive_rate(&hero), 13)

	run := headless.run_begin(&g.GAME, 1, seated = 1) // Keen_Edge, on a blow: the Knight's 18, two ranks on
	defer headless.run_end(&run)
	clear_minions(&run)
	sim.slot_data(run.simulation, 0).boons[.Keen_Edge] = 2
	place_hero(&run, 0, spawn_of(&run, 0), {1, 0})
	place_minion(&run, spawn_of(&run, 0) + {1.6, 0, 0}, .Rise)
	held := [g.PLAYERS]g.Input {
		0 = {buttons = {.Attack}},
	}
	for _ in 0 ..= g.CLASS_SPECS[.Knight].windup do headless.run_step(&run, held)
	hit, struck := headless.run_last_event(&run, g.Event_Minion_Hit)
	testing.expect(t, struck, "the blow lands")
	testing.expect_value(t, hit.damage, 23) // 18 * 1.3, rounded
	scenarios.expect_synced(t, &run)
}
