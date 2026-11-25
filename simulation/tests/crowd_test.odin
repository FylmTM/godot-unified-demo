// The crowd at scale: a floor's cap from its area, the held crowds of the Setup (director.odin, Crowd) on the arena,
// the director raising only into the table's free rows, and the standard scenarios and a pinned reference run with a
// crowd of hundreds fighting (unified's scenarios on a Setup: CROWD_SUITE, CROWD_REFERENCE), so rollback, late joins
// and every platform's floats are proven at the size the game plays. The rule tests run on sync-tested runs that end
// synced, as every rule test does.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:nav"
import "unified:sim"

import g "../crypt_crew"

// The arena with a fighting crowd: the Setup the scale scenarios and the crowd's reference run play.
CROWD_FIGHT :: g.Setup {
	floor = .Arena,
	crowd = .Fight,
}

// The standard scenarios on the arena's fighting crowd: the floor's cap of minions in a fight, rolled back, re-joined
// and played by four clients. Short by default (each step re-simulates hundreds), full length under --long.
CROWD_SUITE := scenarios.Suite(g.Game) {
	game    = &g.GAME,
	players = g.PLAYERS,
	seed    = 42,
	ticks   = scenarios.LONG ? 1200 : 300,
	setup   = CROWD_FIGHT,
}

// The crowd's reference run (unified/src/headless/README.md, Reference runs): the arena's fighting crowd for 1200
// ticks, snapshotted midway; every platform must reproduce a separation pass over hundreds of neighbours bit for bit.
CROWD_REFERENCE :: scenarios.Reference {
	seed          = 7,
	players       = 4,
	ticks         = 1200,
	snapshot_tick = 600,
	setup         = "floor=arena,crowd=fight",
	checkpoints   = {0xf8c41f20c4509952, 0x56505248e5df0217, 0x1fe6b82c34f27410, 0x70c707c49ebf87f2},
	trace         = 0x39653dbdfaea230d,
	snapshot      = 0x211f370f793cecf3,
	log           = 0x2c2a7501c7b36d09,
	compat        = 0x41202eb1f790a0fb,
}

@(test)
the_crowd_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, CROWD_REFERENCE)}
@(test)
a_crowd_rolls_back_every_tick :: proc(t: ^testing.T) {scenarios.rollback_every_tick(t, &CROWD_SUITE)}
@(test)
a_late_joiner_agrees_with_a_crowd :: proc(t: ^testing.T) {scenarios.late_join_agrees(
		t,
		&CROWD_SUITE,
		.Wan,
		CLIENTS - 1,
		scenarios.LONG ? 600 : 150,
	)}

when scenarios.LONG {
	@(test)
	clients_agree_with_a_crowd_on_a_bad_network :: proc(t: ^testing.T) {scenarios.session_agrees(
			t,
			&CROWD_SUITE,
			CLIENTS,
			.Bad,
		)}
}

// A floor's cap is CROWD_DENSITY to its walkable square metre, at most MINION_CAP: Floor 1's rooms hold about a
// hundred, the arena the most any floor holds.
@(test)
a_floors_cap_comes_from_its_area :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1)
	defer headless.run_end(&run)
	floors := &run.simulation.world.floors
	first := &floors[.Floor_1]
	testing.expect_value(t, first.minion_cap, int(first.area * g.CROWD_DENSITY))
	testing.expectf(t, first.minion_cap > 80 && first.minion_cap < 140, "Floor 1 holds %d", first.minion_cap)
	testing.expectf(
		t,
		floors[.Arena].area * g.CROWD_DENSITY >= g.MINION_CAP,
		"the arena's %v m²",
		floors[.Arena].area,
	)
	testing.expect_value(t, floors[.Arena].minion_cap, g.MINION_CAP)
}

// A held crowd asleep starts at the floor's cap, each minion on the walkable floor, apart from the rest and out of
// sight of the hero spawns; with its heroes standing still nobody wakes.
@(test)
a_sleeping_crowd_stays_asleep :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena, crowd = .Idle}, seated = g.PLAYERS)
	defer headless.run_end(&run)
	floor := floor_of(&run)
	state := &run.simulation.state
	testing.expect_value(t, g.minions_alive(&state.minions), floor.minion_cap)
	expect_spread(t, &run, g.CROWD_IDLE_CLEAR)
	play(&run, {}, 2)
	minions := sim.iterate(&state.minions)
	for minion in sim.next(&minions) {
		if minion.phase != .Idle {
			testing.expectf(t, false, "a sleeper at %v woke", minion.pos)
			break
		}
	}
	scenarios.expect_synced(t, &run)
}

// A held crowd chasing starts at the floor's cap, spread over the floor, every minion chasing; its heroes take no
// damage from it (a wipe would empty the floor), however long they stand in it.
@(test)
a_chasing_crowd_never_downs_its_heroes :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena, crowd = .Chase}, seated = g.PLAYERS)
	defer headless.run_end(&run)
	state := &run.simulation.state
	testing.expect_value(t, g.minions_alive(&state.minions), floor_of(&run).minion_cap)
	expect_spread(t, &run, g.CROWD_CLEAR)
	play(&run, {}, 4)
	testing.expect_value(t, headless.run_events(&run, g.Event_Hero_Hurt), 0)
	for slot in 0 ..< g.PLAYERS do testing.expect_value(t, sim.slot_data(run.simulation, slot).hp, g.HERO_HP)
	scenarios.expect_synced(t, &run)
}

// Every minion of a crowd the arena holds killed at once: the dying keep their rows for DEATH_S, so the table has
// MAX_MINIONS less the cap free. The hold raises at most that many a tick, never once per missing minion (the raises
// a full table would refuse, a nav query each, every tick until the dead are gone), the alive never pass the held
// count, and the crowd stands whole again once the dead are gone and the risen have climbed out.
@(test)
the_director_raises_only_into_free_rows :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena, crowd = .Chase}, seated = g.PLAYERS)
	defer headless.run_end(&run)
	state := &run.simulation.state
	held := int(state.held)
	headless.run_command(&run, 0, g.Command_Dev_Kill_Minions{})
	testing.expect_value(t, g.minions_alive(&state.minions), g.MAX_MINIONS - held) // the free rows, risen that tick
	for _ in 0 ..< g.DEATH_TICKS + g.RISE_TICKS + g.TICK_HZ {
		free_before, rises_before := g.free_rows(&state.minions), state.rises
		headless.run_step(&run)
		raised := int(state.rises - rises_before)
		if raised > free_before || g.minions_alive(&state.minions) > held {
			testing.expectf(
				t,
				false,
				"%d raised into %d free rows, %d alive",
				raised,
				free_before,
				g.minions_alive(&state.minions),
			)
			break
		}
	}
	testing.expect_value(t, g.minions_alive(&state.minions), held)
	scenarios.expect_synced(t, &run)
}

// Every minion of the run on the walkable floor's island, `clear` from every hero_spawn and at least SEPARATION from
// every other, less what two chasers close in a tick (the run's first tick, which seated its heroes, moved them).
@(private = "file")
expect_spread :: proc(t: ^testing.T, run: ^headless.Run(g.Game), clear: f32, loc := #caller_location) {
	floor := floor_of(run)
	minions := sim.iterate(&run.simulation.state.minions)
	for minion, handle in sim.next(&minions) {
		if nav.island_of(&floor.mesh, minion.poly) != floor.island {
			testing.expectf(t, false, "a minion off the floor at %v", minion.pos, loc = loc)
			return
		}
		for spawn in floor.places.hero_spawns {
			if dmath.length(spawn.xz - minion.pos.xz) < clear - g.MINION_SPEED / g.TICK_HZ {
				testing.expectf(
					t,
					false,
					"a minion %v m from a hero_spawn",
					dmath.length(spawn.xz - minion.pos.xz),
					loc = loc,
				)
				return
			}
		}
		others := sim.iterate(&run.simulation.state.minions)
		for other, other_handle in sim.next(&others) {
			if other_handle.index <= handle.index do continue
			if dmath.length(other.pos.xz - minion.pos.xz) < g.SEPARATION - 2 * g.MINION_SPEED / g.TICK_HZ {
				testing.expectf(
					t,
					false,
					"two minions %v m apart",
					dmath.length(other.pos.xz - minion.pos.xz),
					loc = loc,
				)
				return
			}
		}
	}
}
