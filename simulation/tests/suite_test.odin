// crypt_crew's end-to-end suite: the standard scenarios of unified:headless/scenarios (unified/src/headless/README.md),
// its replay regressions (the recorded sessions in replays/), unified's determinism lint and the extension's install
// check. The reference run is in reference_test.odin, the rule tests in a file per system (heroes_test.odin).
package test_crypt_crew

import "core:testing"
import "unified:godot"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:lint"
import "unified:sim"

import g "../crypt_crew"
import ext "../extension"

// The scenarios' runs: long enough to cross a surge (SURGE_FIRST_S of game time, the script's co-op pauses held out),
// so the sessions' Game.save, which unified checks every client against the offline replay and against each other,
// is made under rollback, late join and churn (the_suite_runs_cross_a_save proves the short run does).
SUITE := scenarios.Suite(g.Game) {
	game    = &g.GAME,
	players = g.PLAYERS,
	seed    = 42,
	ticks   = scenarios.LONG ? 3600 : 600,
}

// The clients of the multi-client sessions: four, or every player of a game with fewer; the last one joins late.
CLIENTS :: min(g.PLAYERS, 4)

// By default the minimal set, each scenario proving something about this game: rollback every tick, players coming
// and going, a bad-network session, a session whose inputs change every tick and a late joiner, on short runs.
// `uni test --long` adds the other standard scenarios and runs them all at full length.
@(test)
rollback_every_tick :: proc(t: ^testing.T) {scenarios.rollback_every_tick(t, &SUITE)}
@(test)
presence_churn :: proc(t: ^testing.T) {scenarios.presence_churn(t, &SUITE)}
@(test)
clients_agree_on_a_bad_network :: proc(t: ^testing.T) {scenarios.session_agrees(t, &SUITE, CLIENTS, .Bad)}
@(test)
clients_agree_when_inputs_change_every_tick :: proc(t: ^testing.T) {scenarios.session_agrees(
		t,
		&SUITE,
		CLIENTS,
		.Wan,
		churn = true,
	)}
when CLIENTS > 1 {
	@(test)
	a_late_joiner_agrees :: proc(t: ^testing.T) {scenarios.late_join_agrees(
			t,
			&SUITE,
			.Wan,
			CLIENTS - 1,
			scenarios.LONG ? 900 : 300,
		)}
}
// Every recorded session in replays/ (one replay folder each) computes what was blessed, tick by tick; after a meant
// rules change, `uni test crypt_crew --bless` (unified/src/headless/README.md, Replay regressions).
@(test)
the_replays_reproduce :: proc(t: ^testing.T) {scenarios.replays_reproduce(t, &g.GAME, #directory + "/replays")}
@(test)
determinism_lint :: proc(t: ^testing.T) {lint.check_game(t, #directory + "/..")}

when scenarios.LONG {
	@(test)
	two_runs_match :: proc(t: ^testing.T) {scenarios.runs_match(t, &SUITE)}
	@(test)
	two_clients_agree_on_an_ideal_network :: proc(t: ^testing.T) {scenarios.session_agrees(t, &SUITE, 2, .Ideal)}
	@(test)
	two_clients_agree_on_a_wan :: proc(t: ^testing.T) {scenarios.session_agrees(t, &SUITE, 2, .Wan)}
	@(test)
	two_clients_agree_on_a_bad_network :: proc(t: ^testing.T) {scenarios.session_agrees(t, &SUITE, 2, .Bad)}
	@(test)
	clients_agree_on_an_ideal_network :: proc(t: ^testing.T) {scenarios.session_agrees(t, &SUITE, CLIENTS, .Ideal)}
	@(test)
	clients_agree_on_a_wan :: proc(t: ^testing.T) {scenarios.session_agrees(t, &SUITE, CLIENTS, .Wan)}
}

// The short scenarios' scripted run makes at least one save (a surge rises in it), so their save checks are not vacuous.
@(test)
the_suite_runs_cross_a_save :: proc(t: ^testing.T) {
	result := headless.run_sim(&g.GAME, u32(SUITE.ticks), SUITE.seed, CLIENTS)
	testing.expectf(t, result.saves >= 1, "the %d-tick run made no save", SUITE.ticks)
}

// The extension installs: what Godot would report when it loads it (a Data_ struct with padding, a bad Glue), here in
// a second.
@(test)
the_extension_installs :: proc(t: ^testing.T) {
	for problem in godot.install_problems(&g.GAME, ext.GLUE) do testing.expect(t, false, problem)
}

// The LAN recording fights for real: replayed, its heroes' own blows, bolts or shots land on skeletons, and a thrown
// prop hits one (not only the dev commands' kills), so the regression holds the strikes' results.
@(test)
the_lan_recording_fights :: proc(t: ^testing.T) {
	input_log, decoded := sim.log_decode(#load("replays/lan_pair/inputs.unil"), g.Game)
	defer sim.log_destroy(&input_log)
	if !testing.expect(t, decoded, "inputs.unil decodes") do return
	simulation, err := sim.from_snapshot(&g.GAME, #load("replays/lan_pair/snapshot.unis"), any_build = true)
	if !testing.expectf(t, err == .None, "snapshot.unis loads: %v", err) do return
	defer sim.destroy(simulation)
	struck: [g.Hit_Source]int
	for k in 0 ..< len(input_log.ticks) {
		inputs := sim.log_inputs(&input_log, k)
		sim.step(simulation, &inputs)
		for &raw in sim.events_at(simulation, simulation.tick) {
			if hit, is := sim.event_value(&raw, g.Event).(g.Event_Minion_Hit); is do struck[hit.source] += 1
		}
	}
	testing.expectf(
		t,
		struck[.Blow] + struck[.Bolt] + struck[.Crossbow] > 0,
		"no hero's own attack landed: %v",
		struck,
	)
	testing.expectf(t, struck[.Prop] > 0, "no thrown prop hit: %v", struck)
}
