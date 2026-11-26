// The plates' rule tests (plates.odin), on the workshop (workshop_test.odin), each on a sync-tested run that ends
// synced, so a slab's joint rolls back with the rest (check_refs after every restore).
package test_crypt_crew

import "core:testing"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// How far a plate's slab has sunk (metres; 0 at rest).
depth_of :: proc(run: ^headless.Run(g.Game), index: int) -> f32 {
	plate, _ := plate_at(run, index)
	return -physics.prismatic_joint_translation(run.simulation.world.phys, plate.joint)
}

// A plate rests up with nothing on it; a crate dropped on it (20 kg, past PLATE_LOAD) sinks it all the way and presses
// it (Event_Plate), and lifted off it, the slab rises back and the plate is released. A coin (a row with no body) lying
// on a plate weighs nothing.
@(test)
a_crate_presses_a_plate_and_a_coin_doesnt :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	plate, handle := plate_at(&run, STORE_PLATE)
	spot := plate_spot(&run, STORE_PLATE)
	coin, _, _ := sim.spawn(&run.simulation.state.loot)
	coin.pos, coin.value, coin.dropped = spot + {0, g.PLATE_TRAVEL, 0}, 1, run.simulation.state.clock.time
	headless.run_pin(&run)
	play(&run, {}, 0.5)
	testing.expectf(t, depth_of(&run, STORE_PLATE) < 0.01, "an idle plate sinks %v m", depth_of(&run, STORE_PLATE))
	testing.expect(t, !plate.pressed, "a coin presses no plate")
	sim.despawn_all(&run.simulation.state.loot)

	drop_prop_on(&run, WORKSHOP_CRATE, spot + {0, g.PLATE_TRAVEL, 0})
	for _ in 0 ..< g.TICK_HZ {
		headless.run_step(&run)
		if plate.pressed do break
	}
	pressed, found := headless.run_last_event(&run, g.Event_Plate)
	testing.expect(t, found && pressed.plate == handle && pressed.pressed, "the tick it sank past PLATE_ON pressed it")
	play(&run, {}, 0.5)
	testing.expectf(
		t,
		depth_of(&run, STORE_PLATE) > g.PLATE_TRAVEL - 0.01,
		"a crate sinks it %v m",
		depth_of(&run, STORE_PLATE),
	)
	testing.expect_value(t, headless.run_events(&run, g.Event_Plate), 1)

	place_prop(&run, WORKSHOP_CRATE, spot + {3, 0, 0})
	play(&run, {}, 1)
	testing.expectf(t, depth_of(&run, STORE_PLATE) < 0.01, "the slab rises back: %v m", depth_of(&run, STORE_PLATE))
	testing.expect(t, !plate.pressed, "lifted off, it is released")
	testing.expect_value(t, headless.run_events(&run, g.Event_Plate), 2)
	scenarios.expect_synced(t, &run)
}

// A hero presses a plate by standing on it: its pogo spring is a joint to the slab, which bears the hero's weight.
@(test)
a_hero_standing_on_a_plate_presses_it :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	plate, _ := plate_at(&run, VAULT_WEST)
	place_hero(&run, 0, plate_spot(&run, VAULT_WEST) + {0, g.PLATE_TRAVEL + g.PLATE_HALF.y * 2, 0})
	play(&run, {}, 1)
	testing.expect(t, plate.pressed, "a hero standing on it presses it")
	hero := sim.slot_data(run.simulation, 0)
	testing.expectf(t, hero.pos.y > 0, "the hero stands on the sunk slab, not under it: feet at %v", hero.pos.y)
	scenarios.expect_synced(t, &run)
}

// A hero weaving down a plate's edge presses it once and releases it once, however its slab bobs: its pogo's middle
// ray falls on and off the slab and the slab jumps between sunk (past PLATE_ON) and partly sunk (between PLATE_OFF and
// PLATE_ON), which a plate with one threshold would take for presses and releases, several a second. And the rule
// itself: between PLATE_OFF and PLATE_ON a plate stays as it was, on the way down and on the way up.
@(test)
a_plate_holds_under_a_walking_hero :: proc(t: ^testing.T) {
	testing.expect(
		t,
		!g.plate_pressed(false, (g.PLATE_OFF + g.PLATE_ON) / 2),
		"sinking past PLATE_OFF presses nothing",
	)
	testing.expect(t, g.plate_pressed(false, g.PLATE_ON + 0.001), "sinking past PLATE_ON presses it")
	testing.expect(t, g.plate_pressed(true, (g.PLATE_OFF + g.PLATE_ON) / 2), "rising above PLATE_ON keeps it pressed")
	testing.expect(t, !g.plate_pressed(true, g.PLATE_OFF - 0.001), "rising above PLATE_OFF releases it")

	run := workshop()
	defer headless.run_end(&run)
	edge := plate_spot(&run, STORE_PLATE) + {g.PLATE_HALF.x + 0.1, 0, 3} // just past its east edge, 3 m north
	place_hero(&run, 0, edge, {0, -1})
	bobs, sunk := 0, false
	for tick in 0 ..< 3 * g.TICK_HZ {
		weave: i8 = 40 if tick / 6 % 2 == 0 else -40 // a step on and a step off the edge, every 6 ticks
		headless.run_step(&run, [g.PLAYERS]g.Input{0 = {move_x = weave, move_z = -40}})
		if depth_of(&run, STORE_PLATE) > g.PLATE_ON != sunk do bobs, sunk = bobs + 1, !sunk
	}
	testing.expectf(t, bobs > 2, "the slab bobs across PLATE_ON (%d times), as the test means it to", bobs)
	testing.expect_value(t, headless.run_events(&run, g.Event_Plate), 2)
	scenarios.expect_synced(t, &run)
}

// A plate stays pressed while anything still weighs on it: a crate and a hero on it, the hero walks off and it stays
// pressed, announcing nothing; the crate lifted off, it is released.
@(test)
a_plate_stays_pressed_while_anything_weighs_on_it :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	plate, _ := plate_at(&run, STORE_PLATE)
	spot := plate_spot(&run, STORE_PLATE)
	top := spot + {0, g.PLATE_TRAVEL + 2 * g.PLATE_HALF.y, 0}
	drop_prop_on(&run, WORKSHOP_CRATE, top + {-0.45, 0, 0})
	place_hero(&run, 0, top + {0.5, 0, 0}, {0, 1})
	play(&run, {}, 0.5)
	testing.expect(t, plate.pressed, "a crate and a hero press it")
	presses := headless.run_events(&run, g.Event_Plate)
	play(&run, {0 = {move_z = 127}}, 1)
	testing.expectf(t, sim.slot_data(run.simulation, 0).pos.z > spot.z + 2, "the hero walked off")
	testing.expect(t, plate.pressed, "the crate still presses it")
	testing.expect_value(t, headless.run_events(&run, g.Event_Plate), presses)
	place_prop(&run, WORKSHOP_CRATE, spot + {0, 0, -3})
	play(&run, {}, 0.5)
	testing.expect(t, !plate.pressed, "nothing on it: released")
	scenarios.expect_synced(t, &run)
}

// A downed hero's ragdoll weighs on a plate as a crate does (RAGDOLL_MASS against PLATE_LOAD; its bones meet
// CAT_PIECE): a hero standing just off a plate's edge, its back to it, goes down (a dev hurt tips it backwards) and its
// body falls across the slab, which sinks and presses; the plate stays pressed while it lies there, its capsule
// dormant and out of the world. A second hero stands far off, so no wipe restarts the floor meanwhile.
@(test)
a_ragdoll_presses_a_plate :: proc(t: ^testing.T) {
	run := workshop(seated = 2)
	defer headless.run_end(&run)
	plate, handle := plate_at(&run, STORE_PLATE)
	spot := plate_spot(&run, STORE_PLATE)
	place_hero(&run, 0, spot + {g.PLATE_HALF.x + 0.4, 0, 0}, {1, 0}) // off the east edge, facing east
	place_hero(&run, 1, spot + {0, 0, 6})
	headless.run_pin(&run)
	play(&run, {}, 0.5)
	testing.expect(t, !plate.pressed, "nothing presses it before the fall")
	hero := sim.slot_data(run.simulation, 0)
	headless.run_command(&run, 0, g.Command_Dev_Hurt{damage = g.HERO_HP})
	testing.expect(t, g.ragdolled(hero), "the hero lies as a ragdoll")
	for _ in 0 ..< 2 * g.TICK_HZ {
		headless.run_step(&run)
		if plate.pressed do break
	}
	pressed, found := headless.run_last_event(&run, g.Event_Plate)
	testing.expect(t, found && pressed.plate == handle && pressed.pressed, "the body falling across it pressed it")
	play(&run, {}, 1)
	testing.expectf(t, depth_of(&run, STORE_PLATE) > g.PLATE_ON, "the body sinks it %v m", depth_of(&run, STORE_PLATE))
	testing.expect(t, plate.pressed && g.ragdolled(hero), "it stays pressed while the body lies on it")
	testing.expect_value(t, headless.run_events(&run, g.Event_Plate), 1)
	scenarios.expect_synced(t, &run)
}
