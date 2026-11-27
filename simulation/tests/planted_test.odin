// Two bugs planted on purpose, each caught and named by the harness: a worked example of what the sync-test and the
// replay regressions find (unified/src/headless/README.md), and of how a copy of the game's descriptor (sim.Game) runs
// a variant of its rules through them without touching the sim package. Each copy's tick is the game's tick and then
// the bug.
//
// - A desync: state kept outside the block. The copy keeps a package-level counter, which a rollback doesn't restore,
//   and adds it to every hero's warp epoch; the sync-test's first re-simulation of the first tick it touched computes
//   other bytes, and run_synctest names that tick.
// - A rule change: deterministic, so the sync-test can't see it, but the recorded session (replays/lan_pair) no longer
//   reproduces what was blessed. From a late tick the copy counts every felled skeleton twice; regression_run names
//   the first tick that differs and the State's field (State.kills).
//
// The sync-test names the tick only. To name the field of a desync too, record the run and replay it on a good and a
// bad build (the unified-desync skill, The first field).
package test_crypt_crew

import "core:strings"
import "core:testing"
import "unified:headless"
import "unified:sim"

import g "../crypt_crew"

// The planted desync's first tick: past the sync-test's window, so the forward run has ticks to roll back to.
PLANTED_FROM :: 120

// The planted rule's first tick: late in replays/lan_pair (ticks 3 to 4794), after the floor's restart at 2645.
RULE_FROM :: 3000

// The bug: how many times the planted tick ran from PLANTED_FROM on, forward and re-simulated alike. A rollback
// restores the block, never a package variable, so a re-simulated tick reads a count the forward one never saw.
@(private = "file")
planted_runs: u32

// The tick the planted rule first changed something (0: not yet): what the regression must name. Read only by the
// test, never by the rule, so it is no desync of its own (regression_run re-simulates nothing).
@(private = "file")
rule_first: u32

// The game's tick, then from PLANTED_FROM on the desync: every present hero's warp epoch takes the counter.
@(private = "file")
planted_tick :: proc(t: ^g.Tick) {
	g.tick(t)
	if t.number < PLANTED_FROM do return
	planted_runs += 1
	heroes := sim.iterate_present(&t.state.players)
	for hero in sim.next(&heroes) do hero.warp += u8(planted_runs)
}

// The game's tick, then from RULE_FROM on the new rule: each skeleton felled this tick counts twice in the tally.
@(private = "file")
rule_tick :: proc(t: ^g.Tick) {
	before := t.state.kills
	g.tick(t)
	if t.number < RULE_FROM || t.state.kills <= before do return
	t.state.kills += t.state.kills - before
	if rule_first == 0 do rule_first = t.number
}

// A copy of the game with the planted tick is still a game the harness runs (sim.game_violation, what every scenario
// checks first); the sync-test catches it, and names the planted first tick.
@(test)
a_planted_desync_is_caught :: proc(t: ^testing.T) {
	planted := g.GAME
	planted.tick = planted_tick
	if !testing.expectf(t, sim.game_violation(&planted) == "", "the copy breaks a rule: %s", sim.game_violation(&planted)) do return
	planted_runs = 0
	result := headless.run_synctest(&planted, PLANTED_FROM + 60, 8, SUITE.seed, g.PLAYERS)
	testing.expectf(t, result.mismatches > 0, "the planted counter went unseen: %v", result.mismatches)
	testing.expectf(
		t,
		result.first_tick == PLANTED_FROM,
		"the first mismatch is the planted tick %d: tick %d (re-simulated at %d)",
		PLANTED_FROM,
		result.first_tick,
		result.first_at,
	)
}

// The LAN recording replayed with a rule changed late diverges at the first tick the rule changed, and the report names
// the field. Its expectation is never written (no bless).
@(test)
a_planted_rule_change_fails_the_replay :: proc(t: ^testing.T) {
	changed := g.GAME
	changed.tick = rule_tick
	if !testing.expectf(t, sim.game_violation(&changed) == "", "the copy breaks a rule: %s", sim.game_violation(&changed)) do return
	rule_first = 0
	result := headless.regression_run(&changed, #directory + "/replays/lan_pair")
	if !testing.expectf(t, rule_first != 0, "no skeleton fell from tick %d on: the rule changed nothing", RULE_FROM) do return
	testing.expectf(t, result.status == .Diverges, "the replay %v: %s", result.status, result.report)
	testing.expectf(
		t,
		result.diverged_tick == rule_first,
		"it names tick %d, the rule's first change: %d (%s)",
		rule_first,
		result.diverged_tick,
		result.report,
	)
	testing.expectf(t, strings.contains(result.report, "kills "), "the report names State.kills: %s", result.report)
}
