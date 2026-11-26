// The playthrough: four bots (bot.odin), a Knight, a Barbarian, a Mage and a Rogue (each slot's scripted Profile asks
// for its class), play Floor 1 for three minutes on a sync-tested run: every class's attack lands and its ability is
// used (the Barbarian's heave thrown), the skeletons die, a thrown prop hits, a downed ally is revived by the others,
// coins are picked up, the bots do their parts of the floor's way out under fire (the vault's gate opened by its
// plates, the barricade broken), and every re-simulation agrees; then, the floor quiet, they take the whole way out.
package test_crypt_crew

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
