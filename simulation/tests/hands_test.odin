// The props' and hands' rule tests (props.odin, hands.odin), each on a sync-tested run (headless.Run) that ends
// synced, so a hold's joint and a throw's ignore leave the physics world's refs clean (check_refs after every
// restore). A test places a prop where it needs one (place_prop) and pins the run there.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// Floor 1's props by marker order (game/levels/floor_1.tscn), the ones these tests move.
@(private = "file")
BARREL :: 0
@(private = "file")
CRATE :: 2
@(private = "file")
HEAVY_CRATE :: 3

// Slot 0's spawn on Floor 1, in the first room: open floor for several metres toward +X.
@(private = "file")
SPAWN :: [3]f32{-15.5, 0, -1.2}

// Moves prop `index` (in marker order) to stand at rest on `floor_point`, unturned, and pins the run there.
@(private = "file")
place_prop :: proc(run: ^headless.Run(g.Game), index: int, floor_point: [3]f32) {
	prop := &run.simulation.state.props.items[index]
	centre := floor_point + {0, g.PROP_SPECS[prop.kind].half.y, 0}
	physics.body_teleport(run.simulation.world.phys, prop.body, centre)
	headless.run_pin(run)
}

// The prop (in marker order) at `index`, and its handle.
@(private = "file")
prop_at :: proc(run: ^headless.Run(g.Game), index: int) -> (^g.Prop, sim.Handle(g.Prop)) {
	walk := sim.iterate(&run.simulation.state.props)
	for prop, handle in sim.next(&walk) {
		if int(handle.index) == index do return prop, handle
	}
	return nil, {}
}

// One tick of slot `slot` pressing `button` with `input`, then one with the button up again (the next press is an
// edge), the other seated slots idle.
@(private = "file")
press :: proc(run: ^headless.Run(g.Game), slot: int, button: g.Button, input: g.Input = {}) {
	inputs: [g.PLAYERS]g.Input
	inputs[slot] = input
	inputs[slot].buttons += {button}
	headless.run_step(run, inputs)
	inputs[slot].buttons -= {button}
	headless.run_step(run, inputs)
}

// `seconds` of play with these inputs by slot.
@(private = "file")
play :: proc(run: ^headless.Run(g.Game), inputs: [g.PLAYERS]g.Input, seconds: f32) {
	for _ in 0 ..< int(seconds * g.TICK_HZ) do headless.run_step(run, inputs)
}

// Every prop marker makes a prop of its kind, in marker order, and two runs make the same ones (the same bodies, the
// same bytes).
@(test)
props_are_made_in_marker_order :: proc(t: ^testing.T) {
	first := headless.run_begin(&g.GAME, 1)
	defer headless.run_end(&first)
	second := headless.run_begin(&g.GAME, 2)
	defer headless.run_end(&second)
	places := sim.slice(&first.simulation.world.places.props)
	testing.expect_value(t, int(first.simulation.state.props.count), len(places))
	for def, i in places {
		prop, _ := prop_at(&first, i)
		testing.expect_value(t, prop.kind, def.kind)
	}
	testing.expect_value(t, first.simulation.state.props, second.simulation.state.props)
	scenarios.expect_synced(t, &first)
}

// Interact grabs the nearest free prop in the cone in front, never one behind, however near; the hero picks it up
// (Action.Pick_Up), and a second press drops it where it is.
@(test)
a_hero_grabs_the_nearest_in_front_and_drops_it :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 0)
	hero.facing = {1, 0}
	place_prop(&run, BARREL, SPAWN + {1.9, 0, 0}) // in front, 0.95 m from the capsule
	place_prop(&run, CRATE, SPAWN + {1.5, 0, 0.3}) // in front and nearer
	place_prop(&run, HEAVY_CRATE, SPAWN + {-1.7, 0, 0}) // nearer still, but behind
	crate, crate_handle := prop_at(&run, CRATE)
	testing.expect_value(
		t,
		g.grab_target(run.simulation.world.phys, &run.simulation.state.props, hero.pos, hero.facing),
		crate_handle,
	)
	press(&run, 0, .Interact)
	testing.expect_value(t, hero.held, crate_handle)
	testing.expect_value(t, crate.held_by, sim.player_in_slot(run.simulation, 0))
	testing.expect_value(t, hero.action, g.Action.Pick_Up)
	testing.expect_value(t, headless.run_events(&run, g.Event_Prop_Grabbed), 1)
	play(&run, {}, 0.5)
	held_at := physics.body_position(run.simulation.world.phys, crate.body) - hero.pos
	testing.expectf(t, abs(held_at.y - g.HOLD_HEIGHT) < 0.15 && held_at.x > 0.9, "held at %v from the feet", held_at)
	press(&run, 0, .Interact)
	testing.expect_value(t, hero.held, sim.Handle(g.Prop){})
	testing.expect_value(t, crate.held_by, sim.Player{})
	play(&run, {}, 1)
	testing.expect_value(t, hero.action, g.Action.None)
	resting := physics.body_position(run.simulation.world.phys, crate.body)
	testing.expectf(t, abs(resting.y - g.PROP_SPECS[.Crate].half.y) < 0.05, "the dropped crate rests at %v", resting)
	scenarios.expect_synced(t, &run)
}

// Nothing in reach: the press grabs nothing. A prop out of GRAB_RANGE stays where it is.
@(test)
a_hero_grabs_nothing_out_of_reach :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 0)
	hero.facing = {1, 0}
	place_prop(&run, BARREL, SPAWN + {3, 0, 0}) // 2.05 m from the capsule
	press(&run, 0, .Interact)
	testing.expect_value(t, hero.held, sim.Handle(g.Prop){})
	testing.expect_value(t, headless.run_events(&run, g.Event_Prop_Grabbed), 0)
	scenarios.expect_synced(t, &run)
}

// Carrying slows a hero to the prop's carry_speed of its class's speed.
@(test)
carrying_slows_the_hero :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 0)
	hero.facing = {1, 0}
	place_prop(&run, HEAVY_CRATE, SPAWN + {1.5, 0, 0})
	press(&run, 0, .Interact)
	play(&run, {0 = {move_x = 127}}, 1)
	speed := g.CLASS_SPECS[hero.class].max_speed * g.PROP_SPECS[.Heavy_Crate].carry_speed
	testing.expectf(t, abs(hero.vel.x - speed) < 0.15, "carries at %v m/s, not %v", hero.vel.x, speed)
	scenarios.expect_synced(t, &run)
}

// Attack while holding throws, THROW_WINDUP_S after the press: the prop flies along the facing and lands well away, it
// passes through its thrower until clear (the thrower, standing in its path, is never pushed), and the throw is the
// thrower's for THROWN_S.
@(test)
a_throw_flies_along_the_facing :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 0)
	hero.facing = {1, 0}
	place_prop(&run, BARREL, SPAWN + {1.4, 0, 0})
	barrel, barrel_handle := prop_at(&run, BARREL)
	press(&run, 0, .Interact)
	play(&run, {}, 0.75) // the pick-up ends
	standing := hero.pos
	press(&run, 0, .Attack)
	testing.expect_value(t, hero.action, g.Action.Throw)
	testing.expect_value(t, hero.held, barrel_handle) // still winding up
	for _ in 0 ..< g.THROW_WINDUP_TICKS do headless.run_step(&run)
	testing.expect_value(t, hero.held, sim.Handle(g.Prop){})
	testing.expect_value(t, headless.run_events(&run, g.Event_Prop_Thrown), 1)
	testing.expect_value(t, barrel.thrown_by, sim.player_in_slot(run.simulation, 0))
	testing.expect(t, barrel.thrower_ignore != {}, "the barrel ignores its thrower")
	play(&run, {}, 0.25)
	flying := physics.body_position(run.simulation.world.phys, barrel.body)
	testing.expectf(
		t,
		flying.x > standing.x + 3 && abs(flying.z - standing.z) < 0.1,
		"a quarter second out: %v",
		flying,
	)
	play(&run, {}, 2)
	landed := physics.body_position(run.simulation.world.phys, barrel.body)
	testing.expectf(t, landed.x > standing.x + 6, "it came down at %v, from %v", landed, standing)
	testing.expect_value(t, barrel.thrower_ignore, physics.Filter_Joint_Ref{})
	testing.expect(t, !sim.timer_running(run.simulation.state.clock.time, barrel.thrown), "the throw ran out")
	testing.expectf(t, dmath.length(hero.pos - standing) < 0.05, "the thrower moved: %v from %v", hero.pos, standing)
	testing.expect(t, headless.run_events(&run, g.Event_Prop_Impact) > 0, "the barrel thudded down")
	scenarios.expect_synced(t, &run)
}

// A hero who leaves while carrying lets go first: the prop is nobody's, the hold's joint is gone with no stale ref
// (the run stays synced: check_refs), and it is announced as dropped.
@(test)
a_leaver_lets_go :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	sim.slot_data(run.simulation, 1).facing = {1, 0}
	place_prop(&run, BARREL, run.simulation.world.places.hero_spawns[1] + {1.4, 0, 0})
	barrel, barrel_handle := prop_at(&run, BARREL)
	press(&run, 1, .Interact)
	testing.expect_value(t, sim.slot_data(run.simulation, 1).held, barrel_handle)
	headless.run_seat(&run, 1, 0)
	headless.run_step(&run)
	testing.expect_value(t, barrel.held_by, sim.Player{})
	testing.expect_value(t, headless.run_events(&run, g.Event_Prop_Dropped), 1)
	play(&run, {}, 0.5)
	scenarios.expect_synced(t, &run)
}
