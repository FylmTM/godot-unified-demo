// The director's rule tests (director.odin): surges on the clock, their size and their graves, the cap, and where any
// minion may stand. Each on a sync-tested run (headless.Run) that ends synced.
package test_crypt_crew

import "core:testing"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:nav"
import "unified:sim"

import g "../crypt_crew"

// Steps a run until the first surge rose (SURGE_FIRST_S), its seated heroes standing at their spawns.
@(private = "file")
until_the_first_surge :: proc(run: ^headless.Run(g.Game)) {
	for headless.run_events(run, g.Event_Surge) == 0 &&
	    run.simulation.state.clock.time < sim.Game_Time(2 * g.SURGE_FIRST_S * g.TICK_HZ) {
		headless.run_step(run)
	}
}

// A surge rises SURGE_FIRST_S into the floor, SURGE_BASE minions and SURGE_PER_HERO more for each hero present: one
// hero's is smaller than four's.
@(test)
a_surge_grows_with_the_party :: proc(t: ^testing.T) {
	for heroes in ([]int{1, 4}) {
		run := headless.run_begin(&g.GAME, 1, seated = heroes)
		defer headless.run_end(&run)
		until_the_first_surge(&run)
		surge, found := headless.run_last_event(&run, g.Event_Surge)
		testing.expectf(t, found, "no surge with %d heroes", heroes)
		testing.expect_value(t, int(surge.count), g.SURGE_BASE + g.SURGE_PER_HERO * heroes)
		scenarios.expect_synced(t, &run)
	}
}

// A surge rises at graves far enough from every hero (SURGE_NEAR along the floor, less the spread around a grave):
// no risen minion stands nearer to a hero than that.
@(test)
a_surge_rises_out_of_sight :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = g.PLAYERS)
	defer headless.run_end(&run)
	until_the_first_surge(&run)
	world := run.simulation.world
	minions := sim.iterate(&run.simulation.state.minions)
	for minion in sim.next(&minions) {
		if minion.phase != .Rise do continue
		for slot in 0 ..< g.PLAYERS {
			hero_poly, _ := nav.nearest(&world.mesh, sim.slot_data(run.simulation, slot).pos, g.HERO_NAV_REACH)
			cost := nav.field(&world.fields, hero_poly).cost[minion.poly]
			testing.expectf(t, cost >= g.SURGE_NEAR - 2 * g.SURGE_SPREAD, "rose %v m from slot %d", cost, slot)
		}
	}
	scenarios.expect_synced(t, &run)
}

// However many are asked for, no more than MINION_CAP minions are alive at once, surges included; and every minion
// stands on the walkable floor's island, never on a wall's top.
@(test)
the_cap_holds_and_minions_stay_on_the_floor :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	headless.run_command(&run, 0, g.Command_Dev_Spawn_Minions{255})
	world := run.simulation.world
	most := 0
	for _ in 0 ..< 10 * g.TICK_HZ { 	// the first surge's time included
		headless.run_step(&run)
		state := &run.simulation.state
		alive := g.minions_alive(&state.minions)
		most = max(most, alive)
		if alive > g.MINION_CAP {
			testing.expectf(t, false, "%d minions alive", alive)
			break
		}
		minions := sim.iterate(&state.minions)
		for minion in sim.next(&minions) {
			if nav.island_of(&world.mesh, minion.poly) != world.floor_island {
				testing.expectf(t, false, "a minion on another island at %v", minion.pos)
				return
			}
		}
	}
	testing.expect_value(t, most, g.MINION_CAP) // the spawn filled it
	scenarios.expect_synced(t, &run)
}
