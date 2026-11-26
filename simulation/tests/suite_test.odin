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

// The LAN recording holds its play (game/tools/coop_lan_pair.gd, which `./uni coop --rerecord lan_pair` records):
// replayed, a Knight host (slot 0) and a Barbarian joiner (slot 1) each grab and throw props, a thrown prop hits a
// skeleton, each one's blows land, the joiner pauses and the host resumes, the Mage's bolt and the Rogue's shot land,
// the host's dev kill and its downing, and the surges rise; so the regression holds the strikes' results, and
// `uni coop --record` keeps no recording that misses a step.
@(test)
the_lan_recording_holds_its_play :: proc(t: ^testing.T) {
	input_log, decoded := sim.log_decode(#load("replays/lan_pair/inputs.unil"), g.Game)
	defer sim.log_destroy(&input_log)
	if !testing.expect(t, decoded, "inputs.unil decodes") do return
	simulation, err := sim.from_snapshot(&g.GAME, #load("replays/lan_pair/snapshot.unis"), any_build = true)
	if !testing.expectf(t, err == .None, "snapshot.unis loads: %v", err) do return
	defer sim.destroy(simulation)
	// What each slot did, by its hero's class at the time: its grabs, throws, hits by source, pauses and resumes.
	Played :: struct {
		classes:         bit_set[g.Class],
		grabs, throws:   int,
		hits:            [g.Hit_Source]int,
		paused, resumed: int,
		downed:          int,
	}
	played: [2]Played
	surges: u32
	for k in 0 ..< len(input_log.ticks) {
		inputs := sim.log_inputs(&input_log, k)
		sim.step(simulation, &inputs)
		for slot in 0 ..< len(played) {
			if hero := sim.slot_data(simulation, slot); hero != nil && hero.class != .Any do played[slot].classes += {hero.class}
		}
		for &raw in sim.events_at(simulation, simulation.tick) {
			#partial switch event in sim.event_value(&raw, g.Event) {
			case g.Event_Prop_Grabbed:
				if slot, ok := lan_slot(simulation, event.player); ok do played[slot].grabs += 1
			case g.Event_Prop_Thrown:
				if slot, ok := lan_slot(simulation, event.player); ok do played[slot].throws += 1
			case g.Event_Minion_Hit:
				if slot, ok := lan_slot(simulation, event.player); ok do played[slot].hits[event.source] += 1
			case g.Event_Paused:
				if slot, ok := lan_slot(simulation, event.player); ok {
					if event.paused do played[slot].paused += 1
					else do played[slot].resumed += 1
				}
			case g.Event_Hero_Downed:
				if slot, ok := lan_slot(simulation, event.player); ok do played[slot].downed += 1
			case g.Event_Surge:
				if event.surge > surges do surges = event.surge
			}
		}
	}
	host, joiner := &played[0], &played[1]
	testing.expectf(t, host.classes == {.Knight, .Mage}, "the host plays the Knight, then the Mage: %v", host.classes)
	testing.expectf(
		t,
		joiner.classes == {.Barbarian, .Rogue},
		"the joiner the Barbarian, then the Rogue: %v",
		joiner.classes,
	)
	for slot in played {
		testing.expectf(t, slot.grabs >= 2 && slot.throws >= 2, "each grabs and throws twice: %v", played)
		testing.expectf(t, slot.hits[.Blow] > 0, "each one's blows land: %v", played)
	}
	testing.expectf(t, host.hits[.Prop] > 0, "the host's thrown prop hits: %v", host.hits)
	testing.expectf(t, host.hits[.Bolt] > 0 && joiner.hits[.Crossbow] > 0, "the bolt and the shot land: %v", played)
	testing.expectf(t, joiner.paused > 0 && host.resumed > 0, "the joiner pauses, the host resumes: %v", played)
	testing.expectf(t, host.hits[.Dev] > 0 && host.downed > 0, "the host's dev kill and its downing: %v", host)
	testing.expectf(t, surges >= 4, "four surges rise: %d", surges)
}

// The slot of the LAN recording's `player` (its two players hold slots 0 and 1); false for anyone else.
@(private = "file")
lan_slot :: proc(simulation: ^sim.Sim(g.Game), player: sim.Player) -> (slot: int, ok: bool) {
	slot, ok = sim.player_slot(simulation, player)
	return slot, ok && slot < 2
}
