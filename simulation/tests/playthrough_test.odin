// The playthrough: four bots (bot.odin), a Knight, a Barbarian, a Mage and a Rogue (each slot's scripted Profile asks
// for its class), play Floor 1 for three minutes on a sync-tested run: every class's attack lands and its ability is
// used (the Barbarian's heave thrown), the skeletons die, a thrown prop hits, a downed ally is revived by the others,
// coins are picked up, the bots do their parts of the floor's way out under fire (the vault's gate opened by its
// plates, the barricade broken), and every re-simulation agrees; then, the floor quiet, they take the whole way out.
package test_crypt_crew

import "core:slice"
import "core:testing"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

// Three minutes of the four bots: kills, each class's hits (every hit of every tick counted) and abilities (a heave
// landed among them), a thrown prop's hit (its kill is chance: PROP_HIT_DAMAGE alone leaves a fresh skeleton standing;
// attacks_test.odin holds the throw's rules), a revive (the bots send no dev revive: every one is an ally's), a coin
// picked up, synced.
@(test)
the_bot_plays_three_minutes :: proc(t: ^testing.T) {
	game := g.GAME
	game.scripted_input, game.scripted_commands = bot_input, bot_commands
	run := headless.run_begin(&game, 3)
	defer headless.run_end(&run)
	bot_world = run.simulation.world
	struck: [g.Class]int // each class's hits on skeletons, by its own attacks
	used: [g.Class]int // each class's abilities
	prop_hit := false
	for _ in 0 ..< 3 * 60 * g.TICK_HZ {
		headless.run_scripted(&run, g.PLAYERS)
		for &raw in sim.events_at(run.simulation, run.simulation.tick) {
			#partial switch event in sim.event_value(&raw, g.Event) {
			case g.Event_Ability:
				used[event.class] += 1
			case g.Event_Minion_Hit:
				if event.source == .Prop do prop_hit = true
				if event.source == .Prop || event.source == .Dev do continue
				if hero := sim.player_data(&run.simulation.state.players, event.player); hero != nil {
					struck[hero.class] += 1
				}
			}
		}
	}
	for slot in 0 ..< g.PLAYERS {
		want := g.Class(slot + 1)
		testing.expect_value(t, sim.slot_data(run.simulation, slot).class, want)
		testing.expectf(t, struck[want] > 0, "the %v never hit", want)
		testing.expectf(t, used[want] > 0, "the %v never used its ability", want)
	}
	testing.expect(t, headless.run_events(&run, g.Event_Heave_Landed) > 0, "no heave was thrown")
	testing.expect(t, headless.run_events(&run, g.Event_Hero_Revived) > 0, "no downed ally was revived")
	testing.expect(t, headless.run_events(&run, g.Event_Loot_Collected) > 0, "no coin was picked up")
	kills := headless.run_events(&run, g.Event_Minion_Died)
	testing.expectf(t, kills >= 40, "only %d kills in three minutes", kills)
	testing.expect(t, prop_hit, "no thrown prop hit a skeleton")
	testing.expect(t, headless.run_events(&run, g.Event_Gate) > 0, "the vault's gate never opened")
	testing.expect(t, headless.run_events(&run, g.Event_Barricade_Broken) > 0, "the barricade still stands")

	scenarios.expect_synced(t, &run)
}

// The bots take Floor 1's whole way out, on a floor with no skeleton to fight (its packs and elites gone, its surges
// held off) and none of the playthrough's dev commands: two stand on the vault's plates and its latched gate opens,
// the Mage's fireball breaks the barricade, the Knight drags the hoard out of the vault, through the spike gallery
// (waiting out the spikes) and onto the lift's deck, everyone walks aboard, the lift goes down, each picks a boon, and
// the party descends; synced.
@(test)
the_bots_take_the_floors_way_out :: proc(t: ^testing.T) {
	game := g.GAME
	game.scripted_input, game.scripted_commands = bot_input, bot_picks
	run := headless.run_begin(&game, 3)
	defer headless.run_end(&run)
	bot_world = run.simulation.world
	state := &run.simulation.state
	for _ in 0 ..< 2 * g.TICK_HZ do headless.run_scripted(&run, g.PLAYERS) // everyone arrives
	state.hoard.hauled = true // as if hauled already: the first grab doesn't bring the haul's surges on
	hold_surges(&run)
	clear_elites(&run)
	for _ in 0 ..< 3 * 60 * g.TICK_HZ {
		headless.run_scripted(&run, g.PLAYERS)
		if headless.run_events(&run, g.Event_Descended) > 0 do break
	}
	testing.expect(t, headless.run_events(&run, g.Event_Gate) > 0, "the vault's gate never opened")
	testing.expect(t, headless.run_events(&run, g.Event_Barricade_Broken) > 0, "the barricade still stands")
	testing.expect(t, headless.run_events(&run, g.Event_Hoard_Grabbed) > 0, "nobody took the hoard")
	testing.expect_value(t, headless.run_events(&run, g.Event_Boon_Picked), g.PLAYERS)
	testing.expect_value(t, headless.run_events(&run, g.Event_Descended), 1)
	testing.expect_value(t, state.depth, 1)
	scenarios.expect_synced(t, &run)
}

// The bots' commands for the quiet way out: only each one's boon pick at the lift's bottom (bot_commands' last rule).
@(private = "file")
bot_picks :: proc(seed: u64, slot: int, tick: u32, state: ^g.State, setup: g.Setup, out: ^sim.Command_Out(g.Command)) {
	if state.lift.phase == .Choosing do bot_commands(seed, slot, tick, state, setup, out)
}

// The bots take each of the run's new floors' way out the same, on a quiet floor (no skeleton, no elite, surges held
// off) with every gate latched open from the start: as the Ossuary's and the Deep Halls' vault gates would be with
// their braziers lit (braziers.odin's rule, milestone 7's step 2, lights none yet), and the Deep Halls' held gate with a
// hero on its plate. The Mage breaks the floor's barricade, the Knight walks into the vault and drags the hoard to the
// lift (the Deep Halls': along the shortcut the barricade closed), everyone boards, each picks, and the party descends;
// synced.
@(test)
the_bots_take_the_run_floors_ways_out :: proc(t: ^testing.T) {
	for id in ([?]g.Level_Id{.Floor_2, .Floor_3}) {
		game := g.GAME
		game.scripted_input, game.scripted_commands = bot_input, bot_picks
		run := headless.run_begin(&game, 3, g.Setup{floor = id})
		defer headless.run_end(&run)
		bot_world = run.simulation.world
		state := &run.simulation.state
		for _ in 0 ..< 2 * g.TICK_HZ do headless.run_scripted(&run, g.PLAYERS) // everyone arrives
		state.hoard.hauled = true // as if hauled already: the first grab doesn't bring the haul's surges on
		gates := sim.iterate(&state.gates)
		for gate in sim.next(&gates) do gate.latched = true
		hold_surges(&run)
		clear_elites(&run)
		for _ in 0 ..< 3 * 60 * g.TICK_HZ {
			headless.run_scripted(&run, g.PLAYERS)
			if headless.run_events(&run, g.Event_Descended) > 0 do break
		}
		testing.expectf(t, headless.run_events(&run, g.Event_Barricade_Broken) > 0, "%v's barricade still stands", id)
		testing.expectf(t, headless.run_events(&run, g.Event_Hoard_Grabbed) > 0, "nobody took %v's hoard", id)
		testing.expectf(t, headless.run_events(&run, g.Event_Descended) == 1, "%v's party never went down", id)
		testing.expect_value(t, headless.run_events(&run, g.Event_Boon_Picked), g.PLAYERS)
		scenarios.expect_synced(t, &run)
	}
}

// The bots play a whole run: from the hub (everyone boards its lift, which begins the run) down Floor 1, the Ossuary and
// the Deep Halls (each floor's way out done by the bots: the plates stood on, the braziers kindled, the barricade
// blasted, the hoard hauled, everyone aboard, a boon each) to the vault, where they fight the King to its fall, lighting
// its braziers through each ward and stepping out of its blows' reach; the run ends won, three floors down. Each crypt
// floor is quieted as the party enters it (no skeleton, no elite, its surges held off, and again after a lighting brings
// them on: the_bot_plays_three_minutes holds the fight), and the Deep Halls' held gate, whose braziers' way runs through
// it, is latched open; the vault is fought as the rules play it, its stages' skeletons and its wards' surges taken as
// they come (the_bots_beat_the_king plays it for each party size). Synced.
@(test)
the_bots_play_a_whole_run :: proc(t: ^testing.T) {
	game := g.GAME
	game.scripted_input, game.scripted_commands = bot_input, bot_picks
	// a shallow re-simulation window: a run this long re-simulating eight ticks a step would be the suite's slowest test
	// by far; every tick is still restored and played again
	run := headless.run_begin(&game, 3, g.Setup{floor = .Hub}, window = 2)
	defer headless.run_end(&run)
	bot_world = run.simulation.world
	state := &run.simulation.state
	visited: [dynamic]g.Level_Id
	defer delete(visited)
	append(&visited, state.level.id)
	for _ in 0 ..< 20 * 60 * g.TICK_HZ {
		headless.run_scripted(&run, g.PLAYERS)
		if headless.run_events(&run, g.Event_Run_Ended) > 0 do break
		if state.level.id == visited[len(visited) - 1] {
			// a lighting brings the surges on (BRAZIER_SURGE_S): a crypt floor stays quiet
			if _, lit := headless.run_last_event(&run, g.Event_Brazier); lit && state.level.id != .Vault do hold_surges(&run)
			continue
		}
		append(&visited, state.level.id)
		if state.level.id == .Vault do continue
		state.hoard.hauled = true // as if hauled already: the first grab doesn't bring the haul's surges on
		if state.level.id == .Floor_3 {
			if held, _, found := sim.item_at(&state.gates, 1); found do held.latched = true
		}
		clear_elites(&run)
		clear_minions(&run)
		hold_surges(&run)
	}
	testing.expectf(
		t,
		slice.equal(visited[:], []g.Level_Id{.Hub, .Floor_1, .Floor_2, .Floor_3, .Vault}),
		"the run went %v",
		visited,
	)
	ended, found := headless.run_last_event(&run, g.Event_Run_Ended)
	testing.expectf(t, found && ended.won, "the run ended won (%v, %v)", found, ended)
	testing.expect_value(t, headless.run_events(&run, g.Event_Boss_Defeated), 1)
	testing.expect_value(t, state.depth, 3)
	scenarios.expect_synced(t, &run)
}

// The vault's fight as the rules play it, for one to four bots on Normal (slot 0 the Knight, then the Barbarian, the
// Mage and the Rogue), each party from a Continue on the vault three floors down with the run's three lives (no boons:
// harder than a run would bring them there): the King wakes, each ward's skeletons and surges rise and the braziers are
// lit through them, the King falls, and the run ends won before its lives are gone. What the vault's numbers are tuned
// to (BOSS_HP, BOSS_HP_PER_HERO, BOSS_SUMMON, BOSS_WARD_NEED, BOSS_SURGE_S, BOSS_SOLO_GUARD_BLOWS): a party of any size
// can win it. Synced.
@(test)
the_bots_beat_the_king :: proc(t: ^testing.T) {
	for players in 1 ..= g.PLAYERS {
		game := g.GAME
		game.scripted_input, game.scripted_commands = bot_input, bot_picks
		setup := g.Setup {
			version    = g.SAVE_VERSION,
			floor      = .Vault,
			lives      = g.DIFFICULTY[.Normal].lives,
			depth      = 3,
			run_number = 1,
		}
		// a shallow re-simulation window, as the whole run's: every tick is still restored and played again
		run := headless.run_begin(&game, 1, setup, window = 2)
		defer headless.run_end(&run)
		bot_world = run.simulation.world
		state := &run.simulation.state
		for _ in 0 ..< 5 * 60 * g.TICK_HZ {
			headless.run_scripted(&run, players)
			if headless.run_events(&run, g.Event_Run_Ended) > 0 do break
		}
		ended, found := headless.run_last_event(&run, g.Event_Run_Ended)
		testing.expectf(t, found && ended.won, "%d bots: the King stands (%v, %v)", players, found, ended)
		testing.expectf(t, state.run.lives > 0, "%d bots: every life went", players)
		testing.expectf(
			t,
			headless.run_events(&run, g.Event_Boss_Stage) >= 2,
			"%d bots: the King never warded",
			players,
		)
		scenarios.expect_synced(t, &run)
	}
}

// Two bots (the Knight and the Barbarian) play a Pit run on Normal from its first wave and live to its first lull (wave
// PIT_FIRST_BOON's): the choice opens before the one life goes. What the Pit's first waves are tuned to (PIT_BASE,
// PIT_EARLY_GROWTH, PIT_SURGE_S, PIT_ELITE_EVERY, PIT_FIRST_BOON): its boon loop is reached by play. Synced.
@(test)
the_bots_reach_the_pits_first_lull :: proc(t: ^testing.T) {
	game := g.GAME
	game.scripted_input, game.scripted_commands = bot_input, bot_picks
	run := headless.run_begin(&game, 1, g.Setup{floor = .Arena, mode = .Pit}, window = 2)
	defer headless.run_end(&run)
	bot_world = run.simulation.world
	for _ in 0 ..< 3 * 60 * g.TICK_HZ {
		headless.run_scripted(&run, 2)
		if headless.run_events(&run, g.Event_Choice) > 0 || headless.run_events(&run, g.Event_Run_Ended) > 0 do break
	}
	testing.expect_value(t, headless.run_events(&run, g.Event_Run_Ended), 0)
	opened, found := headless.run_last_event(&run, g.Event_Choice)
	testing.expect(t, found && opened.open, "the first lull's choice opened")
	testing.expect_value(t, run.simulation.state.floor_surges, u32(g.PIT_FIRST_BOON))
	scenarios.expect_synced(t, &run)
}
