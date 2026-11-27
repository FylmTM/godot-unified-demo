// crypt_crew's end-to-end suite: the standard scenarios of unified:headless/scenarios (unified/src/headless/README.md),
// its replay regressions (the recorded sessions in replays/) and what two of them hold (a LAN session's play, an F3
// note's fact), unified's determinism lint, the extension's install check, the session's byte budget, and that
// docs/testing.md names every test file, replay and check script. The reference run is in reference_test.odin, the
// planted bugs the harness catches in planted_test.odin, the soak in soak_test.odin, the rule tests in a file per system
// (heroes_test.odin).
package test_crypt_crew

import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"
import "unified:dmath"
import "unified:godot"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:lint"
import "unified:netcode"
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

// An F3 note kept as a regression (docs/testing.md, F3 notes): an agent played the Knight to Floor 1's lift with
// `uni drive`, took Swift Boots from the boon cards with the panel's own keys, walked on Floor 2 and saved
// "on Floor 2 my Knight walks faster than on Floor 1" with `uni drive note` (replays/note_swift_boots/note.txt).
// Replayed, the noted fact holds: slot 0 picks Swift Boots itself (no timeout's auto pick), the party descends to
// Floor 2, and the Knight's top walking speed there is Swift_Boots' rank faster than on Floor 1.
@(test)
the_swift_boots_note_holds :: proc(t: ^testing.T) {
	input_log, decoded := sim.log_decode(#load("replays/note_swift_boots/inputs.unil"), g.Game)
	defer sim.log_destroy(&input_log)
	if !testing.expect(t, decoded, "inputs.unil decodes") do return
	simulation, err := sim.from_snapshot(&g.GAME, #load("replays/note_swift_boots/snapshot.unis"), any_build = true)
	if !testing.expectf(t, err == .None, "snapshot.unis loads: %v", err) do return
	defer sim.destroy(simulation)
	picked: Maybe(g.Event_Boon_Picked)
	descended: u32
	top: [g.Level_Id]f32 // the hero's top ground speed squared on each floor
	for k in 0 ..< len(input_log.ticks) {
		inputs := sim.log_inputs(&input_log, k)
		sim.step(simulation, &inputs)
		for &raw in sim.events_at(simulation, simulation.tick) {
			#partial switch event in sim.event_value(&raw, g.Event) {
			case g.Event_Boon_Picked:
				if slot, ok := sim.player_slot(simulation, event.player); ok && slot == 0 do picked = event
			case g.Event_Descended:
				descended = event.depth
			}
		}
		hero := sim.slot_data(simulation, 0)
		if hero == nil || hero.class != .Knight do continue
		level := simulation.state.level.id
		top[level] = dmath.max(top[level], hero.vel.x * hero.vel.x + hero.vel.z * hero.vel.z)
	}
	pick, ok := picked.?
	if !testing.expect(t, ok, "slot 0 picks a boon") do return
	testing.expectf(
		t,
		pick.boon == .Swift_Boots && pick.rank == 1 && !pick.auto,
		"its own pick, Swift Boots: %v",
		pick,
	)
	testing.expectf(t, descended == 1, "the party descends to depth 1: %d", descended)
	testing.expectf(t, simulation.state.level.id == .Floor_2, "it ends on Floor 2: %v", simulation.state.level.id)
	boots := 1 + g.SWIFT_BOOTS
	testing.expectf(
		t,
		top[.Floor_1] > 0 &&
		top[.Floor_2] / top[.Floor_1] > boots * boots * 0.99 &&
		top[.Floor_2] / top[.Floor_1] < boots * boots * 1.01,
		"the Knight walks %v times faster on Floor 2 (top speeds squared %v, %v)",
		boots,
		top[.Floor_1],
		top[.Floor_2],
	)
}

// docs/testing.md maps every layer of the game's testing to its files, and stays complete: each test file here, each
// replay regression (as replays/<name>) and each of game/tools' check scripts is named in it. A tool that makes
// rather than checks (a bake, an authoring tool) is listed in MAKERS instead, so a new script is a choice either way.
@(test)
the_testing_doc_names_every_layer :: proc(t: ^testing.T) {
	DOC :: #load("../../docs/testing.md", string)
	MAKERS :: [?]string{"bake_crowd.gd", "bake_glyphs.gd", "lay_floor.gd", "minion_bake.gd", "render_portraits.gd"}
	unnamed :: proc(t: ^testing.T, dir, suffix, prefix: string, folders: bool, skip: []string = nil) {
		entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
		if !testing.expectf(t, err == nil, "cannot list %s: %v", dir, err) do return
		for entry in entries {
			if (entry.type == .Directory) != folders || !strings.has_suffix(entry.name, suffix) do continue
			if slice.contains(skip, entry.name) do continue
			name := strings.concatenate({prefix, entry.name}, context.temp_allocator)
			testing.expectf(t, strings.contains(DOC, name), "docs/testing.md doesn't name %s (%s)", name, dir)
		}
	}
	makers := MAKERS
	unnamed(t, #directory, ".odin", "", false)
	unnamed(t, #directory + "/replays", "", "replays/", true)
	unnamed(t, #directory + "/../../game/tools", ".gd", "", false, makers[:])
}

// The session's bytes stay in their budget (tuning.odin, Bandwidth): four clients on the bad network, the last joining
// late; the relay's traffic each way per second of play, the joiner's join and the snapshot it restored each under its
// ceiling. The network simulator and the clock are seeded and virtual, so the bytes are the same on every run and
// platform: a deterministic gate on a change that grows the State, the Input, the commands or the netcode's traffic.
@(test)
a_session_stays_in_its_budget :: proc(t: ^testing.T) {
	TICKS :: 600
	LATE_TICK :: 300
	result := headless.session_run(&g.GAME, {
		clients   = CLIENTS,
		profile   = netcode.PROFILES[.Bad],
		ticks     = TICKS,
		seed      = SUITE.seed,
		late_slot = CLIENTS - 1,
		late_tick = LATE_TICK,
	})
	defer headless.session_result_destroy(&result)
	if !testing.expectf(t, result.ok, "the session failed: %d desyncs", result.desyncs) do return
	seconds := f64(TICKS) / g.TICK_HZ
	sent := int(f64(result.relay_net.bytes_sent) / seconds)
	received := int(f64(result.relay_net.bytes_recv) / seconds)
	snapshot := result.clients[CLIENTS - 1].snapshot_bytes
	testing.expectf(
		t,
		sent <= g.BUDGET_RELAY_SENT_PER_S,
		"the relay sends %d B/s, past %d",
		sent,
		g.BUDGET_RELAY_SENT_PER_S,
	)
	testing.expectf(
		t,
		received <= g.BUDGET_RELAY_RECEIVED_PER_S,
		"the relay receives %d B/s, past %d",
		received,
		g.BUDGET_RELAY_RECEIVED_PER_S,
	)
	testing.expectf(
		t,
		result.join_bytes <= g.BUDGET_JOIN_BYTES,
		"the late joiner's join takes %d bytes, past %d",
		result.join_bytes,
		g.BUDGET_JOIN_BYTES,
	)
	testing.expectf(
		t,
		snapshot <= g.BUDGET_SNAPSHOT_BYTES,
		"the snapshot is %d bytes, past %d",
		snapshot,
		g.BUDGET_SNAPSHOT_BYTES,
	)
}
