// The director's rule tests (director.odin): surges on the clock, their size and their graves, the cap, and where any
// minion may stand. Each on a sync-tested run (headless.Run) that ends synced.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
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

// A surge rises at graves out of sight of every hero (SURGE_NEAR in a straight line) and within reach of the party
// (SURGE_FAR along the floor from the nearest hero): every risen minion stands so, give or take the spread around its
// grave.
@(test)
a_surge_rises_out_of_sight_and_within_reach :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = g.PLAYERS)
	defer headless.run_end(&run)
	until_the_first_surge(&run)
	floor := floor_of(&run)
	risen := 0
	minions := sim.iterate(&run.simulation.state.minions)
	for minion in sim.next(&minions) {
		if minion.phase != .Rise do continue
		risen += 1
		nearest := nav.UNREACHABLE
		for slot in 0 ..< g.PLAYERS {
			hero := sim.slot_data(run.simulation, slot)
			apart := dmath.length(minion.pos.xz - hero.pos.xz)
			testing.expectf(t, apart >= g.SURGE_NEAR - g.SURGE_SPREAD, "rose %v m from slot %d", apart, slot)
			spot, on_floor := g.floor_spot(floor, hero.pos, g.HERO_NAV_REACH)
			if on_floor do nearest = dmath.min(nearest, nav.field(&floor.fields, spot.poly).cost[minion.poly])
		}
		testing.expectf(t, nearest <= g.SURGE_FAR + 2 * g.SURGE_SPREAD, "rose %v m of path from the party", nearest)
	}
	testing.expect(t, risen > 0, "a surge rose")
	scenarios.expect_synced(t, &run)
}

// With a hero up within SURGE_NEAR of every grave, no grave is out of sight: the surge clock runs out and nothing
// rises.
@(test)
no_grave_out_of_sight_no_surge :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = g.PLAYERS)
	defer headless.run_end(&run)
	clear_minions(&run) // the packs: they would down the heroes beside them
	graves := sim.slice(&floor_of(&run).places.graves)
	covered: [g.MAX_GRAVES]bool
	placed := 0
	for &grave, i in graves {
		if covered[i] do continue
		assert(placed < g.PLAYERS, "the floor's graves need more heroes than slots to cover")
		place_hero(&run, placed, grave.point)
		placed += 1
		for &other, k in graves {
			if dmath.length(other.point.xz - grave.point.xz) < g.SURGE_NEAR - 0.5 do covered[k] = true
		}
	}
	for !sim.timer_running(run.simulation.state.clock.time, run.simulation.state.surge) do headless.run_step(&run)
	for run.simulation.state.clock.time < sim.Game_Time(g.SURGE_FIRST_TICKS + g.TICK_HZ) do headless.run_step(&run)
	testing.expect_value(t, headless.run_events(&run, g.Event_Surge), 0)
	scenarios.expect_synced(t, &run)
}

// However many are asked for, no more than the floor's cap (its CROWD_DENSITY's) are alive at once, surges included;
// and every minion stands on the walkable floor's island, never on a wall's top.
@(test)
the_cap_holds_and_minions_stay_on_the_floor :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	headless.run_command(&run, 0, g.Command_Dev_Spawn_Minions{255})
	floor := floor_of(&run)
	most := 0
	for _ in 0 ..< 10 * g.TICK_HZ { 	// the first surge's time included
		headless.run_step(&run)
		state := &run.simulation.state
		alive := g.minions_alive(&state.minions)
		most = max(most, alive)
		if alive > floor.minion_cap {
			testing.expectf(t, false, "%d minions alive", alive)
			break
		}
		minions := sim.iterate(&state.minions)
		for minion in sim.next(&minions) {
			if nav.island_of(&floor.mesh, minion.poly) != floor.island {
				testing.expectf(t, false, "a minion on another island at %v", minion.pos)
				return
			}
		}
	}
	testing.expect_value(t, most, floor.minion_cap) // the spawn filled it
	scenarios.expect_synced(t, &run)
}
