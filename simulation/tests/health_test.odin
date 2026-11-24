// The health and arrival rule tests (health.odin, presence.odin's arrival_spot): going down, rising beside the party
// in grace, the wipe's floor restart, and where a joiner appears. Each on a sync-tested run (headless.Run) that ends
// synced, so a restart's bodies leave the physics world's refs clean.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

// A hero at 0 HP goes down (Action.Down): what it held is dropped, and it stays where it fell, neither sliding on
// nor sinking; RESPAWN_S later it rises beside the party at full health, and in its grace nothing hurts it.
@(test)
a_downed_hero_rises_beside_the_party :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 1)
	place_hero(&run, 1, spawn_of(&run, 1), {1, 0})
	place_prop(&run, CRATE, spawn_of(&run, 1) + {1.5, 0, 0})
	press(&run, 1, .Interact)
	crate, crate_handle := prop_at(&run, CRATE)
	testing.expect_value(t, hero.held, crate_handle)
	hurt(&run, 1, 40)
	testing.expect_value(t, hero.hp, g.HERO_HP - 40)
	carry := [g.PLAYERS]g.Input {
		1 = {move_x = 127},
	}
	play(&run, carry, 0.5) // running when it falls
	hurt(&run, 1, 100)
	testing.expect_value(t, hero.hp, 0)
	testing.expect_value(t, hero.action, g.Action.Down)
	testing.expect_value(t, hero.held, sim.Handle(g.Prop){})
	testing.expect_value(t, crate.held_by, sim.Player{})
	testing.expect_value(t, headless.run_events(&run, g.Event_Hero_Downed), 1)
	fell_at := hero.pos
	play(&run, carry, 1) // its stick does nothing now
	testing.expectf(t, dmath.length(hero.pos - fell_at) < 0.1, "a downed hero moved: %v from %v", hero.pos, fell_at)
	hurt(&run, 1, 10) // down: nothing more
	testing.expect_value(t, headless.run_events(&run, g.Event_Hero_Hurt), 2) // so far: the two before
	for hero.action == .Down && run.simulation.state.clock.time < sim.Game_Time(2 * g.RESPAWN_TICKS) {
		headless.run_step(&run)
	}
	testing.expect_value(t, hero.action, g.Action.None)
	testing.expect_value(t, hero.hp, g.HERO_HP)
	spawned, _ := headless.run_last_event(&run, g.Event_Hero_Spawned)
	testing.expect(t, spawned.beside, "it rose beside the party")
	anchor := sim.slot_data(run.simulation, 0).pos
	testing.expectf(
		t,
		dmath.length(hero.pos.xz - anchor.xz) < g.ARRIVAL_RING + g.ARRIVAL_SNAP,
		"rose %v from %v",
		hero.pos,
		anchor,
	)
	hurt(&run, 1, 50) // in its grace
	testing.expect_value(t, hero.hp, g.HERO_HP)
	for _ in 0 ..< g.SPAWN_GRACE_TICKS do headless.run_step(&run)
	hurt(&run, 1, 50)
	testing.expect_value(t, hero.hp, g.HERO_HP - 50)
	scenarios.expect_synced(t, &run)
}

// When every hero present is down at once, the floor starts over: every hero up at its spawn, the props back at their
// markers, only the packs asleep, no bolt left in flight. The refs stay clean through it, with a surge risen, one hero
// carrying, a throw's ignore live and a bolt flying at the wipe.
@(test)
a_wipe_restarts_the_floor :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	clear_minions(&run) // the packs: the heroes wait for the surge undisturbed
	for headless.run_events(&run, g.Event_Surge) == 0 do headless.run_step(&run)
	place_hero(&run, 0, spawn_of(&run, 0), {1, 0})
	place_prop(&run, CRATE, spawn_of(&run, 0) + {1.5, 0, 0})
	place_hero(&run, 1, spawn_of(&run, 1), {1, 0})
	place_prop(&run, BARREL, spawn_of(&run, 1) + {1.4, 0, 0})
	both := [g.PLAYERS]g.Input {
		0 = {buttons = {.Interact}},
		1 = {buttons = {.Interact}},
	}
	headless.run_step(&run, both)
	play(&run, {}, 0.75)
	press(&run, 1, .Attack)
	for _ in 0 ..< g.THROW_WINDUP_TICKS do headless.run_step(&run)
	barrel, _ := prop_at(&run, BARREL)
	testing.expect(t, sim.slot_data(run.simulation, 0).held != {}, "slot 0 carries at the wipe")
	testing.expect(t, barrel.thrower_ignore != {}, "slot 1's throw ignores it at the wipe")
	bolt, _, flying := sim.spawn(&run.simulation.state.bolts) // a bolt in flight at the wipe
	bolt^ = {
		pos     = spawn_of(&run, 0) + {0, g.FLIGHT_HEIGHT, 0},
		vel     = {g.BOLT_SPEED, 0, 0},
		cast_at = run.simulation.state.clock.time,
		caster  = sim.player_in_slot(run.simulation, 0),
	}
	headless.run_pin(&run)
	testing.expect(t, flying, "a bolt flies at the wipe")
	wipe := headless.run_inputs(&run)
	sim.add_command(&wipe, 0, g.Command_Dev_Hurt{sim.player_in_slot(run.simulation, 0), g.HERO_HP})
	sim.add_command(&wipe, 0, g.Command_Dev_Hurt{sim.player_in_slot(run.simulation, 1), g.HERO_HP})
	headless.run_step(&run, &wipe)
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 1)
	state := &run.simulation.state
	world := run.simulation.world
	for slot in 0 ..< 2 {
		hero := sim.slot_data(run.simulation, slot)
		testing.expect_value(t, hero.action, g.Action.None)
		testing.expect_value(t, hero.hp, g.HERO_HP)
		testing.expectf(
			t,
			dmath.length(hero.pos - world.places.hero_spawns[slot]) < 0.05,
			"slot %d at %v",
			slot,
			hero.pos,
		)
	}
	testing.expect_value(t, int(state.props.count), int(world.places.props.count))
	testing.expect_value(t, int(state.bolts.count), 0)
	minions := sim.iterate(&state.minions)
	for minion in sim.next(&minions) do testing.expect_value(t, minion.phase, g.Minion_Phase.Idle)
	for _ in 0 ..< g.TICK_HZ do headless.run_step(&run)
	scenarios.expect_synced(t, &run)
}

// A joiner mid-floor arrives beside the party: on the ring around the lowest-slot hero up, clear of minions (a ring
// spot with a minion on it is passed over). A joiner with nobody up arrives at its slot's spawn.
@(test)
a_joiner_arrives_beside_the_party :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	for _ in 0 ..< g.TICK_HZ / 2 do headless.run_step(&run)
	anchor := sim.slot_data(run.simulation, 0).pos
	first := dmath.DIR8[(1 * g.ARRIVAL_SLOT_TURN) % len(dmath.DIR8)] // slot 1's first spot (arrival_spot)
	blocked_at := anchor + [3]f32{first.x, 0, first.y} * g.ARRIVAL_RING
	spot, on_floor := g.floor_spot(run.simulation.world, blocked_at, g.ARRIVAL_SNAP)
	testing.expect(t, on_floor, "slot 1's first spot is on the floor")
	state := &run.simulation.state
	g.spawn_minion(state, spot.point, spot.poly, {0, 1}, .Idle, state.clock.time)
	headless.run_pin(&run)
	headless.run_seat(&run, 1, 2)
	headless.run_step(&run)
	joiner := sim.slot_data(run.simulation, 1)
	spawned, _ := headless.run_last_event(&run, g.Event_Hero_Spawned)
	testing.expect(t, spawned.beside, "it arrived beside the party")
	beside := dmath.length(joiner.pos.xz - anchor.xz)
	testing.expectf(t, abs(beside - g.ARRIVAL_RING) < g.ARRIVAL_SNAP, "arrived %v m from the party", beside)
	testing.expectf(
		t,
		dmath.length(joiner.pos.xz - spot.point.xz) >= g.ARRIVAL_CLEAR,
		"arrived on the minion: %v",
		joiner.pos,
	)
	scenarios.expect_synced(t, &run)

	alone := headless.run_begin(&g.GAME, 1)
	defer headless.run_end(&alone)
	headless.run_seat(&alone, 2, 1)
	headless.run_step(&alone)
	first_arrival, _ := headless.run_last_event(&alone, g.Event_Hero_Spawned)
	testing.expect(t, !first_arrival.beside, "nobody up: its slot's spawn")
	testing.expect_value(t, sim.slot_data(alone.simulation, 2).pos, alone.simulation.world.places.hero_spawns[2])
	scenarios.expect_synced(t, &alone)
}
