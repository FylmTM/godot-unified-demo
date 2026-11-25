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
	for run.simulation.state.rising > 0 do headless.run_step(&run) // it rises a few a tick
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

// A surge is a quota that rises over the next ticks, as the risers watch holds it (each grave's risers RISE_GAP_TICKS
// apart, each riser clear of every live minion): all of it in the end; and the next surge is SURGE_GROWTH larger.
@(test)
a_surge_rises_a_few_a_tick :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = g.PLAYERS)
	defer headless.run_end(&run)
	clear_minions(&run) // the packs: only the surge's below
	state := &run.simulation.state
	watch: Rise_Watch
	counts: [2]int
	for &count in counts {
		surges := state.surges
		risen := 0
		for state.surges == surges || state.rising > 0 {
			headless.run_step(&run)
			if state.surges != surges && count == 0 {
				surge, _ := headless.run_last_event(&run, g.Event_Surge) // the surge's own tick
				count = int(surge.count)
			}
			risen += watch_rises(t, &run, &watch)
		}
		testing.expect_value(t, risen, count)
	}
	testing.expect_value(t, counts[1], counts[0] + g.SURGE_GROWTH)
	scenarios.expect_synced(t, &run)
}

// A wipe while a surge still owes risers: the restarted floor owes nothing, nothing rises before its first surge, and
// that surge counts no growth (the floor's surges begin again: no death spiral after a wipe).
@(test)
a_wipe_forgets_what_a_surge_owed :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = g.PLAYERS)
	defer headless.run_end(&run)
	state := &run.simulation.state
	state.floor_surges = 20 // a long floor: a large surge, still rising when the wipe comes
	headless.run_pin(&run)
	until_the_first_surge(&run)
	testing.expect(t, state.rising > 0, "the surge still owes")
	for slot in 0 ..< g.PLAYERS do hurt(&run, slot, g.HERO_HP)
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 1)
	testing.expect_value(t, state.rising, 0)
	testing.expect_value(t, state.floor_surges, 0)
	surges := headless.run_events(&run, g.Event_Surge)
	for headless.run_events(&run, g.Event_Surge) == surges {
		headless.run_step(&run)
		if headless.run_events(&run, g.Event_Surge) > surges do break
		minions := sim.iterate(&state.minions)
		for minion in sim.next(&minions) {
			if minion.phase == .Rise {
				testing.expectf(
					t,
					false,
					"a minion rose %d ticks into the restarted floor",
					run.simulation.tick - state.level.since,
				)
				return
			}
		}
	}
	surge, _ := headless.run_last_event(&run, g.Event_Surge)
	testing.expect_value(t, int(surge.count), g.SURGE_BASE + g.SURGE_PER_HERO * g.PLAYERS)
	scenarios.expect_synced(t, &run)
}

// Slot 0 raises minions (dev) until `alive` stand.
@(private = "file")
raise_to :: proc(run: ^headless.Run(g.Game), alive: int) {
	state := &run.simulation.state
	for g.minions_alive(&state.minions) < alive {
		count := dmath.min(alive - g.minions_alive(&state.minions), 255)
		headless.run_command(run, 0, g.Command_Dev_Spawn_Minions{u8(count)})
	}
}

// A surge owes no more than the floor's cap has room for, less what the last one still owes: with three owed and five
// places under the cap, it owes two.
@(test)
a_surge_counts_what_is_still_owed :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = g.PLAYERS)
	defer headless.run_end(&run)
	state := &run.simulation.state
	cap := floor_of(&run).minion_cap
	raise_to(&run, cap - 5)
	testing.expect_value(t, g.minions_alive(&state.minions), cap - 5)
	state.rising = 3
	state.surge = {} // the clock runs out at once
	headless.run_pin(&run)
	for headless.run_events(&run, g.Event_Surge) == 0 do headless.run_step(&run)
	surge, _ := headless.run_last_event(&run, g.Event_Surge)
	testing.expect_value(t, int(surge.count), 2)
	scenarios.expect_synced(t, &run)
}

// What a surge owes rises only while the floor's cap has room: two under the cap with twenty owed, two rise and the
// rest wait, however many turns the graves take.
@(test)
the_owed_wait_for_room_under_the_cap :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = g.PLAYERS)
	defer headless.run_end(&run)
	state := &run.simulation.state
	cap := floor_of(&run).minion_cap
	raise_to(&run, cap - 2)
	state.rising = 20
	headless.run_pin(&run)
	for _ in 0 ..< 2 * g.TICK_HZ {
		headless.run_step(&run)
		if alive := g.minions_alive(&state.minions); alive > cap {
			testing.expectf(t, false, "%d alive under a cap of %d", alive, cap)
			break
		}
	}
	testing.expect_value(t, state.rising, 18)
	scenarios.expect_synced(t, &run)
}

// A co-op pause in the middle of a surge's rising moves no outcome: the same risers rise in the same places, the
// pause only delaying them.
@(test)
a_pause_moves_no_riser :: proc(t: ^testing.T) {
	places: [2][dynamic][3]f32
	defer for &list in places do delete(list)
	for paused in 0 ..< 2 {
		run := headless.run_begin(&g.GAME, 1, seated = g.PLAYERS)
		defer headless.run_end(&run)
		clear_minions(&run)
		state := &run.simulation.state
		state.floor_surges = 10 // a surge long enough to pause in
		headless.run_pin(&run)
		until_the_first_surge(&run)
		halted := false
		for state.rising > 0 {
			if paused == 1 && !halted && state.rising < 15 {
				halted = true
				headless.run_command(&run, 0, g.Command_Set_Paused{true})
				for _ in 0 ..< 13 do headless.run_step(&run)
				headless.run_command(&run, 0, g.Command_Set_Paused{false})
			}
			headless.run_step(&run)
			minions := sim.iterate(&state.minions)
			for minion in sim.next(&minions) {
				if minion.phase == .Rise && minion.since == state.clock.time do append(&places[paused], minion.pos)
			}
		}
	}
	testing.expect_value(t, len(places[1]), len(places[0]))
	for place, i in places[0] {
		if i < len(places[1]) && places[1][i] != place {
			testing.expectf(t, false, "riser %d rose at %v, paused at %v", i, place, places[1][i])
			break
		}
	}
}
