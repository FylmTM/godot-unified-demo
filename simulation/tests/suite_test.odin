// crypt_crew's end-to-end suite: the standard scenarios of unified:headless/scenarios (unified/src/headless/README.md),
// its replay regressions (the recorded sessions in replays/), unified's determinism lint and the extension's install
// check. The reference run is in reference_test.odin, the rule tests in a file per system (heroes_test.odin).
package test_crypt_crew

import "core:testing"
import "unified:godot"
import "unified:headless/scenarios"
import "unified:lint"

import g "../crypt_crew"
import ext "../extension"

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

// The extension installs: what Godot would report when it loads it (a Data_ struct with padding, a bad Glue), here in
// a second.
@(test)
the_extension_installs :: proc(t: ^testing.T) {
	for problem in godot.install_problems(&g.GAME, ext.GLUE) do testing.expect(t, false, problem)
}
