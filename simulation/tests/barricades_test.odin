// The barricades' rule tests (barricades.odin), on the workshop (workshop_test.odin), each on a sync-tested run that
// ends synced: every step after a break restores to before it and re-simulates the blow (headless.Run's window), so
// the weld's break under rollback is checked tick by tick, its refs included (check_refs after every restore).
package test_crypt_crew

import "core:testing"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// The workshop's barricade's place: its fence runs along x, closing the store room's second way into the hall (+z).
barricade_spot :: proc(run: ^headless.Run(g.Game)) -> [3]f32 {
	return sim.slice(&floor_of(run).places.barricades)[0].pos
}

// A hero walking into a barricade at a run for two seconds leaves it standing (its weld strains as hard as under a
// thrown crate, but a walk is no blow); a crate thrown into it from far enough off that its arc comes down onto the
// fence breaks it, blamed on the thrower: its weld gone and the fence loose debris in CAT_PROP, untagged, and no
// longer in minions' way.
@(test)
a_barricade_survives_a_walk_in_and_breaks_to_a_thrown_crate :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	barricade, handle, _ := sim.item_at(&run.simulation.state.barricades, 0)
	fence := barricade_spot(&run)
	place_hero(&run, 0, fence + {0, 0, 3}, {0, -1})
	play(&run, {0 = {move_z = -127}}, 2)
	hero := sim.slot_data(run.simulation, 0)
	testing.expectf(t, hero.pos.z < fence.z + 1, "the hero ran into it: at %v", hero.pos)
	testing.expect(t, !barricade.broken, "a walk-in leaves it standing")
	testing.expect_value(t, headless.run_events(&run, g.Event_Barricade_Broken), 0)

	place_hero(&run, 0, fence + {0, 0, 8.5}, {0, -1})
	place_prop(&run, WORKSHOP_CRATE, fence + {0, 0, 7.1})
	press(&run, 0, .Interact)
	play(&run, {}, 0.75)
	press(&run, 0, .Attack)
	for _ in 0 ..< g.TICK_HZ {
		headless.run_step(&run)
		if barricade.broken do break
	}
	testing.expect(t, barricade.broken, "a thrown crate breaks it")
	broken, found := headless.run_last_event(&run, g.Event_Barricade_Broken)
	testing.expect(t, found && broken.barricade == handle, "the break is announced the tick it happens")
	testing.expect_value(t, broken.player, sim.player_in_slot(run.simulation, 0))
	phys := run.simulation.world.phys
	testing.expect_value(t, barricade.weld, physics.Weld_Joint_Ref{})
	testing.expect_value(t, physics.body_tag(phys, barricade.body), 0)
	physics.body_shapes(phys, barricade.body, &run.simulation.world.shapes)
	testing.expect_value(t, physics.shape_filter(phys, run.simulation.world.shapes[0]).category, g.CAT_PROP)
	play(&run, {}, 1)
	scenarios.expect_synced(t, &run)
}

// A Knight's shield charge breaks a barricade: a blow, blamed on the Knight.
@(test)
a_charge_breaks_a_barricade :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Knight})
	barricade, _, _ := sim.item_at(&run.simulation.state.barricades, 0)
	place_hero(&run, 0, barricade_spot(&run) + {0, 0, 3.5}, {0, -1})
	block := [g.PLAYERS]g.Input {
		0 = {buttons = {.Ability}},
	}
	headless.run_step(&run, block)
	block[0].buttons += {.Attack}
	for _ in 0 ..< g.CHARGE_TICKS {
		headless.run_step(&run, block)
		if barricade.broken do break
	}
	testing.expect(t, barricade.broken, "the charge breaks it")
	broken, _ := headless.run_last_event(&run, g.Event_Barricade_Broken)
	testing.expect_value(t, broken.player, sim.player_in_slot(run.simulation, 0))
	play(&run, {}, 0.5)
	scenarios.expect_synced(t, &run)
}

// A standing barricade holds a minion back (its obstacles); broken, it doesn't: a minion in the store room (its gate
// shut) chases the hero in the hall and stays behind the fence until a charge breaks it.
@(test)
a_barricade_holds_minions_back_until_it_breaks :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Knight})
	fence := barricade_spot(&run)
	place_hero(&run, 0, fence + {0, 0, 2.5}, {0, -1})
	minion := place_minion(&run, fence + {0, 0, -1.5}, .Chase)
	for _ in 0 ..< g.TICK_HZ {
		step_up(&run)
		pos := sim.get(&run.simulation.state.minions, minion).pos
		if !testing.expectf(t, pos.z < fence.z - g.MINION_RADIUS, "the fence holds it back: %v", pos) do break
	}
	barricade, _, _ := sim.item_at(&run.simulation.state.barricades, 0)
	place_hero(&run, 0, fence + {0, 0, 1.5}, {0, -1})
	headless.run_step(&run, [g.PLAYERS]g.Input{0 = {buttons = {.Ability}}})
	headless.run_step(&run, [g.PLAYERS]g.Input{0 = {buttons = {.Ability, .Attack}}})
	for _ in 0 ..< g.CHARGE_TICKS do headless.run_step(&run, [g.PLAYERS]g.Input{0 = {buttons = {.Ability}}})
	testing.expect(t, barricade.broken, "the charge broke it")
	place_hero(&run, 0, fence + {0, 0, 3}, {0, -1}) // back in the hall: the minion comes out to it
	passed := false
	for _ in 0 ..< 2 * g.TICK_HZ {
		step_up(&run)
		if minion := sim.get(&run.simulation.state.minions, minion); minion != nil {
			passed |= minion.pos.z > fence.z + g.MINION_RADIUS
		}
	}
	testing.expect(t, passed, "the broken fence lets it through")
	scenarios.expect_synced(t, &run)
}
