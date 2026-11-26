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

// The workshop's barricade and its handle.
barricade_at :: proc(run: ^headless.Run(g.Game)) -> (^g.Barricade, sim.Handle(g.Barricade)) {
	barricade, handle, _ := sim.item_at(&run.simulation.state.barricades, 0)
	return barricade, handle
}

// Slot 0 throws the crate it picks up from `distance` metres in front of the fence (facing it), and the run goes on
// until the barricade breaks or a second passes.
throw_crate_at_fence :: proc(run: ^headless.Run(g.Game), distance: f32) {
	fence := barricade_spot(run)
	place_hero(run, 0, fence + {0, 0, distance}, {0, -1})
	place_prop(run, WORKSHOP_CRATE, fence + {0, 0, distance - 1.4}) // in reach, in front
	press(run, 0, .Interact)
	play(run, {}, 0.75)
	press(run, 0, .Attack)
	barricade, _ := barricade_at(run)
	for _ in 0 ..< g.TICK_HZ {
		headless.run_step(run)
		if barricade.broken do break
	}
}

// A barricade nothing touches strains its weld with nothing but its own weight: Box3D reports no joint event, tick
// after tick (a fence pressed into a wall, or a threshold under its weight, would report one every tick).
@(test)
an_untouched_barricade_strains_nothing :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	joints: [dynamic]physics.Joint_Ref
	defer delete(joints)
	for _ in 0 ..< 2 * g.TICK_HZ {
		headless.run_step(&run)
		physics.world_joint_events(run.simulation.world.phys, &joints)
		if !testing.expectf(t, len(joints) == 0, "the weld reports %v at rest", joints) do break
	}
	barricade, _ := barricade_at(&run)
	testing.expect(t, !barricade.broken, "it stands")
	scenarios.expect_synced(t, &run)
}

// A hero running into a barricade beside a crate resting against it leaves it standing: the weld strains harder than
// under a thrown crate, but neither a walk nor a resting prop is a blow.
@(test)
a_barricade_survives_a_walk_in :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	barricade, _ := barricade_at(&run)
	fence := barricade_spot(&run)
	place_prop(&run, WORKSHOP_CRATE, fence + {-1, 0, g.BARRICADE_HALF.z + g.PROP_SPECS[.Crate].half.z + 0.01})
	place_hero(&run, 0, fence + {1, 0, 3}, {0, -1})
	play(&run, {0 = {move_z = -127}}, 2)
	hero := sim.slot_data(run.simulation, 0)
	testing.expectf(t, hero.pos.z < fence.z + 1, "the hero ran into it: at %v", hero.pos)
	testing.expect(t, !barricade.broken, "a walk-in leaves it standing")
	testing.expect_value(t, headless.run_events(&run, g.Event_Barricade_Broken), 0)
	scenarios.expect_synced(t, &run)
}

// A crate thrown into a barricade from 3, 4 or 5 metres (it meets the fence: its body stands taller than a crate's
// flight) strains the weld past BARRICADE_BREAK_N and breaks it, blamed on the thrower: its weld gone and the fence
// loose debris in CAT_PROP, untagged.
@(test)
a_thrown_crate_breaks_a_barricade :: proc(t: ^testing.T) {
	for distance in ([]f32{3, 4, 5}) {
		run := workshop()
		defer headless.run_end(&run)
		barricade, handle := barricade_at(&run)
		throw_crate_at_fence(&run, distance)
		testing.expectf(t, barricade.broken, "a crate thrown from %v m breaks it", distance)
		broken, found := headless.run_last_event(&run, g.Event_Barricade_Broken)
		testing.expect(t, found && broken.barricade == handle, "the break is announced the tick it happens")
		testing.expect_value(t, broken.player, sim.player_in_slot(run.simulation, 0))
		phys := run.simulation.world.phys
		testing.expect_value(t, barricade.weld, physics.Weld_Joint_Ref{})
		testing.expect_value(t, physics.body_tag(phys, barricade.body), 0)
		physics.body_shapes(phys, barricade.body, &run.simulation.world.shapes)
		testing.expect_value(t, physics.shape_filter(phys, run.simulation.world.shapes[0]).category, g.CAT_PROP)
		play(&run, {}, 0.5)
		scenarios.expect_synced(t, &run)
	}
}

// A blow under BARRICADE_BREAK_N leaves a barricade standing: a crate at the end of its throw (its throw still running)
// nudging the fence at 3 m/s is a blow, but too light a one.
@(test)
a_light_blow_leaves_a_barricade :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	barricade, _ := barricade_at(&run)
	crate, _ := prop_at(&run, WORKSHOP_CRATE)
	place_prop(&run, WORKSHOP_CRATE, barricade_spot(&run) + {0, 0, 1.2})
	phys := run.simulation.world.phys
	physics.body_set_awake(phys, crate.body, true)
	physics.body_set_linear_velocity(phys, crate.body, {0, 0, -3})
	now := run.simulation.state.clock.time
	crate.thrown = {
		start  = now,
		target = now + sim.Game_Time(g.THROWN_TICKS),
	}
	crate.thrown_by = sim.player_in_slot(run.simulation, 0)
	headless.run_pin(&run)
	play(&run, {}, 0.5)
	testing.expect(t, !barricade.broken, "a light blow leaves it standing")
	scenarios.expect_synced(t, &run)
}

// A body a Barbarian throws into a barricade breaks it, blamed on the Barbarian: a skeleton, and a downed ally.
@(test)
a_hurled_body_breaks_a_barricade :: proc(t: ^testing.T) {
	for ally in ([]bool{false, true}) {
		run := workshop(seated = 2)
		defer headless.run_end(&run)
		headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Barbarian})
		barricade, _ := barricade_at(&run)
		fence := barricade_spot(&run)
		place_hero(&run, 1, fence + {4, 0, 4}) // out of the way
		place_hero(&run, 0, fence + {0, 0, 3.5}, {0, -1})
		ahead := fence + {0, 0, 3.5 - GRAB_AHEAD}
		if ally {
			place_hero(&run, 1, ahead)
			hurt(&run, 1, g.HERO_HP)
		} else {
			place_elite(&run, .Warrior, ahead, {0, 1}, .Idle)
		}
		press(&run, 0, .Ability)
		play(&run, {}, 4.0 / g.TICK_HZ)
		press(&run, 0, .Attack)
		for _ in 0 ..< g.TICK_HZ {
			headless.run_step(&run)
			if barricade.broken do break
		}
		testing.expectf(t, barricade.broken, "a hurled %s breaks it", "ally" if ally else "skeleton")
		broken, _ := headless.run_last_event(&run, g.Event_Barricade_Broken)
		testing.expect_value(t, broken.player, sim.player_in_slot(run.simulation, 0))
		scenarios.expect_synced(t, &run)
	}
}

// A thrown body falling onto a barricade's top has landed there (the landing's ray meets mechanisms: LAND_FILTER),
// rather than flying on until HEAVE_FLIGHT_MAX_S.
@(test)
a_thrown_body_lands_on_a_barricade :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Barbarian})
	fence := barricade_spot(&run)
	place_hero(&run, 0, fence + {0, 0, 4}, {0, 1})
	warrior := place_elite(&run, .Warrior, fence + {0, 0, 4 + GRAB_AHEAD}, {0, -1}, .Idle)
	press(&run, 0, .Ability)
	play(&run, {}, 4.0 / g.TICK_HZ)
	press(&run, 0, .Attack)
	play(&run, {}, f32(g.THROW_WINDUP_TICKS) / g.TICK_HZ)
	elite := elite_of(&run, warrior)
	testing.expect_value(t, elite.phase, g.Elite_Phase.Thrown)
	phys := run.simulation.world.phys
	top := fence + {0, 2 * g.BARRICADE_HALF.y, 0}
	physics.character_teleport(phys, &elite.body, top + {0, g.ELITE_HALF_HEIGHT + g.ELITE_RADIUS + 0.1, 0})
	physics.body_set_linear_velocity(phys, elite.body.body, {0, -1, 0})
	headless.run_pin(&run)
	landed := headless.run_events(&run, g.Event_Heave_Landed)
	play(&run, {}, 2.0 / g.TICK_HZ)
	testing.expect_value(t, headless.run_events(&run, g.Event_Heave_Landed), landed + 1)
	scenarios.expect_synced(t, &run)
}

// A broken barricade stands again when the floor starts over: its debris goes with the floor, and the floor's markers
// make it anew, welded.
@(test)
a_broken_barricade_stands_again_when_the_floor_restarts :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	throw_crate_at_fence(&run, 4)
	barricade, _ := barricade_at(&run)
	testing.expect(t, barricade.broken, "the crate broke it")
	hurt(&run, 0, g.HERO_HP)
	play(&run, {}, g.WIPE_S + 0.25)
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 1)
	testing.expect_value(t, int(run.simulation.state.barricades.count), 1)
	barricade, _ = barricade_at(&run)
	testing.expect(t, !barricade.broken && barricade.weld != {}, "it stands again, welded")
	scenarios.expect_synced(t, &run)
}

// A Knight's shield charge breaks a barricade: a blow, blamed on the Knight.
@(test)
a_charge_breaks_a_barricade :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Knight})
	barricade, _ := barricade_at(&run)
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
	barricade, _ := barricade_at(&run)
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
