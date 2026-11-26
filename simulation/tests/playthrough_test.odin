// The playthrough: four bots (bot.odin), a Knight, a Barbarian, a Mage and a Rogue (each slot's scripted Profile asks
// for its class), play Floor 1 for three minutes on a sync-tested run: every class's attack lands and its ability is
// used (the Barbarian's heave thrown), the skeletons die, a thrown prop hits, a downed ally is revived by the others,
// coins are picked up, and every re-simulation agrees.
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
	scenarios.expect_synced(t, &run)
}
