// The playthrough: four bots (bot.odin), a Knight, a Barbarian, a Mage and a Rogue, play Floor 1 for three minutes on
// a sync-tested run: every class's attack lands, the skeletons die, a thrown prop kills, and every re-simulation
// agrees.
package test_crypt_crew

import "core:testing"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

// Three minutes of the four bots: kills, each class's hits, a prop's kill, synced.
@(test)
the_bot_plays_three_minutes :: proc(t: ^testing.T) {
	game := g.GAME
	game.scripted_input, game.scripted_commands = bot_input, bot_commands
	run := headless.run_begin(&game, 3)
	defer headless.run_end(&run)
	bot_world = run.simulation.world
	struck: [g.PLAYERS]bool // by slot: its hero's attacks hit a skeleton
	thrown_kill := false
	for _ in 0 ..< 3 * 60 * g.TICK_HZ {
		headless.run_scripted(&run, g.PLAYERS)
		if hit, found := headless.run_last_event(&run, g.Event_Minion_Hit); found && hit.source != .Prop {
			if slot, present := sim.player_slot(&run.simulation.state.players, hit.player); present do struck[slot] = true
		}
		if died, found := headless.run_last_event(&run, g.Event_Minion_Died); found && died.source == .Prop {
			thrown_kill = true
		}
	}
	kills := headless.run_events(&run, g.Event_Minion_Died)
	testing.expectf(t, kills >= 40, "only %d kills in three minutes", kills)
	for hit, slot in struck do testing.expectf(t, hit, "slot %d's class never hit", slot)
	testing.expect(t, thrown_kill, "no thrown prop killed")
	scenarios.expect_synced(t, &run)
}
