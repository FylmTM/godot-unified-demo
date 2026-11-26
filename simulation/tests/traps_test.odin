// The traps' rule tests (traps.odin), on the workshop (workshop_test.odin), each on a sync-tested run that ends synced,
// so the spikes' sensor and the roller's kinematic drive roll back with the rest (check_refs after every restore).
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// Where the trap of marker index `index` stands (the spike tile's middle; a roller's marker, its path's first point).
trap_spot :: proc(run: ^headless.Run(g.Game), index: int) -> [3]f32 {
	return sim.slice(&floor_of(run).places.traps)[index].pos
}

// Whether the clock alone has the trap of marker index `index` up now: SPIKES_UP_TICKS at the start of each
// SPIKES_PERIOD_TICKS from its phase.
clock_up :: proc(run: ^headless.Run(g.Game), index: int) -> bool {
	def := sim.slice(&floor_of(run).places.traps)[index]
	return (u32(run.simulation.state.clock.time) + def.phase) % g.SPIKES_PERIOD_TICKS < g.SPIKES_UP_TICKS
}

// Spikes hurt only while up: a hero standing on them for a whole cycle is struck as they rise and SPIKES_HIT_TICKS
// later, SPIKES_DAMAGE each time, every blow on a tick the clock has them up; a hero beside them is never touched.
@(test)
spikes_hurt_only_while_up :: proc(t: ^testing.T) {
	run := workshop(seated = 2)
	defer headless.run_end(&run)
	trap, _ := trap_at(&run, SPIKES)
	centre := trap_spot(&run, SPIKES)
	place_hero(&run, 0, centre)
	place_hero(&run, 1, centre + {g.SPIKES_HALF + g.HERO_RADIUS + 0.3, 0, 0})
	for !clock_up(&run, SPIKES) do headless.run_step(&run) // past the first rise, so the cycle below starts down
	for clock_up(&run, SPIKES) do headless.run_step(&run)
	hp := sim.slot_data(run.simulation, 0).hp
	hits := 0
	for _ in 0 ..< g.SPIKES_PERIOD_TICKS {
		headless.run_step(&run)
		testing.expect_value(t, trap.up, clock_up(&run, SPIKES))
		if hurt, found := headless.run_last_event(&run, g.Event_Hero_Hurt); found {
			testing.expect_value(t, hurt.player, sim.player_in_slot(run.simulation, 0))
			testing.expectf(t, trap.up, "struck at %v while down", run.simulation.state.clock.time)
			hits += 1
		}
	}
	testing.expect_value(t, hits, int((g.SPIKES_UP_TICKS + g.SPIKES_HIT_TICKS - 1) / g.SPIKES_HIT_TICKS))
	testing.expect_value(t, sim.slot_data(run.simulation, 0).hp, hp - i16(hits) * g.SPIKES_DAMAGE)
	testing.expect_value(t, sim.slot_data(run.simulation, 1).hp, g.HERO_HP)
	scenarios.expect_synced(t, &run)
}

// Spikes strike minions too (rows with no body: those over the tile), only while up: a sleeping minion put on them
// while they are down is struck the tick they rise, by the trap, and knocked away from the tile's middle.
@(test)
spikes_strike_minions_while_up :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	centre := trap_spot(&run, SPIKES)
	for clock_up(&run, SPIKES) do headless.run_step(&run)
	minion := place_minion(&run, centre + {0.5, 0, 0.5}, .Idle)
	start := sim.get(&run.simulation.state.minions, minion).pos
	for _ in 0 ..< g.SPIKES_PERIOD_TICKS {
		headless.run_step(&run)
		hit, found := headless.run_last_event(&run, g.Event_Minion_Hit)
		if !found do continue
		testing.expect_value(t, hit.minion, minion)
		testing.expect_value(t, hit.source, g.Hit_Source.Trap)
		testing.expect(t, clock_up(&run, SPIKES), "struck while up")
		break
	}
	testing.expect_value(t, sim.get(&run.simulation.state.minions, minion).hp, g.MINION_HP - g.SPIKES_DAMAGE)
	play(&run, {}, 0.25)
	away := sim.get(&run.simulation.state.minions, minion).pos
	knocked := dmath.length(away.xz - centre.xz) - dmath.length(start.xz - centre.xz)
	testing.expectf(t, knocked > 0.5, "knocked %v m away from the middle", knocked)
	scenarios.expect_synced(t, &run)
}

// Spikes follow the game clock, not the tick count: through a co-op pause (which holds game time while ticks go on)
// they rise and fall exactly as the clock and their phase say, before it and after it.
@(test)
spikes_follow_the_clock_through_a_pause :: proc(t: ^testing.T) {
	run := workshop(seated = 2)
	defer headless.run_end(&run)
	for index in ([]int{SPIKES, PLATED_SPIKES}) {
		headless.run_command(&run, 1, g.Command_Set_Paused{true})
		for _ in 0 ..< 50 do headless.run_step(&run)
		headless.run_command(&run, 1, g.Command_Set_Paused{false})
		trap, _ := trap_at(&run, index)
		for _ in 0 ..< g.SPIKES_PERIOD_TICKS {
			headless.run_step(&run)
			if !testing.expect_value(t, trap.up, clock_up(&run, index)) do break
		}
	}
	scenarios.expect_synced(t, &run)
}

// Spikes with a plate stand up while it is pressed, whatever the clock says, and strike every SPIKES_HIT_TICKS: four
// times in four of those (the hero on them still up after it).
@(test)
a_plate_holds_its_spikes_up :: proc(t: ^testing.T) {
	run := workshop(seated = 2)
	defer headless.run_end(&run)
	trap, _ := trap_at(&run, PLATED_SPIKES)
	drop_prop_on(&run, WORKSHOP_HEAVY_CRATE, plate_spot(&run, SPIKES_PLATE) + {0, g.PLATE_TRAVEL, 0})
	play(&run, {}, 0.5)
	place_hero(&run, 0, trap_spot(&run, PLATED_SPIKES))
	hits := 0
	for _ in 0 ..< 4 * g.SPIKES_HIT_TICKS {
		headless.run_step(&run)
		testing.expect(t, trap.up, "pressed, its spikes stay up")
		if _, found := headless.run_last_event(&run, g.Event_Trap_Hit); found do hits += 1
	}
	testing.expect_value(t, hits, 4)
	scenarios.expect_synced(t, &run)
}

// Spikes rising under a downed hero leave it be: it takes nothing (it is down at 0), and nothing is announced.
@(test)
spikes_rising_under_a_downed_hero_leave_it_be :: proc(t: ^testing.T) {
	run := workshop(seated = 2) // the other hero stays up: no wipe
	defer headless.run_end(&run)
	place_hero(&run, 0, trap_spot(&run, SPIKES))
	hurt(&run, 0, g.HERO_HP)
	hurts := headless.run_events(&run, g.Event_Hero_Hurt)
	for _ in 0 ..< g.SPIKES_PERIOD_TICKS do headless.run_step(&run)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).action, g.Action.Down)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).hp, 0)
	testing.expect_value(t, headless.run_events(&run, g.Event_Hero_Hurt), hurts)
	testing.expect_value(t, headless.run_events(&run, g.Event_Trap_Hit), 0)
	scenarios.expect_synced(t, &run)
}

// The roller's pillar is where its path says at every tick (driven onto it, no drift), and a hero in its way is shoved
// and struck ROLLER_DAMAGE, at most once every ROLLER_HIT_TICKS while it touches.
@(test)
the_roller_follows_its_path_and_strikes_what_it_touches :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	roller, _ := trap_at(&run, ROLLER)
	def := &sim.slice(&floor_of(&run).places.traps)[ROLLER]
	phys := run.simulation.world.phys
	for _ in 0 ..< g.TICK_HZ {
		headless.run_step(&run)
		at, want := physics.body_position(phys, roller.body), g.roller_centre(def, run.simulation.state.clock.time)
		if !testing.expectf(t, dmath.length(at - want) < 1e-3, "the pillar at %v, its path at %v", at, want) do break
	}
	ahead := def.path.points[def.path.count - 1]
	place_hero(&run, 0, ahead)
	last: sim.Game_Time
	hits := 0
	for _ in 0 ..< 6 * g.TICK_HZ {
		step_up(&run)
		if _, found := headless.run_last_event(&run, g.Event_Hero_Hurt); !found do continue
		now := run.simulation.state.clock.time
		testing.expectf(t, hits == 0 || u32(now - last) >= g.ROLLER_HIT_TICKS, "struck again %v ticks on", now - last)
		last, hits = now, hits + 1
	}
	testing.expect(t, hits >= 2, "the roller strikes the hero in its way")
	scenarios.expect_synced(t, &run)
}

// A crossbow shot finds the moving roller where its shooter saw it: aimed just behind the pillar's trailing side, it
// stops at the pillar when the shooter's picture was late (its input's sim.Seen), and flies on past it with none.
@(test)
a_crossbow_hits_the_roller_where_the_shooter_saw_it :: proc(t: ^testing.T) {
	for seen in ([]u8{0, 5}) {
		run := workshop()
		defer headless.run_end(&run)
		headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Rogue})
		def := &sim.slice(&floor_of(&run).places.traps)[ROLLER]
		leg := g.SPIKES_PERIOD_TICKS // the roller's legs take 3 s: the strike lands in a leg's middle, at full speed
		windup := g.CLASS_SPECS[.Rogue].windup
		for (u32(run.simulation.state.clock.time) + windup + 1) % leg != leg / 2 do headless.run_step(&run)
		shoot := [g.PLAYERS]g.Input {
			0 = {buttons = {.Attack}, seen = sim.Seen(seen)},
		}
		for _ in 0 ..< windup do headless.run_step(&run, shoot)
		strike := run.simulation.state.clock.time + 1
		centre := g.roller_centre(def, strike)
		heading: f32 = 1 if centre.z > g.roller_centre(def, strike - 1).z else -1
		behind := centre.z - heading * (g.ROLLER_HALF.z + 0.1)
		place_hero(&run, 0, {centre.x - 4, 0, behind}, {1, 0})
		headless.run_step(&run, shoot)
		shot, found := headless.run_last_event(&run, g.Event_Crossbow_Shot)
		testing.expect(t, found, "the Rogue shoots")
		face := centre.x - g.ROLLER_HALF.x
		if seen > 0 {
			testing.expectf(
				t,
				abs(shot.to.x - face) < 0.05,
				"seen %d: the shot stops at the pillar, at %v",
				seen,
				shot.to,
			)
		} else {
			testing.expectf(
				t,
				shot.to.x > face + 1,
				"seen %d: the shot flies on past the pillar, to %v",
				seen,
				shot.to,
			)
		}
		scenarios.expect_synced(t, &run)
	}
}
