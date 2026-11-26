// The mechanisms' shared test support and the workshop's own suite: the workshop (game/levels/workshop.tscn) is a hall
// holding one of each mechanism, which every mechanism test plays on (plates_test.odin, gates_test.odin,
// barricades_test.odin, traps_test.odin), sync-tested as every rule test is, so each also rolls back over what it
// checks: a plate pressed, a gate moving, a barricade's break, the spikes rising. Its pieces are found by their marker
// order in the floor's Places, never by numbers copied out of the level.
package test_crypt_crew

import "core:testing"
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
// test sees only the skeletons it raises.
workshop :: proc(seated := 1, seed: u64 = 1) -> headless.Run(g.Game) {
	run := headless.run_begin(&g.GAME, seed, WORKSHOP, seated = seated)
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
	checkpoints   = {0x3dbcdcdd00f8d8e3, 0x83128efebe4b999f, 0xbde12dced09c3998, 0xb30521482fb78e2c},
	trace         = 0x1caf7c6e23b7a364,
	snapshot      = 0x0a3afb225d11b4f1,
	log           = 0xf8ef82b6a54689bd,
	compat        = 0x0b47c5bb7c946b0a,
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
