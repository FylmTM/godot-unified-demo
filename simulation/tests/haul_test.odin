// The hoard's and the lift's rule tests (hoard.odin, lift.odin): taking a handle, one hauler dragging and two carrying
// from the same rule, every way a hold lets go, the lift boarding only with the hoard at rest and everyone aboard (the
// downed too), stepping off, the ride, a late joiner on the deck, a leaver, and the descent with its save. Each on a
// sync-tested run (headless.Run) that ends synced, so the holds, the deck and the level change also roll back. The
// hoard and the lift are Floor 1's; the hoard is taken out of its vault into the great hall (HALL_HOARD: room to walk
// it about in), heroes are put beside it (place_hero), the party aboard by dev_board.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// How far east of the deck's middle a Barbarian throws a body onto it from: the body comes down on the deck's near half
// and slides into the hoard resting across its far edge.
THROW_FROM :: f32(12)

// A quarter turn about +Y: a body's +X turned to -Z.
QUARTER_TURN :: [4]f32{0, 0.70710678, 0, 0.70710678}

// How far out from a handle a hauler stands to take it (feet to handle, on the floor plan): in reach of its capsule.
HANDLE_STAND :: f32(0.7)

// Where the haul tests stand the hoard, out of the vault: the great hall, between its braziers.
HALL_HOARD :: [3]f32{8, 0, -10.6}

// A run of `seated` heroes on Floor 1 with no minion and no elite (nothing to hurt them), the hoard resting at
// HALL_HOARD unless `in_vault`.
@(private = "file")
quiet_run :: proc(seated: int, in_vault := false) -> headless.Run(g.Game) {
	run := headless.run_begin(&g.GAME, 1, seated = seated)
	clear_minions(&run)
	clear_elites(&run)
	if !in_vault {
		hoard := run.simulation.state.hoard.body
		physics.body_teleport(run.simulation.world.phys, hoard, HALL_HOARD + {0, g.HOARD_HALF.y, 0})
		headless.run_pin(&run)
	}
	return run
}

// Puts slot `slot`'s hero beside the hoard's `handle`, out along the hoard's long side, facing it.
@(private = "file")
beside_handle :: proc(run: ^headless.Run(g.Game), slot: int, handle: g.Haul_Handle) {
	state := &run.simulation.state
	phys := run.simulation.world.phys
	point := g.handle_point(phys, &state.hoard, handle)
	out := dmath.normalize(point.xz - physics.body_position(phys, state.hoard.body).xz)
	place_hero(run, slot, {point.x + out.x * HANDLE_STAND, 0, point.z + out.y * HANDLE_STAND}, -out)
}

// The point on the deck's top at `local` (in the deck's frame, from the middle of its top).
@(private = "file")
deck_point :: proc(run: ^headless.Run(g.Game), local: [3]f32) -> [3]f32 {
	lift := &run.simulation.state.lift
	return physics.body_world_point(run.simulation.world.phys, lift.body, local + {0, g.LIFT_HALF.y, 0})
}

// Every slot in `slots` presses Interact in one tick (the others idle), then lets go.
@(private = "file")
press_all :: proc(run: ^headless.Run(g.Game), slots: []int) {
	inputs: [g.PLAYERS]g.Input
	for slot in slots do inputs[slot].buttons = {.Interact}
	headless.run_step(run, inputs)
	headless.run_step(run)
}

// `seconds` of the slots in `slots` walking along `move` (a full stick), the others idle.
@(private = "file")
walk :: proc(run: ^headless.Run(g.Game), slots: []int, move: [2]i8, seconds: f32) {
	inputs: [g.PLAYERS]g.Input
	for slot in slots do inputs[slot].move_x, inputs[slot].move_z = move.x, move.y
	play(run, inputs, seconds)
}

// dev_board (the hoard and everyone on the deck), then a step, so the deck's sensor has seen the hoard.
@(private = "file")
board :: proc(run: ^headless.Run(g.Game)) {
	headless.run_command(run, 0, g.Command_Dev_Board{})
	headless.run_step(run)
}

// Steps until the lift is in `phase`, at most `seconds`; whether it got there.
@(private = "file")
until_lift :: proc(run: ^headless.Run(g.Game), phase: g.Lift_Phase, seconds: f32 = 10) -> bool {
	for _ in 0 ..< int(seconds * g.TICK_HZ) {
		if run.simulation.state.lift.phase == phase do return true
		headless.run_step(run)
	}
	return run.simulation.state.lift.phase == phase
}

// The floor's hoard and lift are made from its markers, at rest: the hoard where its marker stands, weighing
// HOARD_REST_MASS (no hero shoves it), the deck at floor level, waiting.
@(test)
the_hoard_and_the_lift_stand_at_their_markers :: proc(t: ^testing.T) {
	run := quiet_run(1, in_vault = true)
	defer headless.run_end(&run)
	state := &run.simulation.state
	phys := run.simulation.world.phys
	places := &floor_of(&run).places
	testing.expect(t, places.hoard.placed && places.lift.placed, "Floor 1 has a hoard and a lift")
	at := physics.body_position(phys, state.hoard.body)
	testing.expectf(t, dmath.length(at - (places.hoard.pos + {0, g.HOARD_HALF.y, 0})) < 0.02, "the hoard at %v", at)
	testing.expectf(t, abs(physics.body_mass(phys, state.hoard.body) - g.HOARD_REST_MASS) < 1, "it weighs its rest")
	deck := physics.body_position(phys, state.lift.body)
	testing.expectf(t, abs(deck.y + g.LIFT_HALF.y) < 1e-3, "the deck's top at the floor (%v)", deck)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Waiting)
	scenarios.expect_synced(t, &run)
}

// Interact beside a handle takes it (Action.Haul, the hoard at HOARD_MASS), and the press grabs no prop though one is
// in reach; Interact again lets go, and grabs nothing either. A hauler neither attacks nor uses its ability.
@(test)
a_hero_takes_a_handle_and_lets_go :: proc(t: ^testing.T) {
	run := quiet_run(1)
	defer headless.run_end(&run)
	state := &run.simulation.state
	phys := run.simulation.world.phys
	hero := sim.slot_data(run.simulation, 0)
	beside_handle(&run, 0, .Left)
	place_prop(&run, CRATE, hero.pos + {-0.2, 0, 1.4}) // a crate in reach too
	testing.expect_value(t, g.haul_target(phys, &state.hoard, &state.lift, hero), g.Haul_Handle.Left)
	press(&run, 0, .Interact)
	testing.expect_value(t, hero.handle, g.Haul_Handle.Left)
	testing.expect_value(t, hero.action, g.Action.Haul)
	testing.expect_value(t, hero.held, sim.Handle(g.Prop){})
	testing.expect_value(t, state.hoard.haulers[0], sim.player_in_slot(run.simulation, 0))
	testing.expectf(t, abs(physics.body_mass(phys, state.hoard.body) - g.HOARD_MASS) < 1, "held, it weighs HOARD_MASS")
	testing.expect_value(t, headless.run_events(&run, g.Event_Hoard_Grabbed), 1)
	inputs: [g.PLAYERS]g.Input
	inputs[0].buttons = {.Attack, .Ability}
	play(&run, inputs, 0.5)
	testing.expect_value(t, hero.action, g.Action.Haul) // no swing, no ability
	testing.expect_value(t, headless.run_events(&run, g.Event_Hero_Attacked), 0)
	press(&run, 0, .Interact)
	testing.expect_value(t, hero.handle, g.Haul_Handle.None)
	testing.expect_value(t, hero.action, g.Action.None)
	testing.expect_value(t, hero.held, sim.Handle(g.Prop){})
	testing.expect_value(t, state.hoard.haulers, [2]sim.Player{})
	dropped, _ := headless.run_last_event(&run, g.Event_Hoard_Dropped)
	testing.expect(t, !dropped.slipped, "let go, not slipped")
	testing.expectf(t, abs(physics.body_mass(phys, state.hoard.body) - g.HOARD_REST_MASS) < 1, "unheld, its rest")
	scenarios.expect_synced(t, &run)
}

// The same rule, one hauler or two: alone, a hold lifts one end and the hauler drags the hoard at HOARD_DRAG_SPEED;
// with a hauler at each handle the hoard is carried clear at HOARD_CARRY_SPEED, nearly twice as fast. Physics tells
// them apart: the hold's cap lifts half the weight, never all of it.
@(test)
one_hauler_drags_and_two_carry :: proc(t: ^testing.T) {
	speeds: [2]f32 // the hoard's speed along the walk, with one hauler and with two
	for haulers in 1 ..= 2 {
		run := quiet_run(2)
		defer headless.run_end(&run)
		phys := run.simulation.world.phys
		hoard := &run.simulation.state.hoard
		beside_handle(&run, 0, .Left)
		if haulers == 2 do beside_handle(&run, 1, .Right)
		both := []int{0, 1}
		slots := both[:haulers]
		press_all(&run, slots)
		play(&run, {}, 0.5) // lifted
		lowest := physics.body_position(phys, hoard.body).y - g.HOARD_HALF.y
		if haulers == 2 do testing.expectf(t, lowest > 0.1, "two lift it clear (its bottom at %v)", lowest)
		walk(&run, slots, {0, 127}, 1) // getting going
		from := physics.body_position(phys, hoard.body)
		walk(&run, slots, {0, 127}, 0.75)
		speeds[haulers - 1] = (physics.body_position(phys, hoard.body).z - from.z) / 0.75
		hero := sim.slot_data(run.simulation, 0)
		testing.expect_value(t, hero.handle, g.Haul_Handle.Left) // held all the way
		want := (g.HOARD_DRAG_SPEED if haulers == 1 else g.HOARD_CARRY_SPEED) * g.CLASS_SPECS[hero.class].max_speed
		walking := dmath.length(hero.vel.xz)
		testing.expectf(t, abs(walking - want) < 0.1, "%d hauler(s) walk at %v m/s, not %v", haulers, walking, want)
		scenarios.expect_synced(t, &run)
	}
	testing.expectf(
		t,
		speeds[1] > 1.5 * speeds[0],
		"two (%v m/s) carry faster than one drags (%v)",
		speeds[1],
		speeds[0],
	)
}

// A hold stretched past HOARD_SLIP lets go (slipped): the hauler gone on, the hoard caught.
@(test)
a_stretched_hold_slips :: proc(t: ^testing.T) {
	run := quiet_run(1)
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 0)
	beside_handle(&run, 0, .Left)
	press(&run, 0, .Interact)
	play(&run, {}, 0.25)
	testing.expect_value(t, hero.handle, g.Haul_Handle.Left)
	place_hero(&run, 0, hero.pos + {-2 * g.HOARD_SLIP, 0, 0}, {-1, 0}) // the hold now stretched past HOARD_SLIP
	headless.run_step(&run)
	testing.expect_value(t, hero.handle, g.Haul_Handle.None)
	testing.expect_value(t, run.simulation.state.hoard.haulers, [2]sim.Player{})
	dropped, _ := headless.run_last_event(&run, g.Event_Hoard_Dropped)
	testing.expect(t, dropped.slipped, "it slipped")
	scenarios.expect_synced(t, &run)
}

// A hauler going down lets go (and so does one leaving): the handle is free for another.
@(test)
a_downed_or_leaving_hauler_lets_go :: proc(t: ^testing.T) {
	run := quiet_run(2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	beside_handle(&run, 0, .Left)
	beside_handle(&run, 1, .Right)
	press_all(&run, {0, 1})
	testing.expect_value(t, sim.slot_data(run.simulation, 0).handle, g.Haul_Handle.Left)
	hurt(&run, 0, g.HERO_HP)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).action, g.Action.Down)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).handle, g.Haul_Handle.None)
	testing.expect_value(t, state.hoard.haulers[0], sim.Player{})
	testing.expect_value(t, state.hoard.haulers[1], sim.player_in_slot(run.simulation, 1))
	leaver := sim.player_in_slot(run.simulation, 1)
	headless.run_seat(&run, 1, 0)
	headless.run_step(&run)
	testing.expect_value(t, state.hoard.haulers, [2]sim.Player{})
	dropped, _ := headless.run_last_event(&run, g.Event_Hoard_Dropped)
	testing.expect_value(t, dropped.player, leaver)
	scenarios.expect_synced(t, &run)
}

// The first grab on a floor starts the haul: the next surge comes within HAUL_SURGE_S, and the ones after every
// HAUL_SURGE_S.
@(test)
the_haul_wakes_the_crypt :: proc(t: ^testing.T) {
	run := quiet_run(1)
	defer headless.run_end(&run)
	state := &run.simulation.state
	play(&run, {}, g.SURGE_FIRST_S + 0.5) // the first surge rose: the next SURGE_EVERY_S on
	testing.expect_value(t, state.surges, 1)
	beside_handle(&run, 0, .Left)
	press(&run, 0, .Interact)
	testing.expect(t, state.hoard.hauled, "the haul began")
	testing.expect_value(t, u32(state.surge.target - state.clock.time), g.HAUL_SURGE_TICKS - 1)
	for _ in 0 ..< g.HAUL_SURGE_TICKS - 1 do headless.run_step(&run) // to the surge's tick: its clock starts again
	testing.expect_value(t, u32(state.surge.target - state.clock.time), g.HAUL_SURGE_TICKS)
	scenarios.expect_synced(t, &run)
}

// The lift boards once the hoard rests on the deck, nobody holding it, and everyone is aboard; anyone stepping off
// while it boards puts it back to waiting; LIFT_HOLD_S of everyone aboard and it goes down.
@(test)
the_lift_boards_and_stepping_off_cancels :: proc(t: ^testing.T) {
	run := quiet_run(2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	board(&run)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Boarding)
	play(&run, {}, g.LIFT_HOLD_S / 2)
	place_hero(&run, 1, spawn_of(&run, 1)) // off the deck, before the hold runs out
	headless.run_step(&run)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Waiting)
	board(&run)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Boarding)
	play(&run, {}, g.LIFT_HOLD_S - 2.0 / g.TICK_HZ) // boarding since the command's tick, a tick before board's step
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Boarding)
	headless.run_step(&run)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Descending)
	scenarios.expect_synced(t, &run)
}

// The lift won't board with a hero off the deck, nor with a hand on the hoard; a downed hero off the deck holds it
// too, and one aboard counts as aboard (nobody is left behind, the downed ride down as they lie).
@(test)
the_lift_waits_for_everyone_and_the_hoard_at_rest :: proc(t: ^testing.T) {
	run := quiet_run(3)
	defer headless.run_end(&run)
	state := &run.simulation.state
	board(&run)
	place_hero(&run, 2, spawn_of(&run, 2)) // off the deck
	play(&run, {}, 0.25)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Waiting)
	hurt(&run, 2, g.HERO_HP) // down, off the deck: still waited for
	play(&run, {}, 0.25)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Waiting)
	board(&run) // the downed one carried aboard with the others: its body laid on the deck
	testing.expect_value(t, sim.slot_data(run.simulation, 2).action, g.Action.Down)
	testing.expect(t, g.ragdolled(sim.slot_data(run.simulation, 2)), "it lies on the deck as a ragdoll")
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Boarding)
	beside_handle(&run, 0, .Right) // boarding, the hoard takes no hand: not even "[E] Haul" offers one
	hero := sim.slot_data(run.simulation, 0)
	testing.expect_value(
		t,
		g.haul_target(run.simulation.world.phys, &state.hoard, &state.lift, hero),
		g.Haul_Handle.None,
	)
	press(&run, 0, .Interact)
	testing.expect_value(t, hero.handle, g.Haul_Handle.None)
	place_hero(&run, 1, spawn_of(&run, 1)) // off: back to waiting, and a hand may take the hoard
	play(&run, {}, 0.1)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Waiting)
	beside_handle(&run, 0, .Right)
	press(&run, 0, .Interact)
	testing.expect_value(t, hero.handle, g.Haul_Handle.Right)
	place_hero(&run, 1, deck_point(&run, {1, 0, 1} * g.LIFT_SLOT_SPREAD)) // everyone aboard again, the hoard held
	play(&run, {}, 0.25)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Waiting)
	press(&run, 0, .Interact) // let go: it boards
	play(&run, {}, 0.25)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Boarding)
	scenarios.expect_synced(t, &run)
}

// A party all down on the deck with the hoard doesn't ride: a wipe is a wipe.
@(test)
a_party_all_down_doesnt_ride :: proc(t: ^testing.T) {
	run := quiet_run(1)
	defer headless.run_end(&run)
	board(&run)
	testing.expect_value(t, run.simulation.state.lift.phase, g.Lift_Phase.Boarding)
	hurt(&run, 0, g.HERO_HP)
	headless.run_step(&run)
	testing.expect_value(t, run.simulation.state.lift.phase, g.Lift_Phase.Waiting)
	scenarios.expect_synced(t, &run)
}

// Going down: LIFT_DROP in LIFT_RIDE_S, the riders and the hoard carried with the deck, nobody hurt meanwhile (a dev
// hurt does nothing) and no wipe; at the bottom the heroes choose.
@(test)
the_lift_carries_its_riders_down :: proc(t: ^testing.T) {
	run := quiet_run(2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	phys := run.simulation.world.phys
	hurt(&run, 1, g.HERO_HP) // one rides down, down
	board(&run)
	testing.expect(t, until_lift(&run, .Descending), "it goes down")
	top := physics.body_position(phys, state.lift.body).y
	hurt(&run, 0, 10)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).hp, g.HERO_HP) // nobody is hurt going down
	testing.expect(t, until_lift(&run, .Choosing, g.LIFT_RIDE_S + 0.1), "it reaches the bottom")
	play(&run, {}, 0.5) // the riders settle
	bottom := physics.body_position(phys, state.lift.body).y
	testing.expectf(t, abs(top - bottom - g.LIFT_DROP) < 1e-3, "it went down %v", top - bottom)
	for slot in 0 ..< 2 {
		hero := sim.slot_data(run.simulation, slot)
		testing.expectf(t, g.on_deck(phys, &state.lift, hero.pos), "slot %d rode down (at %v)", slot, hero.pos)
	}
	hoard_at := physics.body_position(phys, state.hoard.body).y
	testing.expectf(t, abs(hoard_at - (bottom + g.LIFT_HALF.y + g.HOARD_HALF.y)) < 0.05, "the hoard rode down")
	testing.expect_value(t, state.wipe, sim.Timer{}) // one down, one up: and the lift's ride never wipes
	scenarios.expect_synced(t, &run)
}

// A hero arriving while the lift is busy appears on its deck (and is waited for: boons_test.odin); one arriving
// while it waits arrives beside the party, as always.
@(test)
a_late_joiner_mid_ride_lands_on_the_deck :: proc(t: ^testing.T) {
	run := quiet_run(1)
	defer headless.run_end(&run)
	state := &run.simulation.state
	phys := run.simulation.world.phys
	board(&run)
	testing.expect(t, until_lift(&run, .Descending), "it goes down")
	play(&run, {}, g.LIFT_RIDE_S / 2)
	headless.run_seat(&run, 1, 2)
	headless.run_step(&run)
	joiner := sim.slot_data(run.simulation, 1)
	testing.expectf(t, g.on_deck(phys, &state.lift, joiner.pos), "it lands on the deck (at %v)", joiner.pos)
	testing.expect(t, until_lift(&run, .Choosing, g.LIFT_RIDE_S), "it reaches the bottom")
	play(&run, {}, 0.5)
	testing.expectf(t, g.on_deck(phys, &state.lift, joiner.pos), "it rode down (at %v)", joiner.pos)
	scenarios.expect_synced(t, &run)
}

// Once everyone has picked, the party descends: the depth up, the hoard's gold in the purse, the next floor entered
// with everyone up (the downed at REVIVE_HP, the others at their health), and the save made there.
@(test)
the_party_descends_with_the_hoard :: proc(t: ^testing.T) {
	run := quiet_run(2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	saved := run.simulation.setup
	hurt(&run, 0, 30)
	hurt(&run, 1, g.HERO_HP)
	gold := state.gold
	board(&run)
	testing.expect(t, until_lift(&run, .Choosing), "it reaches the bottom")
	headless.run_command(&run, 0, g.Command_Pick_Boon{0})
	headless.run_command(&run, 1, g.Command_Pick_Boon{0})
	testing.expect_value(t, state.depth, 1)
	testing.expect_value(t, state.gold, gold + g.HOARD_GOLD)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Waiting) // the next floor's
	descended, _ := headless.run_last_event(&run, g.Event_Descended)
	testing.expect_value(t, descended, g.Event_Descended{depth = 1, gold = gold + g.HOARD_GOLD})
	first, second := sim.slot_data(run.simulation, 0), sim.slot_data(run.simulation, 1)
	testing.expect_value(t, first.hp, g.HERO_HP - 30 + g.hero_max_hp(first) - g.HERO_HP) // a Thick_Hide pick heals
	testing.expect_value(t, second.action, g.Action.None)
	testing.expect_value(t, second.hp, g.REVIVE_HP)
	testing.expect(t, sim.save_changed(run.simulation, run.simulation.tick, &saved), "the descent saves")
	testing.expect_value(t, saved.depth, 1)
	testing.expect_value(t, saved.floor, g.FLOOR_ORDER[1 % len(g.FLOOR_ORDER)])
	testing.expect_value(t, saved.gold, gold + g.HOARD_GOLD)
	scenarios.expect_synced(t, &run)
}

// A Continue starts at the save's depth (and a save of an older build, without one, at none).
@(test)
a_continue_starts_at_its_depth :: proc(t: ^testing.T) {
	run := headless.run_begin(
		&g.GAME,
		1,
		g.Setup{version = g.SAVE_VERSION, floor = .Floor_1, lives = 1, depth = 2},
		seated = 1,
	)
	defer headless.run_end(&run)
	testing.expect_value(t, run.simulation.state.depth, 2)
	scenarios.expect_synced(t, &run)
}

// A hoard dropped over the deck's edge doesn't board: part of its box hangs past the deck (each corner of its bottom
// must be over it), though the sensor over the deck sees it.
@(test)
a_hoard_over_the_edge_doesnt_board :: proc(t: ^testing.T) {
	run := quiet_run(1)
	defer headless.run_end(&run)
	state := &run.simulation.state
	phys := run.simulation.world.phys
	board(&run)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Boarding)
	edge := physics.body_world_point(phys, state.lift.body, {g.LIFT_HALF.x, g.LIFT_HALF.y + g.HOARD_HALF.y, 0})
	physics.body_teleport(phys, state.hoard.body, edge + {-0.4, 0, 0}) // its +X end 0.4 m past the edge
	headless.run_pin(&run)
	play(&run, {}, 0.25)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Waiting)
	scenarios.expect_synced(t, &run)
}

// A wipe during the haul starts the floor over: the holds let go, the hoard back at its marker at rest, the haul's
// surges off, the lift waiting at the top.
@(test)
a_wipe_mid_haul_starts_the_haul_over :: proc(t: ^testing.T) {
	run := quiet_run(1)
	defer headless.run_end(&run)
	state := &run.simulation.state
	phys := run.simulation.world.phys
	beside_handle(&run, 0, .Left)
	press(&run, 0, .Interact)
	walk(&run, {0}, {0, 127}, 1)
	testing.expect(t, state.hoard.hauled, "the haul began")
	hurt(&run, 0, g.HERO_HP)
	for _ in 0 ..< 2 * g.WIPE_TICKS {
		if headless.run_events(&run, g.Event_Floor_Restarted) > 0 do break
		headless.run_step(&run)
	}
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 1)
	testing.expect_value(t, state.hoard.haulers, [2]sim.Player{})
	testing.expect(t, !state.hoard.hauled, "the haul's surges are off")
	marker := floor_of(&run).places.hoard.pos + {0, g.HOARD_HALF.y, 0}
	at := physics.body_position(phys, state.hoard.body)
	testing.expectf(t, dmath.length(at - marker) < 0.02, "the hoard back at its marker (%v)", at)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Waiting)
	scenarios.expect_synced(t, &run)
}

// While the lift is up, its deck is floor like any: a minion walks onto it and strikes a hero standing in its middle
// (the navigation keeps the deck's tile; only once the deck has gone down are minions kept off the shaft).
@(test)
a_minion_reaches_a_hero_on_the_deck :: proc(t: ^testing.T) {
	run := quiet_run(1)
	defer headless.run_end(&run)
	place_hero(&run, 0, deck_point(&run, {}))
	place_minion(&run, deck_point(&run, {g.LIFT_HALF.x + 2.5, 0, 0}), .Chase, {-1, 0})
	for _ in 0 ..< 6 * g.TICK_HZ {
		if headless.run_events(&run, g.Event_Hero_Hurt) > 0 do break
		headless.run_step(&run)
	}
	testing.expect(t, headless.run_events(&run, g.Event_Hero_Hurt) > 0, "the minion struck the hero on the deck")
	scenarios.expect_synced(t, &run)
}

// Whether slot `slot`'s hero stands clear of the hoard's box and of every other hero, on the deck.
@(private = "file")
expect_clear :: proc(t: ^testing.T, run: ^headless.Run(g.Game), slot: int, loc := #caller_location) {
	phys := run.simulation.world.phys
	hero := sim.slot_data(run.simulation, slot)
	local := physics.body_local_point(phys, run.simulation.state.hoard.body, hero.pos + {0, 1, 0})
	reach := g.HERO_RADIUS - 0.02
	inside := abs(local.x) < g.HOARD_HALF.x + reach && abs(local.z) < g.HOARD_HALF.z + reach
	testing.expectf(t, !inside, "slot %d arrived in the hoard (%v from its middle)", slot, local, loc = loc)
	testing.expectf(
		t,
		g.on_deck(phys, &run.simulation.state.lift, hero.pos),
		"slot %d is on the deck",
		slot,
		loc = loc,
	)
	heroes := sim.iterate_present(&run.simulation.state.players)
	for other, player in sim.next(&heroes) {
		if player == sim.player_in_slot(run.simulation, slot) do continue
		apart := dmath.length(other.pos.xz - hero.pos.xz)
		testing.expectf(
			t,
			apart > 2 * g.HERO_RADIUS - 0.05,
			"slot %d arrived %v m from a hero",
			slot,
			apart,
			loc = loc,
		)
	}
}

// An arrival while the lift is busy appears clear of the hoard and of every hero: the hoard resting on its own slot's
// corner, it takes another place (boarding); its corner taken by a hero, the same (going down).
@(test)
an_arrival_on_the_deck_lands_clear :: proc(t: ^testing.T) {
	run := quiet_run(1)
	defer headless.run_end(&run)
	state := &run.simulation.state
	phys := run.simulation.world.phys
	board(&run)
	on_corner := deck_point(&run, [3]f32{1, 0, -1} * g.LIFT_SLOT_SPREAD + {0, g.HOARD_HALF.y, 0})
	physics.body_teleport(phys, state.hoard.body, on_corner)
	headless.run_pin(&run)
	play(&run, {}, 0.25)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Boarding) // the hoard is still wholly aboard
	headless.run_seat(&run, 1, 2)
	headless.run_step(&run)
	expect_clear(t, &run, 1)
	testing.expect(t, until_lift(&run, .Descending), "it goes down")
	place_hero(&run, 0, deck_point(&run, [3]f32{-1, 0, 1} * g.LIFT_SLOT_SPREAD)) // on slot 2's corner
	headless.run_seat(&run, 2, 3)
	headless.run_step(&run)
	expect_clear(t, &run, 2)
	scenarios.expect_synced(t, &run)
}

// Let go of mid-carry, the hoard keeps its carried weight while it slides on, and weighs HOARD_REST_MASS only once it
// has settled: a chest dropped at speed never shoves a hero as a wall would.
@(test)
a_dropped_hoard_settles_before_it_weighs_its_rest :: proc(t: ^testing.T) {
	run := quiet_run(3)
	defer headless.run_end(&run)
	state := &run.simulation.state
	phys := run.simulation.world.phys
	beside_handle(&run, 0, .Left)
	beside_handle(&run, 1, .Right)
	press_all(&run, {0, 1})
	walk(&run, {0, 1}, {0, 127}, 1.2) // carried at speed, south
	at := physics.body_position(phys, state.hoard.body)
	ahead := [3]f32{at.x, 0, at.z + g.HOARD_HALF.z + g.HERO_RADIUS + 0.3} // a hero just ahead of it
	place_hero(&run, 2, ahead, {0, -1})
	moving: [g.PLAYERS]g.Input
	for slot in 0 ..< 2 do moving[slot] = {
		move_z  = 127,
		buttons = {.Interact},
	}
	headless.run_step(&run, moving) // both let go, still walking
	testing.expect_value(t, state.hoard.haulers, [2]sim.Player{})
	testing.expect(t, !state.hoard.resting, "let go at speed, it isn't at rest")
	mass := physics.body_mass(phys, state.hoard.body)
	testing.expectf(t, abs(mass - g.HOARD_MASS) < 1, "it slides on at its carried weight (%v kg)", mass)
	play(&run, {}, 2)
	testing.expect(t, state.hoard.resting, "settled")
	mass = physics.body_mass(phys, state.hoard.body)
	testing.expectf(t, abs(mass - g.HOARD_REST_MASS) < 1, "settled, it weighs its rest (%v kg)", mass)
	shoved := dmath.length(sim.slot_data(run.simulation, 2).pos.xz - ahead.xz)
	testing.expectf(t, shoved < 1, "the hero ahead was shoved %v m", shoved)
	scenarios.expect_synced(t, &run)
}

// The sensor over the deck tells a hoard hanging over the edge (it sees it, not wholly over the deck: the HUD's
// "wholly on the lift") from one not on the lift at all (it doesn't see it).
@(test)
the_deck_sees_a_hoard_hanging_over_its_edge :: proc(t: ^testing.T) {
	run := quiet_run(1)
	defer headless.run_end(&run)
	state := &run.simulation.state
	phys := run.simulation.world.phys
	overlaps := &run.simulation.world.overlaps
	seen, wholly := g.hoard_on_deck(phys, &state.hoard, &state.lift, overlaps)
	testing.expect(t, !seen && !wholly, "at its marker, the hoard is nowhere near the lift")
	physics.body_teleport(phys, state.hoard.body, deck_point(&run, {g.LIFT_HALF.x - 0.4, g.HOARD_HALF.y, 0}))
	headless.run_pin(&run)
	play(&run, {}, 0.25)
	seen, wholly = g.hoard_on_deck(phys, &state.hoard, &state.lift, overlaps)
	testing.expect(t, seen && !wholly, "over the edge: on the lift, not wholly")
	beside := deck_point(&run, {g.LIFT_HALF.x + g.HOARD_HALF.x + 1, g.HOARD_HALF.y, 0})
	physics.body_teleport(phys, state.hoard.body, beside)
	headless.run_pin(&run)
	play(&run, {}, 0.25)
	seen, wholly = g.hoard_on_deck(phys, &state.hoard, &state.lift, overlaps)
	testing.expect(t, !seen, "beside the deck: not on the lift")
	scenarios.expect_synced(t, &run)
}

// A hauler bumps the chest as any body does: walking into it from its handle's end, it pushes it along and never
// walks into its box (left free to, it stood on the chest, wedged).
@(test)
a_hauler_doesnt_walk_into_the_hoard :: proc(t: ^testing.T) {
	run := quiet_run(1)
	defer headless.run_end(&run)
	state := &run.simulation.state
	phys := run.simulation.world.phys
	beside_handle(&run, 0, .Left)
	press(&run, 0, .Interact)
	hero := sim.slot_data(run.simulation, 0)
	deepest := -max(f32)
	for _ in 0 ..< g.TICK_HZ {
		headless.run_step(&run, [g.PLAYERS]g.Input{0 = {move_x = 127}})
		local := physics.body_local_point(phys, state.hoard.body, hero.pos + {0, 0.5, 0})
		deepest = dmath.max(deepest, local.x + g.HOARD_HALF.x + g.HERO_RADIUS) // the capsule's reach into the box
	}
	testing.expectf(t, deepest < 0.1, "the hauler went %v m into the chest", deepest)
	scenarios.expect_synced(t, &run)
}

// Two haulers carry the hoard clear at HOARD_CARRY_SPEED all the way, never dropping to a drag: their drive's cap
// (HOARD_GROUND_FORCE) lets the chest hold them back as they get going, so the holds stay on lifting.
@(test)
two_haulers_carry_it_clear_all_the_way :: proc(t: ^testing.T) {
	run := quiet_run(2)
	defer headless.run_end(&run)
	beside_handle(&run, 0, .Left)
	beside_handle(&run, 1, .Right)
	press_all(&run, {0, 1})
	play(&run, {}, 0.5)
	walk(&run, {0, 1}, {0, 127}, 1) // getting going
	carry := g.HOARD_CARRY_SPEED * g.CLASS_SPECS[sim.slot_data(run.simulation, 0).class].max_speed
	dragged := 0
	for _ in 0 ..< g.TICK_HZ {
		headless.run_step(&run, [g.PLAYERS]g.Input{0 = {move_z = 127}, 1 = {move_z = 127}})
		dragged += int(dmath.length(sim.slot_data(run.simulation, 0).vel.xz) < 0.9 * carry)
	}
	testing.expectf(t, dragged == 0, "dragged %d ticks of the carry", dragged)
	scenarios.expect_synced(t, &run)
}

// A real haul aboard: one hauler drags the hoard from the floor onto the deck, lets go, still aboard, and the lift
// boards and goes down.
@(test)
a_hauler_drags_the_hoard_aboard :: proc(t: ^testing.T) {
	run := quiet_run(1)
	defer headless.run_end(&run)
	state := &run.simulation.state
	phys := run.simulation.world.phys
	place_prop(&run, HEAVY_CRATE, spawn_of(&run, 3) + {0, 0, 2.5}) // out of the way
	physics.body_teleport(phys, state.hoard.body, deck_point(&run, {g.LIFT_HALF.x + 2.5, g.HOARD_HALF.y, 0}))
	headless.run_pin(&run)
	play(&run, {}, 0.5)
	beside_handle(&run, 0, .Left)
	press(&run, 0, .Interact)
	for _ in 0 ..< 4 * g.TICK_HZ {
		local := physics.body_local_point(phys, state.lift.body, physics.body_position(phys, state.hoard.body))
		if local.x < 0.4 do break
		headless.run_step(&run, [g.PLAYERS]g.Input{0 = {move_x = -127}})
	}
	press(&run, 0, .Interact)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).handle, g.Haul_Handle.None)
	testing.expect(t, until_lift(&run, .Descending, 3), "dragged aboard, it boards and goes down")
	scenarios.expect_synced(t, &run)
}

// A hero aboard down, the one hero up leaving mid-ride wipes nobody: the ride goes on to the boons.
@(test)
the_ride_never_wipes :: proc(t: ^testing.T) {
	run := quiet_run(2)
	defer headless.run_end(&run)
	hurt(&run, 1, g.HERO_HP)
	board(&run)
	testing.expect(t, until_lift(&run, .Descending), "it goes down")
	headless.run_seat(&run, 0, 0) // the one up leaves: everyone present is down
	testing.expect(t, until_lift(&run, .Choosing, g.LIFT_RIDE_S + g.WIPE_S), "it reaches the bottom")
	play(&run, {}, g.WIPE_S + 0.5)
	testing.expect_value(t, headless.run_events(&run, g.Event_Party_Wiped), 0)
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 0)
	scenarios.expect_synced(t, &run)
}

// Strong_Back takes off some of a haul's slowdown: one hauler with a rank drags at back_speed of HOARD_DRAG_SPEED.
@(test)
strong_back_hauls_faster :: proc(t: ^testing.T) {
	run := quiet_run(1)
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 0)
	hero.boons[.Strong_Back] = 1
	beside_handle(&run, 0, .Left)
	press(&run, 0, .Interact)
	play(&run, {}, 0.5)
	walk(&run, {0}, {0, 127}, 1)
	want := g.CLASS_SPECS[hero.class].max_speed * g.back_speed(hero, g.HOARD_DRAG_SPEED)
	testing.expect(t, want > g.CLASS_SPECS[hero.class].max_speed * g.HOARD_DRAG_SPEED, "faster")
	testing.expectf(
		t,
		abs(dmath.length(hero.vel.xz) - want) < 0.1,
		"it hauls at %v, not %v",
		dmath.length(hero.vel.xz),
		want,
	)
	scenarios.expect_synced(t, &run)
}

// A downed hero's ragdoll rides the deck down with the party: aboard (its pelvis over the deck) from the boarding to
// the bottom, never left at the top nor fallen out of the level (RAGDOLL_KILL_DEPTH is far below the shaft's
// LIFT_DROP).
@(test)
a_downed_body_rides_the_lift_down :: proc(t: ^testing.T) {
	run := quiet_run(2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	hurt(&run, 1, g.HERO_HP)
	play(&run, {}, 0.5)
	board(&run)
	downed := sim.slot_data(run.simulation, 1)
	testing.expect(t, g.ragdolled(downed), "the downed hero lies as a ragdoll")
	testing.expect(t, until_lift(&run, .Descending), "the lift goes down with the downed aboard")
	top := downed.pos.y
	testing.expect(t, until_lift(&run, .Choosing), "and reaches the bottom")
	testing.expect(t, g.ragdolled(downed), "the body still lies as a ragdoll")
	testing.expect(t, g.on_deck(run.simulation.world.phys, &state.lift, downed.pos), "on the deck at the bottom")
	testing.expectf(t, top - downed.pos.y > g.LIFT_DROP - 0.3, "it went down %v m", top - downed.pos.y)
	scenarios.expect_synced(t, &run)
}

// A hero downed on the lift arrives up: struck down on the deck as the lift boards, its ragdoll rides down with the
// party, it picks its boon lying there, and on the next floor it stands at its spawn at REVIVE_HP, its ragdoll gone and
// its capsule back in the world, walking on its own stick.
@(test)
a_hero_downed_on_the_lift_arrives_up :: proc(t: ^testing.T) {
	run := quiet_run(2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	board(&run)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Boarding)
	hurt(&run, 1, g.HERO_HP) // boarding: the floor isn't won yet
	downed := sim.slot_data(run.simulation, 1)
	testing.expect(t, g.ragdolled(downed), "down on the deck, as a ragdoll")
	testing.expect(t, until_lift(&run, .Choosing), "the lift goes down with it aboard")
	testing.expect_value(t, downed.action, g.Action.Down)
	headless.run_command(&run, 0, g.Command_Pick_Boon{0})
	headless.run_command(&run, 1, g.Command_Pick_Boon{0})
	testing.expect_value(t, state.depth, 1)
	testing.expect_value(t, downed.action, g.Action.None)
	testing.expect_value(t, downed.hp, g.REVIVE_HP)
	testing.expect(t, !g.ragdolled(downed), "it arrives on its feet, no ragdoll")
	testing.expect(
		t,
		physics.body_is_enabled(run.simulation.world.phys, downed.body.body),
		"its capsule is in the world",
	)
	from := downed.pos
	play(&run, {1 = {move_x = 127}}, 0.5)
	testing.expectf(t, downed.pos.x > from.x + 1, "it walks on its own stick: %v from %v", downed.pos, from)
	scenarios.expect_synced(t, &run)
}

// A Barbarian heaves a downed ally's ragdoll and throws it onto the waiting deck from across the room, then walks
// aboard itself: the body comes down on the deck and slides into the hoard resting across its far edge (a thrown body
// lands some ten metres off at a throw's speed, and would slide on off the 4 m deck) and lies there, and with the hoard
// aboard the lift boards (a downed hero aboard counts as aboard, however it got there).
@(test)
a_heaved_ragdoll_thrown_onto_the_deck_boards :: proc(t: ^testing.T) {
	run := quiet_run(2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	phys := run.simulation.world.phys
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Barbarian})
	deck := deck_point(&run, {})
	// the hoard across the deck's far edge, its long side to the throw: what stops the body sliding off it
	physics.body_teleport(
		phys,
		state.hoard.body,
		deck + {g.HOARD_HALF.z - g.LIFT_HALF.x + 0.05, g.HOARD_HALF.y, 1.1},
		QUARTER_TURN,
	)
	thrower := deck + {THROW_FROM, 0, 1.1} // down the corridor east of the west room, facing the deck
	place_prop(&run, HEAVY_CRATE, spawn_of(&run, 3)) // out of the throw's way
	place_hero(&run, 0, thrower, {-1, 0})
	place_hero(&run, 1, thrower + {-GRAB_AHEAD, 0, 0})
	headless.run_pin(&run)
	hurt(&run, 1, g.HERO_HP)
	press(&run, 0, .Ability)
	ally := sim.slot_data(run.simulation, 1)
	testing.expect_value(t, ally.heave, g.Heave_Phase.Held)
	play(&run, {}, 0.5)
	press(&run, 0, .Attack)
	for _ in 0 ..< 3 * g.TICK_HZ {
		if ally.heave == .None do break
		headless.run_step(&run)
	}
	testing.expect_value(t, headless.run_events(&run, g.Event_Heave_Landed), 1)
	play(&run, {}, 1.5)
	testing.expectf(t, g.on_deck(phys, &state.lift, ally.pos), "the body came to rest on the deck: %v", ally.pos)
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Waiting) // the Barbarian is still off it
	place_hero(&run, 0, deck_point(&run, {1, 0, 1} * g.LIFT_SLOT_SPREAD))
	testing.expect(t, until_lift(&run, .Boarding, 1), "the lift boards with the thrown body aboard")
	scenarios.expect_synced(t, &run)
}

// A lone hauler drags the hoard toward the vault's gate, from Floor 1's marker and from a metre past the vault's tile
// seam (x = 28), whenever its grab comes (every tick of the first LONE_HAUL_TIMINGS after it is put beside the handle:
// the hoard's rest and the hauler's settling at every phase): the dragged end slides over the floor tiles' seams,
// never catching on one, so the hold never slips and the hoard comes LONE_HAUL_DISTANCE toward the gate (shut: the
// hauler stops at it).
@(test)
a_lone_hauler_drags_the_hoard_toward_the_gate :: proc(t: ^testing.T) {
	gate_x := f32(0)
	for from_seam in ([]bool{false, true}) do for timing in 0 ..= LONE_HAUL_TIMINGS {
		run := quiet_run(1, in_vault = true)
		defer headless.run_end(&run)
		state := &run.simulation.state
		phys := run.simulation.world.phys
		gate_x = sim.slice(&floor_of(&run).places.gates)[0].pos.x
		if from_seam {
			physics.body_teleport(phys, state.hoard.body, {29, g.HOARD_HALF.y, -2})
			headless.run_pin(&run)
		}
		beside_handle(&run, 0, .Left)
		for _ in 0 ..< timing do headless.run_step(&run)
		press(&run, 0, .Interact)
		hero := sim.slot_data(run.simulation, 0)
		from := physics.body_position(phys, state.hoard.body)
		walk(&run, {0}, {-127, 0}, 3)
		moved := from.x - physics.body_position(phys, state.hoard.body).x
		slips := headless.run_events(&run, g.Event_Hoard_Dropped) // nothing but a slip lets go here
		ok := slips == 0 && hero.handle == .Left && moved > LONE_HAUL_DISTANCE
		testing.expectf(t, ok, "from the seam %v, grabbed %d ticks in: %d slips, dragged %v m", from_seam, timing, slips, moved)
		if !ok do return
	}
	testing.expect(t, gate_x != 0, "Floor 1 has its vault gate")
}

// The lone haul's grab timings (ticks), and how far it drags the hoard in three seconds at least (metres).
LONE_HAUL_TIMINGS :: 48
LONE_HAUL_DISTANCE :: f32(2.5)

// Boarding (dev_board) while a Barbarian heaves a downed ally, held or thrown, lets the heave go first: the Barbarian
// stands free, the ally lies anew on the deck, nobody's heave, and no joint is left on the bones that went (no crash,
// check_refs after every restore).
@(test)
boarding_lets_go_of_a_heave :: proc(t: ^testing.T) {
	for thrown in ([]bool{false, true}) {
		run := quiet_run(2)
		defer headless.run_end(&run)
		headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Barbarian})
		barbarian := sim.slot_data(run.simulation, 0)
		ally := sim.slot_data(run.simulation, 1)
		place_hero(&run, 0, {6, 0, -4}, {1, 0})
		place_hero(&run, 1, {6 + GRAB_AHEAD, 0, -4})
		hurt(&run, 1, g.HERO_HP)
		press(&run, 0, .Ability)
		testing.expect_value(t, ally.heave, g.Heave_Phase.Held)
		if thrown {
			press(&run, 0, .Attack)
			for _ in 0 ..< g.THROW_WINDUP_TICKS do headless.run_step(&run)
			testing.expect_value(t, ally.heave, g.Heave_Phase.Thrown)
		}
		board(&run)
		if !thrown do testing.expect_value(t, barbarian.action, g.Action.None) // let go of, not still heaving
		testing.expect_value(t, barbarian.heaved, g.Heaved{})
		testing.expect_value(t, ally.heave, g.Heave_Phase.None)
		testing.expect(t, g.ragdolled(ally), "the ally lies as a ragdoll")
		testing.expect(t, g.on_deck(run.simulation.world.phys, &run.simulation.state.lift, ally.pos), "on the deck")
		play(&run, {}, 0.5)
		scenarios.expect_synced(t, &run)
	}
}

// An arrival never lands in the hoard: with the party's hero standing an arrival ring out from the hoard, in the
// direction the arriving slot tries first (ARRIVAL_SLOT_TURN), the arrival stands clear of HOARD_FOOTPRINT.
@(test)
an_arrival_lands_clear_of_the_hoard :: proc(t: ^testing.T) {
	run := quiet_run(1)
	defer headless.run_end(&run)
	phys := run.simulation.world.phys
	hoard := [3]f32{8, 0, -7} // the great hall's open floor
	physics.body_teleport(phys, run.simulation.state.hoard.body, hoard + {0, g.HOARD_HALF.y, 0})
	dir := dmath.DIR8[g.ARRIVAL_SLOT_TURN % len(dmath.DIR8)] // slot 1's first
	place_hero(&run, 0, hoard - [3]f32{dir.x, 0, dir.y} * g.ARRIVAL_RING)
	headless.run_seat(&run, 1, 2)
	headless.run_step(&run)
	arrived := sim.slot_data(run.simulation, 1)
	apart := dmath.length(arrived.pos.xz - hoard.xz)
	testing.expectf(t, apart >= g.HERO_RADIUS + g.HOARD_FOOTPRINT, "arrived %v m from the hoard's middle", apart)
	scenarios.expect_synced(t, &run)
}

// The ways the hoard is hauled, each level's, as points along the floor: Floor 1's out of the vault through the
// spike gallery to the lift, and out of it through the passage (the barricade broken) to the lift; the workshop's out
// of its vault, between its plates, to its lift; the Ossuary's (Floor 2) out of its vault across the hall to the lift;
// the Deep Halls' (Floor 3) out of its vault, past the antechamber's plates, through the shortcut (the barricade
// broken) to the lift.
@(private = "file")
HAUL_LANES := [?]struct {
	level:  g.Level_Id,
	what:   string,
	points: [][2]f32,
} {
	{
		.Floor_1,
		"the gallery",
		{{30, -2}, {21.5, -2}, {16, -2.2}, {12, -3.6}, {4, -3.6}, {0, -2}, {-8, -2}, {-12, -3}, {-16, -4}},
	},
	{
		.Floor_1,
		"the passage",
		{{30, -2}, {21.5, -2}, {20.7, -2.6}, {20.7, -6}, {14.5, -6}, {13, -4.2}, {12, -3.6}, {4, -3.6}},
	},
	{.Workshop, "the workshop", {{-6, -6.4}, {-6, 0.2}, {1, 0.2}, {2, 2}}},
	{.Floor_2, "the Ossuary's hall", {{2, 16.5}, {2, 8}, {-2, 2}}},
	{.Floor_3, "the Deep Halls' shortcut", {{6, 20.5}, {6, 13}, {0, 10}, {-6, 10}}},
}

// Every haul lane (HAUL_LANES) is clear for a dragged hoard all along: its box, lengthwise along the lane (as a hauler
// drags it), every HAUL_LANE_STEP of the way, meets no wall or low cover from a hand over the floor up, and no plate's
// slab under it (a dragged end catches on the slab's edge: a plate belongs off the hoard's lanes).
@(test)
every_haul_lane_is_clear :: proc(t: ^testing.T) {
	for lane in HAUL_LANES {
		run := headless.run_begin(&g.GAME, 1, g.Setup{floor = lane.level})
		defer headless.run_end(&run)
		phys := run.simulation.world.phys
		out: [dynamic]physics.Overlap
		defer delete(out)
		plates := sim.slice(&floor_of(&run).places.plates)
		blocked := false
		for k in 0 ..< len(lane.points) - 1 {
			a, b := lane.points[k], lane.points[k + 1]
			along := dmath.normalize(b - a)
			across := [2]f32{-along.y, along.x}
			steps := int(dmath.length(b - a) / HAUL_LANE_STEP) + 1
			for s in 0 ..= steps {
				at := a + (b - a) * (f32(s) / f32(steps))
				corners: [8][3]f32
				for &corner, c in corners {
					x := (f32(c & 1) * 2 - 1) * g.HOARD_HALF.x
					z := (f32((c >> 1) & 1) * 2 - 1) * g.HOARD_HALF.z
					y := f32(c >> 2) * 2 * g.HOARD_HALF.y
					foot := along * x + across * z
					corner = {foot.x, y, foot.y}
				}
				box := physics.make_proxy(corners[:], 0)
				filter := physics.Filter {
					category = g.CAT_HOARD,
					mask     = g.CAT_WALL | g.CAT_LOW,
				}
				physics.world_overlap_shape(phys, {at.x, 0.05, at.y}, box, &out, filter)
				if len(out) > 0 {
					testing.expectf(t, false, "%s: the hoard meets a wall at %v", lane.what, at)
					blocked = true
				}
				for plate in plates {
					for corner in corners {
						point := [3]f32{at.x + corner.x, 0, at.y + corner.z}
						if g.within_square(plate.pos, plate.rot, g.PLATE_HALF.x, point) {
							testing.expectf(t, false, "%s: the hoard drags over the plate at %v", lane.what, plate.pos)
							blocked = true
							break
						}
					}
				}
				if blocked do break
			}
			if blocked do break
		}
	}
}

// How far apart the haul lanes are checked (metres).
HAUL_LANE_STEP :: f32(0.1)

// Boarding (dev_board) lets go of every hold: a hauler's handle and a carried prop, as a heave's (above), so nobody
// stands on the deck still holding a hoard or a crate the board moved.
@(test)
boarding_lets_go_of_every_hold :: proc(t: ^testing.T) {
	run := quiet_run(2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	beside_handle(&run, 0, .Left)
	press(&run, 0, .Interact)
	carrier := sim.slot_data(run.simulation, 1)
	place_hero(&run, 1, {2.4, 0, -4}, {0, 1}) // facing the crate by the corridor's mouth
	place_prop(&run, CRATE, {2.4, 0, -2.9})
	press(&run, 1, .Interact)
	testing.expect(t, sim.slot_data(run.simulation, 0).handle == .Left && carrier.held != {}, "a hauler and a carrier")
	board(&run)
	testing.expect_value(t, state.hoard.haulers, [2]sim.Player{})
	testing.expect_value(t, sim.slot_data(run.simulation, 0).handle, g.Haul_Handle.None)
	testing.expect_value(t, carrier.held, sim.Handle(g.Prop){})
	scenarios.expect_synced(t, &run)
}
