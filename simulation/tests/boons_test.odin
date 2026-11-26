// The boons' rule tests (boons.odin): the offer a pure keyed roll (the same whenever it is asked, distinct, never a
// boon at its top rank), a pick counting once and only while the lift waits on picks, the timeout's picks, a late
// joiner waited for and a leaver not, picks during a co-op pause, everyone picking on one tick, boons kept through a
// leave, a wipe and a level change, and what each boon does. Each on a sync-tested run (headless.Run) that ends synced.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
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

// A seed whose depth-0 offers to slots 0 and 1 (members 1 and 2) both hold Thick_Hide, and each one's index of it.
@(private = "file")
thick_hide_seed :: proc() -> (seed: u64, index: [2]u8) {
	search: for candidate in u64(1) ..< 400 {
		for slot in 0 ..< 2 {
			player := sim.Player {
				index = u16(slot),
				id    = u16(slot + 1),
			}
			offer := g.boon_offer(candidate, 0, player, {})
			found := false
			for boon, i in offer.boons[:offer.count] {
				if boon == .Thick_Hide do index[slot], found = u8(i), true
			}
			if !found do continue search
		}
		return candidate, index
	}
	panic("no seed offers Thick_Hide to both")
}

// Thick_Hide's pick heals what it adds to a hero up, and nothing to a hero down; a hero's next body has the health its
// boons give it (hero_max_hp, at a wipe's restart).
@(test)
thick_hide_heals_the_up_and_shapes_the_next_body :: proc(t: ^testing.T) {
	seed, index := thick_hide_seed()
	run := headless.run_begin(&g.GAME, seed, seated = 3)
	defer headless.run_end(&run)
	clear_minions(&run)
	clear_elites(&run)
	testing.expect_value(t, sim.player_in_slot(run.simulation, 1), sim.Player{index = 1, id = 2})
	hurt(&run, 0, 30)
	hurt(&run, 1, g.HERO_HP)
	headless.run_command(&run, 0, g.Command_Dev_Board{})
	for _ in 0 ..< 10 * g.TICK_HZ {
		if run.simulation.state.lift.phase == .Choosing do break
		headless.run_step(&run)
	}
	headless.run_command(&run, 0, g.Command_Pick_Boon{index[0]})
	headless.run_command(&run, 1, g.Command_Pick_Boon{index[1]}) // slot 2 hasn't picked: the lift waits
	up, down := sim.slot_data(run.simulation, 0), sim.slot_data(run.simulation, 1)
	testing.expect_value(t, up.boons[.Thick_Hide], 1)
	testing.expect_value(t, up.hp, g.HERO_HP - 30 + g.THICK_HIDE_HP)
	testing.expect_value(t, down.boons[.Thick_Hide], 1)
	testing.expect_value(t, down.hp, 0) // down, it stays down at 0
	headless.run_command(&run, 2, g.Command_Pick_Boon{0}) // the party descends
	testing.expect_value(t, run.simulation.state.depth, 1)
	for slot in 0 ..< 3 do hurt(&run, slot, 999)
	for _ in 0 ..< 2 * g.WIPE_TICKS {
		if headless.run_events(&run, g.Event_Floor_Restarted) > 0 do break
		headless.run_step(&run)
	}
	testing.expect_value(t, up.hp, g.HERO_HP + g.THICK_HIDE_HP) // its next body has its boons' health
	scenarios.expect_synced(t, &run)
}

// A hero that picked, left and came back at the same depth has had its pick: a second one counts for nothing.
@(test)
a_rejoiner_doesnt_pick_twice :: proc(t: ^testing.T) {
	run := choosing_run(2)
	defer headless.run_end(&run)
	headless.run_command(&run, 1, g.Command_Pick_Boon{0})
	kept := sim.slot_data(run.simulation, 1).boons
	headless.run_seat(&run, 1, 0)
	headless.run_step(&run)
	headless.run_seat(&run, 1, 2) // back, the party still choosing
	headless.run_step(&run)
	testing.expect_value(t, run.simulation.state.depth, 0)
	headless.run_command(&run, 1, g.Command_Pick_Boon{1})
	testing.expect_value(t, sim.slot_data(run.simulation, 1).boons, kept)
	testing.expect_value(t, headless.run_events(&run, g.Event_Boon_Picked), 1)
	scenarios.expect_synced(t, &run)
}

// A hero with every boon at its top rank has nothing to pick: the lift doesn't wait for it, and a pick of it counts for
// nothing.
@(test)
a_hero_with_every_boon_maxed_isnt_waited_for :: proc(t: ^testing.T) {
	run := choosing_run(2)
	defer headless.run_end(&run)
	maxed := sim.slot_data(run.simulation, 1)
	for &rank in maxed.boons do rank = g.BOON_RANK_MAX
	headless.run_pin(&run)
	testing.expect_value(t, offer_of(&run, 1).count, 0)
	headless.run_command(&run, 1, g.Command_Pick_Boon{0})
	testing.expect_value(t, headless.run_events(&run, g.Event_Boon_Picked), 0)
	headless.run_command(&run, 0, g.Command_Pick_Boon{0})
	testing.expect_value(t, run.simulation.state.depth, 1)
	scenarios.expect_synced(t, &run)
}

// At the lift's bottom the heroes take no input but the pick: a held stick walks nobody, and Interact beside a downed
// ally starts no revive.
@(test)
choosing_heroes_take_no_input :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	clear_minions(&run)
	clear_elites(&run)
	hurt(&run, 1, g.HERO_HP)
	headless.run_command(&run, 0, g.Command_Dev_Board{})
	for _ in 0 ..< 10 * g.TICK_HZ {
		if run.simulation.state.lift.phase == .Choosing do break
		headless.run_step(&run)
	}
	hero := sim.slot_data(run.simulation, 0)
	downed := sim.slot_data(run.simulation, 1).pos
	place_hero(&run, 0, downed + {-1, 0, 0}, {1, 0}) // beside the downed ally, in revive's range
	from := hero.pos
	held: [g.PLAYERS]g.Input
	held[0] = {
		move_x  = 127,
		buttons = {.Interact},
	}
	for _ in 0 ..< g.TICK_HZ / 2 do headless.run_step(&run, held)
	testing.expectf(t, dmath.length(hero.pos.xz - from.xz) < 0.05, "it walked %v", hero.pos - from)
	testing.expect_value(t, hero.action, g.Action.None)
	testing.expect_value(t, sim.slot_data(run.simulation, 1).revive, 0)
	scenarios.expect_synced(t, &run)
}

// Each boon in play: Keen_Edge on an elite's damage, Swift_Boots on a hero's walk, Quick_Hands on an ability's
// cooldown, Strong_Back on a carried prop's and a haul's slowdown, Field_Medic on a revive.
@(test)
each_boon_works_in_play :: proc(t: ^testing.T) {
	{ 	// Keen_Edge: an elite takes the edged blow
		run := headless.run_begin(&g.GAME, 1, seated = 1)
		defer headless.run_end(&run)
		sim.slot_data(run.simulation, 0).boons[.Keen_Edge] = 2
		headless.run_pin(&run)
		headless.run_command(&run, 0, g.Command_Dev_Hurt_Elites{20})
		hit, _ := headless.run_last_event(&run, g.Event_Elite_Hit)
		testing.expect_value(t, hit.damage, 26)
		scenarios.expect_synced(t, &run)
	}
	{ 	// Swift_Boots and Strong_Back: a hero carrying a crate walks at its speed, the carry's slowdown less
		run := headless.run_begin(&g.GAME, 1, seated = 1)
		defer headless.run_end(&run)
		clear_minions(&run)
		hero := sim.slot_data(run.simulation, 0)
		hero.boons[.Swift_Boots], hero.boons[.Strong_Back] = 3, 1
		place_hero(&run, 0, spawn_of(&run, 0), {1, 0})
		place_prop(&run, CRATE, spawn_of(&run, 0) + {1.5, 0, 0})
		press(&run, 0, .Interact)
		play(&run, {}, 0.7)
		play(&run, [g.PLAYERS]g.Input{0 = {move_x = 127}}, 0.5)
		want :=
			g.CLASS_SPECS[hero.class].max_speed *
			g.back_speed(hero, g.PROP_SPECS[.Crate].carry_speed) *
			g.boots_scale(hero)
		testing.expect(t, hero.held != {}, "it carries the crate")
		testing.expectf(t, abs(hero.vel.x - want) < 0.05, "it walks at %v, not %v", hero.vel.x, want)
		scenarios.expect_synced(t, &run)
	}
	{ 	// Quick_Hands: a Rogue's roll comes back sooner
		run := headless.run_begin(&g.GAME, 1, seated = 1)
		defer headless.run_end(&run)
		clear_minions(&run)
		headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Rogue})
		hero := sim.slot_data(run.simulation, 0)
		hero.boons[.Quick_Hands] = 2
		headless.run_pin(&run)
		press(&run, 0, .Ability)
		testing.expect_value(
			t,
			u32(hero.ability_ready.target - hero.ability_ready.start),
			g.hands_cooldown(hero, g.ROLL_COOLDOWN_TICKS),
		)
		testing.expect(t, g.hands_cooldown(hero, g.ROLL_COOLDOWN_TICKS) < g.ROLL_COOLDOWN_TICKS, "sooner")
		scenarios.expect_synced(t, &run)
	}
	{ 	// Field_Medic: its tending counts a share more
		run := headless.run_begin(&g.GAME, 1, seated = 2)
		defer headless.run_end(&run)
		clear_minions(&run)
		place_hero(&run, 0, spawn_of(&run, 0))
		place_hero(&run, 1, spawn_of(&run, 0) + {1, 0, 0}, {-1, 0})
		hurt(&run, 0, g.HERO_HP)
		sim.slot_data(run.simulation, 1).boons[.Field_Medic] = 1
		headless.run_pin(&run)
		tending := [g.PLAYERS]g.Input {
			1 = {buttons = {.Interact}},
		}
		for _ in 0 ..< 10 do headless.run_step(&run, tending)
		testing.expect_value(
			t,
			sim.slot_data(run.simulation, 0).revive,
			10 * g.revive_rate(sim.slot_data(run.simulation, 1)),
		)
		testing.expect(t, g.revive_rate(sim.slot_data(run.simulation, 1)) > g.REVIVE_UNIT, "a share more")
		scenarios.expect_synced(t, &run)
	}
}
