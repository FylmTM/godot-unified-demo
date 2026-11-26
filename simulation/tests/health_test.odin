// The health and arrival rule tests (health.odin, presence.odin's arrival_spot): going down and staying down, the
// wipe's floor restart after WIPE_S (and a joiner stopping it), and where a joiner appears. Each on a sync-tested run
// (headless.Run) that ends synced, so a restart's bodies leave the physics world's refs clean. Reviving is
// revive_test.odin's.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

// A hero at 0 HP goes down (Action.Down): what it held is dropped, and it stays where it fell, neither sliding on
// nor sinking, and nothing hurts it further. It stays down: no rising on its own, however long (an ally revives it).
@(test)
a_downed_hero_stays_down :: proc(t: ^testing.T) {
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
	spawns := headless.run_events(&run, g.Event_Hero_Spawned) // the session's arrivals
	play(&run, {}, 8)
	testing.expect_value(t, hero.action, g.Action.Down)
	testing.expect_value(t, hero.hp, 0)
	testing.expect_value(t, headless.run_events(&run, g.Event_Hero_Spawned), spawns)
	testing.expect_value(t, headless.run_events(&run, g.Event_Party_Wiped), 0) // slot 0 is up
	scenarios.expect_synced(t, &run)
}

// A hero alone that goes down is the whole party down: the wipe starts at once (Event_Party_Wiped), and WIPE_S later,
// not a tick sooner, the floor starts over with the hero up at its spawn.
@(test)
a_hero_alone_down_wipes_after_the_wait :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	hurt(&run, 0, g.HERO_HP)
	testing.expect_value(t, headless.run_events(&run, g.Event_Party_Wiped), 1)
	for _ in 0 ..< g.WIPE_TICKS - 1 do headless.run_step(&run)
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 0)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).action, g.Action.Down)
	headless.run_step(&run)
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 1)
	hero := sim.slot_data(run.simulation, 0)
	testing.expect_value(t, hero.action, g.Action.None)
	testing.expect_value(t, hero.hp, g.HERO_HP)
	testing.expect_value(t, run.simulation.state.wipe, sim.Timer{})
	scenarios.expect_synced(t, &run)
}

// A joiner arriving while the whole party is down is a hero up: the wipe stops, the floor doesn't start over, and the
// downed stay down for the joiner to revive. The joiner, with nobody up to arrive beside, appears at its slot's spawn.
@(test)
a_joiner_stops_the_wipe :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	hurt(&run, 0, g.HERO_HP)
	play(&run, {}, g.WIPE_S / 2)
	headless.run_seat(&run, 1, 2)
	headless.run_step(&run)
	spawned, _ := headless.run_last_event(&run, g.Event_Hero_Spawned)
	testing.expect(t, !spawned.beside, "nobody up to arrive beside: its spawn")
	play(&run, {}, g.WIPE_S)
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 0)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).action, g.Action.Down)
	testing.expect_value(t, run.simulation.state.wipe, sim.Timer{})
	scenarios.expect_synced(t, &run)
}

// When every hero present is down at once, the floor starts over WIPE_S later: every hero up at its spawn, the props
// back at their markers, only the packs asleep, no bolt or fireball left in flight. The refs stay clean through it, with
// a surge risen, one hero carrying and a throw's ignore live as they go down, and a bolt and a fireball flying at the
// restart.
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
	wipe := headless.run_inputs(&run)
	sim.add_command(&wipe, 0, g.Command_Dev_Hurt{sim.player_in_slot(run.simulation, 0), g.HERO_HP})
	sim.add_command(&wipe, 0, g.Command_Dev_Hurt{sim.player_in_slot(run.simulation, 1), g.HERO_HP})
	headless.run_step(&run, &wipe)
	testing.expect_value(t, headless.run_events(&run, g.Event_Party_Wiped), 1)
	for _ in 0 ..< g.WIPE_TICKS - 1 do headless.run_step(&run)
	state := &run.simulation.state
	bolt, _, flying := sim.spawn(&state.bolts) // a bolt in flight at the restart ...
	bolt^ = {
		pos     = spawn_of(&run, 0) + {0, g.FLIGHT_HEIGHT, 0},
		vel     = {g.BOLT_SPEED, 0, 0},
		cast_at = state.clock.time,
		caster  = sim.player_in_slot(run.simulation, 0),
	}
	fireball, _, lobbed := sim.spawn(&state.fireballs) // ... and a fireball
	fireball^ = {
		from    = spawn_of(&run, 0),
		to      = spawn_of(&run, 0) + {3, 0, 0},
		cast_at = state.clock.time,
		caster  = sim.player_in_slot(run.simulation, 0),
	}
	headless.run_pin(&run)
	testing.expect(t, flying && lobbed, "a bolt and a fireball fly at the restart")
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 0)
	headless.run_step(&run)
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 1)
	floor := floor_of(&run)
	for slot in 0 ..< 2 {
		hero := sim.slot_data(run.simulation, slot)
		testing.expect_value(t, hero.action, g.Action.None)
		testing.expect_value(t, hero.hp, g.HERO_HP)
		testing.expectf(
			t,
			dmath.length(hero.pos - floor.places.hero_spawns[slot]) < 0.05,
			"slot %d at %v",
			slot,
			hero.pos,
		)
	}
	testing.expect_value(t, int(state.props.count), int(floor.places.props.count))
	testing.expect_value(t, int(state.bolts.count), 0)
	testing.expect_value(t, int(state.fireballs.count), 0)
	testing.expect_value(t, headless.run_events(&run, g.Event_Fireball_Burst), 0)
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
	spot, on_floor := g.floor_spot(floor_of(&run), blocked_at, g.ARRIVAL_SNAP)
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
	testing.expect_value(t, sim.slot_data(alone.simulation, 2).pos, floor_of(&alone).places.hero_spawns[2])
	scenarios.expect_synced(t, &alone)
}

// Within a floor a leaver comes back as it left: hurt, its hit points and its ability's cooldown; down, down (beside
// the party, its revive's progress kept), so leaving is no way up.
@(test)
a_leaver_comes_back_as_it_left :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	clear_minions(&run)
	leaver := sim.player_in_slot(run.simulation, 1)
	hero := sim.player_data(&run.simulation.state.players, leaver)
	headless.run_command(&run, 1, g.Command_Dev_Set_Class{.Rogue})
	press(&run, 1, .Ability) // a roll: its cooldown runs
	play(&run, {}, 0.5)
	hurt(&run, 1, 40)
	cooldown := hero.ability_ready
	testing.expect(t, sim.timer_running(run.simulation.state.clock.time, cooldown), "the roll's cooldown runs")
	headless.run_seat(&run, 1, 0)
	headless.run_step(&run)
	headless.run_seat(&run, 1, 2)
	headless.run_step(&run)
	testing.expect_value(t, hero.hp, g.HERO_HP - 40)
	testing.expect_value(t, hero.ability_ready, cooldown)
	testing.expect_value(t, hero.action, g.Action.None)

	place_hero(&run, 0, spawn_of(&run, 0))
	place_hero(&run, 1, spawn_of(&run, 0) + {1.1, 0, 0}, {-1, 0})
	hurt(&run, 1, g.HERO_HP)
	place_hero(&run, 0, spawn_of(&run, 0), {1, 0})
	inputs := [g.PLAYERS]g.Input {
		0 = {buttons = {.Interact}},
	}
	for _ in 0 ..< 30 do headless.run_step(&run, inputs)
	testing.expect_value(t, hero.revive, 30 * g.REVIVE_UNIT)
	headless.run_seat(&run, 1, 0)
	headless.run_step(&run)
	headless.run_seat(&run, 1, 2)
	headless.run_step(&run)
	testing.expect_value(t, hero.action, g.Action.Down)
	testing.expect_value(t, hero.hp, 0)
	testing.expect_value(t, hero.revive, 30 * g.REVIVE_UNIT - g.REVIVE_DECAY) // its arrival tick, untended
	spawned, _ := headless.run_last_event(&run, g.Event_Hero_Spawned)
	testing.expect(t, spawned.beside, "it arrives beside the party, down")
	scenarios.expect_synced(t, &run)
}

// The whole party down, one of them leaving and coming back doesn't stop the wipe: it comes back down, and the floor
// restarts WIPE_S after the last went down. Whoever was away then comes back whole: the floor it left is gone.
@(test)
a_downed_rejoiner_keeps_the_wipe :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 3)
	defer headless.run_end(&run)
	clear_minions(&run)
	away := sim.player_data(&run.simulation.state.players, sim.player_in_slot(run.simulation, 2))
	hurt(&run, 2, g.HERO_HP)
	headless.run_seat(&run, 2, 0) // down, it leaves for the rest of the floor
	headless.run_step(&run)
	hurt(&run, 0, g.HERO_HP)
	hurt(&run, 1, g.HERO_HP) // the wipe begins
	testing.expect_value(t, headless.run_events(&run, g.Event_Party_Wiped), 1)
	headless.run_seat(&run, 1, 0)
	headless.run_step(&run)
	headless.run_seat(&run, 1, 2)
	headless.run_step(&run)
	testing.expect_value(t, sim.slot_data(run.simulation, 1).action, g.Action.Down)
	for _ in 0 ..< g.WIPE_TICKS - 3 do headless.run_step(&run)
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 0)
	headless.run_step(&run) // WIPE_TICKS after the last went down
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 1)
	headless.run_seat(&run, 2, 3)
	headless.run_step(&run)
	testing.expect_value(t, away.action, g.Action.None)
	testing.expect_value(t, away.hp, g.HERO_HP)
	scenarios.expect_synced(t, &run)
}
