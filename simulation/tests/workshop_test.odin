// The mechanisms' shared test support and the workshop's own suite: the workshop (game/levels/workshop.tscn) is a hall
// holding one of each mechanism, and a hoard in a vault and a lift (a whole haul to the descent in a small room), which
// every mechanism test plays on (plates_test.odin, gates_test.odin, barricades_test.odin, traps_test.odin), sync-tested
// as every rule test is, so each also rolls back over what it checks: a plate pressed, a gate moving, a barricade's
// break, the spikes rising. Its pieces are found by their marker order in the floor's Places, never by numbers copied
// out of the level.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// The workshop's mechanisms by marker order (game/levels/workshop.tscn): its plates, gates and traps; and its props.
VAULT_WEST :: 0 // the vault gate's two plates
VAULT_EAST :: 1
STORE_PLATE :: 2 // the store gate's
SPIKES_PLATE :: 3 // the plated spikes'
VAULT_GATE :: 0 // need 2, latched
STORE_GATE :: 1 // need 1: open while its plate is pressed
SPIKES :: 0 // on the clock alone, phase 0
PLATED_SPIKES :: 1 // on the clock, phase 1.5 s, and while their plate is pressed
ROLLER :: 2
WORKSHOP_CRATE :: 0
WORKSHOP_BARREL :: 1
WORKSHOP_HEAVY_CRATE :: 2

// The workshop's Setup.
WORKSHOP :: g.Setup {
	floor = .Workshop,
}

// A sync-tested run on the workshop with `seated` heroes, its minions gone and its surges held off (hold_surges), so a
// test sees only the skeletons it raises; `window` is how far back each step is re-simulated.
workshop :: proc(seated := 1, seed: u64 = 1, window: u32 = 8) -> headless.Run(g.Game) {
	run := headless.run_begin(&g.GAME, seed, WORKSHOP, window, seated)
	hold_surges(&run)
	return run
}

// The run's next surge never comes (its timer runs to the end of game time), and the run is pinned there.
hold_surges :: proc(run: ^headless.Run(g.Game)) {
	state := &run.simulation.state
	state.surge = {
		start  = state.clock.time,
		target = max(sim.Game_Time),
	}
	sim.despawn_all(&state.minions)
	headless.run_pin(run)
}

// The plate of marker index `index` among the floor's plates (they are made in marker order), and its handle.
plate_at :: proc(run: ^headless.Run(g.Game), index: int) -> (^g.Plate, sim.Handle(g.Plate)) {
	plate, handle, _ := sim.item_at(&run.simulation.state.plates, index)
	return plate, handle
}

// The gate of marker index `index` among the floor's gates, and its handle.
gate_at :: proc(run: ^headless.Run(g.Game), index: int) -> (^g.Gate, sim.Handle(g.Gate)) {
	gate, handle, _ := sim.item_at(&run.simulation.state.gates, index)
	return gate, handle
}

// The trap of marker index `index` among the floor's traps, and its handle.
trap_at :: proc(run: ^headless.Run(g.Game), index: int) -> (^g.Trap, sim.Handle(g.Trap)) {
	trap, handle, _ := sim.item_at(&run.simulation.state.traps, index)
	return trap, handle
}

// Where the plate of marker index `index` stands on the floor.
plate_spot :: proc(run: ^headless.Run(g.Game), index: int) -> [3]f32 {
	return sim.slice(&floor_of(run).places.plates)[index].pos
}

// Where the gate of marker index `index` stands on the floor (its grille's foot, in the middle).
gate_spot :: proc(run: ^headless.Run(g.Game), index: int) -> [3]f32 {
	return sim.slice(&floor_of(run).places.gates)[index].pos
}

// How high the gate of marker index `index` is lifted (metres).
lift_of :: proc(run: ^headless.Run(g.Game), index: int) -> f32 {
	gate, _ := gate_at(run, index)
	return g.gate_lift(run.simulation.world.phys, gate)
}

// Moves the prop of marker `index` to fall onto whatever is under `point` (a plate's slab, the floor) from a hand above
// it, unturned and awake, and pins the run there; it lands and settles in the next ticks.
drop_prop_on :: proc(run: ^headless.Run(g.Game), index: int, point: [3]f32) {
	prop, _ := prop_at(run, index)
	centre := point + {0, g.PROP_SPECS[prop.kind].half.y + 0.25, 0}
	physics.body_teleport(run.simulation.world.phys, prop.body, centre)
	physics.body_set_awake(run.simulation.world.phys, prop.body, true) // a teleport leaves a sleeper asleep in the air
	headless.run_pin(run)
}

// The workshop's scripted party rolls back every tick: its plates, gates, barricade and traps under the standard
// scenarios, as Floor 1's run is (suite_test.odin).
WORKSHOP_SUITE := scenarios.Suite(g.Game) {
	game    = &g.GAME,
	players = g.PLAYERS,
	seed    = 42,
	ticks   = scenarios.LONG ? 3600 : 600,
	setup   = WORKSHOP,
}

// The workshop's reference run (unified/src/headless/README.md, Reference runs): the scripted party in the hall for
// 1200 ticks, snapshotted midway; every platform must reproduce the plates' and gates' joints, the spikes' sensors and
// the roller's kinematic drive bit for bit.
WORKSHOP_REFERENCE :: scenarios.Reference {
	seed          = 7,
	players       = 4,
	ticks         = 1200,
	snapshot_tick = 600,
	setup         = "floor=workshop",
	checkpoints   = {0x3db2f7a1324fa051, 0x70d4762df14fb173, 0x334e79ed0b1dac08, 0x615f35b3f759464f},
	trace         = 0xdbb0d5f70546be4e,
	snapshot      = 0x30a4d42da56b107d,
	log           = 0xc4ff1154da326839,
	compat        = 0xf786f547007783c1,
}

@(test)
the_workshop_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(
		t,
		&g.GAME,
		WORKSHOP_REFERENCE,
	)}
@(test)
the_workshop_rolls_back_every_tick :: proc(t: ^testing.T) {scenarios.rollback_every_tick(t, &WORKSHOP_SUITE)}
@(test)
a_late_joiner_agrees_in_the_workshop :: proc(t: ^testing.T) {scenarios.late_join_agrees(
		t,
		&WORKSHOP_SUITE,
		.Wan,
		CLIENTS - 1,
		scenarios.LONG ? 900 : 300,
	)}

// Every mechanism marker makes its body, in marker order, and two runs make the same ones.
@(test)
the_workshops_mechanisms_are_made_in_marker_order :: proc(t: ^testing.T) {
	first := workshop(seed = 1)
	defer headless.run_end(&first)
	second := workshop(seed = 2)
	defer headless.run_end(&second)
	places := &floor_of(&first).places
	state := &first.simulation.state
	testing.expect_value(t, int(state.plates.count), int(places.plates.count))
	testing.expect_value(t, int(state.gates.count), int(places.gates.count))
	testing.expect_value(t, int(state.barricades.count), int(places.barricades.count))
	testing.expect_value(t, int(state.traps.count), int(places.traps.count))
	for def, i in sim.slice(&places.traps) {
		trap, _ := trap_at(&first, i)
		testing.expect_value(t, trap.kind, def.kind)
	}
	testing.expect_value(t, state.plates, second.simulation.state.plates)
	testing.expect_value(t, state.gates, second.simulation.state.gates)
	testing.expect_value(t, state.traps, second.simulation.state.traps)
	scenarios.expect_synced(t, &first)
}

// Steps slot `slot`'s hero along `waypoints` at a full stick (each reached within 0.4 m on the floor plan), the others
// idle, for at most `seconds`; whether it reached the last.
@(private = "file")
walk_through :: proc(run: ^headless.Run(g.Game), slot: int, waypoints: [][2]f32, seconds: f32) -> bool {
	hero := sim.slot_data(run.simulation, slot)
	next := 0
	for _ in 0 ..< int(seconds * g.TICK_HZ) {
		for next < len(waypoints) && dmath.length(waypoints[next] - hero.pos.xz) < 0.4 do next += 1
		if next == len(waypoints) do return true
		toward := dmath.normalize(waypoints[next] - hero.pos.xz)
		inputs: [g.PLAYERS]g.Input
		inputs[slot].move_x, inputs[slot].move_z = dmath.axis_i8(toward.x), dmath.axis_i8(toward.y)
		headless.run_step(run, inputs)
	}
	return false
}

// The workshop's whole haul, played by the rules: two heroes stand on the vault's plates and its latched gate opens;
// one takes a handle of the hoard and drags it out of the vault, across the hall and onto the lift's deck, and lets
// go; the other walks aboard; the lift boards, goes down, both pick a boon, and the party descends (to the run's next
// floor) with the hoard's gold.
@(test)
the_workshops_haul_reaches_the_descent :: proc(t: ^testing.T) {
	run := workshop(seated = 2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	phys := run.simulation.world.phys
	place_hero(&run, 0, plate_spot(&run, VAULT_WEST))
	place_hero(&run, 1, plate_spot(&run, VAULT_EAST))
	play(&run, {}, 2)
	testing.expectf(
		t,
		lift_of(&run, VAULT_GATE) > g.GATE_PASS,
		"the vault gate is open: %v m",
		lift_of(&run, VAULT_GATE),
	)
	hauler := sim.slot_data(run.simulation, 0)
	left := g.handle_point(phys, &state.hoard, .Left)
	place_hero(&run, 0, {left.x - 0.7, 0, left.z}, {1, 0})
	press(&run, 0, .Interact)
	testing.expect_value(t, hauler.handle, g.Haul_Handle.Left)
	deck := physics.body_position(phys, state.lift.body).xz
	way := [][2]f32{{-7.4, -4.9}, {-6.4, -2.8}, {-6, 0.2}, {deck.x - 1, 0.2}, {deck.x + 0.5, deck.y + 1.6}}
	testing.expect(t, walk_through(&run, 0, way, 20), "the hauler drags the hoard to the lift")
	testing.expect_value(t, hauler.handle, g.Haul_Handle.Left) // held all the way
	press(&run, 0, .Interact)
	place_hero(&run, 1, {deck.x - 1.2, 0, deck.y - 1.2})
	gold := state.gold
	for _ in 0 ..< 8 * g.TICK_HZ {
		if state.lift.phase == .Choosing do break
		headless.run_step(&run)
	}
	testing.expect_value(t, state.lift.phase, g.Lift_Phase.Choosing)
	headless.run_command(&run, 0, g.Command_Pick_Boon{0})
	headless.run_command(&run, 1, g.Command_Pick_Boon{1})
	testing.expect_value(t, state.depth, 1)
	testing.expect_value(t, state.gold, gold + g.HOARD_GOLD)
	testing.expect_value(t, state.level.id, g.FLOOR_ORDER[1 % len(g.FLOOR_ORDER)])
	testing.expect_value(t, headless.run_events(&run, g.Event_Descended), 1)
	scenarios.expect_synced(t, &run)
}
