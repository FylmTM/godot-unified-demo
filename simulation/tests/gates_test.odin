// The gates' rule tests (gates.odin), on the workshop (workshop_test.odin), each on a sync-tested run that ends synced,
// so a grille's joint and motor roll back with the rest (check_refs after every restore). Its vault gate needs both its
// plates and latches; its store gate opens while its one plate is pressed. Plates are pressed with props dropped on
// them, which stay put, where a hero would wander.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// How long a gate takes to lift all the way or come all the way down (GATE_RISE at GATE_SPEED: 1.3 s), with a margin.
GATE_TRAVEL_S :: 2

// The vault gate stays shut with one of its two plates pressed, opens with both (lifted GATE_RISE), and once open
// stays open with both released: it latches.
@(test)
a_gate_needs_its_plates_and_a_latch_holds :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	gate, _ := gate_at(&run, VAULT_GATE)
	drop_prop_on(&run, WORKSHOP_CRATE, plate_spot(&run, VAULT_WEST) + {0, g.PLATE_TRAVEL, 0})
	play(&run, {}, GATE_TRAVEL_S)
	testing.expect(t, !gate.open, "one plate of two opens nothing")
	testing.expectf(
		t,
		lift_of(&run, VAULT_GATE) < 0.01,
		"the grille stays down: lifted %v m",
		lift_of(&run, VAULT_GATE),
	)
	drop_prop_on(&run, WORKSHOP_BARREL, plate_spot(&run, VAULT_EAST) + {0, g.PLATE_TRAVEL, 0})
	play(&run, {}, GATE_TRAVEL_S)
	testing.expect(t, gate.open && gate.latched, "both open it, and it latches")
	testing.expectf(t, abs(lift_of(&run, VAULT_GATE) - g.GATE_RISE) < 0.02, "lifted %v m", lift_of(&run, VAULT_GATE))
	testing.expect_value(t, headless.run_events(&run, g.Event_Gate), 1)

	place_prop(&run, WORKSHOP_CRATE, plate_spot(&run, VAULT_WEST) + {0, 0, 3})
	place_prop(&run, WORKSHOP_BARREL, plate_spot(&run, VAULT_EAST) + {0, 0, 3})
	play(&run, {}, GATE_TRAVEL_S)
	first, _ := plate_at(&run, VAULT_WEST)
	second, _ := plate_at(&run, VAULT_EAST)
	testing.expect(t, !first.pressed && !second.pressed, "both plates are released")
	testing.expect(t, gate.open, "the latch holds it open")
	testing.expectf(
		t,
		abs(lift_of(&run, VAULT_GATE) - g.GATE_RISE) < 0.02,
		"still lifted %v m",
		lift_of(&run, VAULT_GATE),
	)
	testing.expect_value(t, headless.run_events(&run, g.Event_Gate), 1)
	scenarios.expect_synced(t, &run)
}

// The store gate opens while its plate is pressed and comes back down once it is released: no latch.
@(test)
a_gate_without_a_latch_closes_when_its_plate_is_released :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	gate, _ := gate_at(&run, STORE_GATE)
	drop_prop_on(&run, WORKSHOP_CRATE, plate_spot(&run, STORE_PLATE) + {0, g.PLATE_TRAVEL, 0})
	play(&run, {}, GATE_TRAVEL_S)
	testing.expect(t, gate.open, "its plate opens it")
	testing.expectf(t, lift_of(&run, STORE_GATE) > g.GATE_RISE - 0.02, "lifted %v m", lift_of(&run, STORE_GATE))
	place_prop(&run, WORKSHOP_CRATE, plate_spot(&run, STORE_PLATE) + {0, 0, 3})
	play(&run, {}, GATE_TRAVEL_S)
	testing.expect(t, !gate.open && !gate.latched, "released, it closes")
	testing.expectf(t, lift_of(&run, STORE_GATE) < 0.02, "down again: lifted %v m", lift_of(&run, STORE_GATE))
	testing.expect_value(t, headless.run_events(&run, g.Event_Gate), 2)
	scenarios.expect_synced(t, &run)
}

// A crate left under a closing gate wedges it: the grille comes down onto the crate and stops there, pressing it with
// at most GATE_CLOSE_FORCE, and the crate stays whole where it stands.
@(test)
a_crate_wedges_a_gate :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	drop_prop_on(&run, WORKSHOP_HEAVY_CRATE, plate_spot(&run, STORE_PLATE) + {0, g.PLATE_TRAVEL, 0})
	play(&run, {}, GATE_TRAVEL_S)
	under := gate_spot(&run, STORE_GATE)
	place_prop(&run, WORKSHOP_CRATE, under)
	place_prop(&run, WORKSHOP_HEAVY_CRATE, plate_spot(&run, STORE_PLATE) + {0, 0, 3})
	play(&run, {}, GATE_TRAVEL_S)
	crate, _ := prop_at(&run, WORKSHOP_CRATE)
	gate, _ := gate_at(&run, STORE_GATE)
	testing.expect(t, !gate.open, "the gate is told to close")
	top := 2 * g.PROP_SPECS[.Crate].half.y
	testing.expectf(
		t,
		abs(lift_of(&run, STORE_GATE) - top) < 0.05,
		"it rests on the crate: lifted %v m",
		lift_of(&run, STORE_GATE),
	)
	centre := physics.body_position(run.simulation.world.phys, crate.body)
	testing.expectf(
		t,
		dmath.length(centre - (under + {0, top / 2, 0})) < 0.1,
		"the crate stands where it was: %v",
		centre,
	)
	scenarios.expect_synced(t, &run)
}

// A gate closing on a hero presses on it with GATE_CLOSE_FORCE, which the hero's pogo spring bears (its feet stay within
// a few centimetres of where they stood: a much harder press would squash it to the floor), and never hurts it; the
// hero walks out from under it, and the gate comes down behind it.
@(test)
a_gate_closing_on_a_hero_never_crushes_it :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	drop_prop_on(&run, WORKSHOP_CRATE, plate_spot(&run, STORE_PLATE) + {0, g.PLATE_TRAVEL, 0})
	play(&run, {}, GATE_TRAVEL_S)
	under := gate_spot(&run, STORE_GATE)
	place_hero(&run, 0, under, {0, 1})
	play(&run, {}, 0.5)
	hero := sim.slot_data(run.simulation, 0)
	standing := hero.pos.y
	place_prop(&run, WORKSHOP_CRATE, plate_spot(&run, STORE_PLATE) + {0, 0, 3})
	play(&run, {}, GATE_TRAVEL_S)
	testing.expect_value(t, hero.hp, g.HERO_HP)
	testing.expectf(
		t,
		abs(hero.pos.y - standing) < 0.03,
		"pressed, the hero stands: feet at %v from %v",
		hero.pos.y,
		standing,
	)
	testing.expectf(
		t,
		lift_of(&run, STORE_GATE) > 1.5,
		"the grille rests on the hero: lifted %v m",
		lift_of(&run, STORE_GATE),
	)
	play(&run, {0 = {move_z = 127}}, 1)
	play(&run, {}, GATE_TRAVEL_S)
	testing.expectf(t, hero.pos.z > under.z + 1, "the hero walked out: %v", hero.pos)
	testing.expectf(
		t,
		lift_of(&run, STORE_GATE) < 0.02,
		"the gate came down behind it: lifted %v m",
		lift_of(&run, STORE_GATE),
	)
	scenarios.expect_synced(t, &run)
}

// A shut gate holds a minion back (its obstacles), and once lifted past GATE_PASS lets it through: a minion in the
// store room behind the gate chases the hero in the hall and stays behind the grille until the gate opens.
@(test)
a_shut_gate_holds_minions_back_until_it_opens :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	under := gate_spot(&run, STORE_GATE)
	place_hero(&run, 0, under + {0, 0, 3})
	minion := place_minion(&run, under + {0, 0, -1.5}, .Chase)
	for _ in 0 ..< int(2 * g.TICK_HZ) {
		step_up(&run)
		pos := sim.get(&run.simulation.state.minions, minion).pos
		if !testing.expectf(t, pos.z < under.z - g.MINION_RADIUS, "the shut gate holds it back: %v", pos) do break
	}
	drop_prop_on(&run, WORKSHOP_CRATE, plate_spot(&run, STORE_PLATE) + {0, g.PLATE_TRAVEL, 0})
	passed := false
	for _ in 0 ..< int(2 * GATE_TRAVEL_S * g.TICK_HZ) {
		step_up(&run)
		passed |= sim.get(&run.simulation.state.minions, minion).pos.z > under.z + 0.5
	}
	testing.expect(t, passed, "the open gate lets it through")
	scenarios.expect_synced(t, &run)
}

// A late joiner's snapshot of a gate half open holds the grille where it is, moving: the joiner's run goes on to
// compute what the host's does, tick for tick.
@(test)
a_late_joiner_sees_a_half_open_gate :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	drop_prop_on(&run, WORKSHOP_CRATE, plate_spot(&run, STORE_PLATE) + {0, g.PLATE_TRAVEL, 0})
	for _ in 0 ..< int(GATE_TRAVEL_S * g.TICK_HZ) {
		if lift_of(&run, STORE_GATE) >= g.GATE_RISE / 2 do break
		headless.run_step(&run)
	}
	if !testing.expectf(
		t,
		lift_of(&run, STORE_GATE) >= g.GATE_RISE / 2,
		"the gate lifts: %v",
		lift_of(&run, STORE_GATE),
	) {
		return
	}
	snapshot := sim.snapshot_encode(run.simulation, run.simulation.tick)
	defer delete(snapshot)
	late, err := headless.run_begin_from_snapshot(&g.GAME, snapshot)
	defer headless.run_end(&late)
	testing.expect_value(t, err, sim.Snap_Error.None)
	testing.expect_value(t, lift_of(&late, STORE_GATE), lift_of(&run, STORE_GATE))
	for _ in 0 ..< int(GATE_TRAVEL_S * g.TICK_HZ) {
		headless.run_step(&run)
		headless.run_step_inputs(&late, &run.recorded[run.simulation.tick - run.start])
		if !testing.expect_value(t, late.final_checksum, run.final_checksum) do break
	}
	testing.expectf(
		t,
		lift_of(&late, STORE_GATE) > g.GATE_RISE - 0.02,
		"the joiner's gate opened: %v",
		lift_of(&late, STORE_GATE),
	)
	scenarios.expect_synced(t, &run)
	scenarios.expect_synced(t, &late)
}

// A gate told to close closes, whatever tick the command lands on: the closing motor's first tick moves the grille
// slower than Box3D's sleep threshold, so a gate whose island fell asleep on that tick would stay open for good. The
// store gate's plate is released on each tick from 1.5 s to 2.5 s after it was pressed (the gate is up and at rest, and
// would fall asleep, in that span), and every time it comes down.
@(test)
a_gate_closes_whatever_tick_it_is_told_to :: proc(t: ^testing.T) {
	for wait in int(1.5 * g.TICK_HZ) ..< int(2.5 * g.TICK_HZ) {
		run := workshop(window = 1)
		defer headless.run_end(&run)
		drop_prop_on(&run, WORKSHOP_CRATE, plate_spot(&run, STORE_PLATE) + {0, g.PLATE_TRAVEL, 0})
		for _ in 0 ..< wait do headless.run_step(&run)
		place_prop(&run, WORKSHOP_CRATE, plate_spot(&run, STORE_PLATE) + {0, 0, 3})
		play(&run, {}, 3) // its closing motor's force stops a rising grille first: GATE_TRAVEL_S and more
		lift := lift_of(&run, STORE_GATE)
		if !testing.expectf(t, lift < 0.02, "released %d ticks after its plate was pressed: lifted %v", wait, lift) {
			break
		}
		scenarios.expect_synced(t, &run)
	}
}

// A shut gate parts an arrival from the party as a wall does (ARRIVAL_FILTER): a joiner arriving beside a hero in the
// store room, whose first ring spot lies past the gate in the hall, arrives in the room instead.
@(test)
a_shut_gate_keeps_an_arrival_on_the_partys_side :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	gate := gate_spot(&run, STORE_GATE)
	// slot 1's first spot (arrival_spot) is ARRIVAL_RING along DIR8[ARRIVAL_SLOT_TURN] = (-x, +z): in front of the gate
	place_hero(&run, 0, gate + {0.5, 0, -1})
	first := dmath.DIR8[g.ARRIVAL_SLOT_TURN % len(dmath.DIR8)]
	past := gate + {0.5, 0, -1} + [3]f32{first.x, 0, first.y} * g.ARRIVAL_RING
	testing.expectf(t, past.z > gate.z + g.GATE_HALF.z - 0.5, "the first spot, %v, lies past the gate", past)
	headless.run_seat(&run, 1, 2)
	headless.run_step(&run)
	joiner := sim.slot_data(run.simulation, 1)
	testing.expectf(t, joiner.pos.z < gate.z - g.GATE_HALF.z, "arrived in the room, not past the gate: %v", joiner.pos)
	scenarios.expect_synced(t, &run)
}

// A skeleton Mage's bone bolt stops at a shut gate (BONE_BOLT_FILTER): a Mage in the store room casts at a hero it sees
// through the grille, and the hero in the hall takes nothing.
@(test)
a_shut_gate_stops_bone_bolts :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	gate := gate_spot(&run, STORE_GATE)
	place_hero(&run, 0, gate + {2.5, 0, 6}, {0, -1}) // in sight through the grille, out of the roller's way
	place_elite(&run, .Mage, gate + {0, 0, -2.5}, {0, 1}, .Chase)
	casts := headless.run_events(&run, g.Event_Elite_Cast)
	play(&run, {}, 4)
	testing.expect(t, headless.run_events(&run, g.Event_Elite_Cast) > casts, "the Mage casts at the hero")
	testing.expect_value(t, sim.slot_data(run.simulation, 0).hp, g.HERO_HP)
	scenarios.expect_synced(t, &run)
}
