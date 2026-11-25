// What the rule tests share: playing and pressing on a headless.Run, and putting a hero, a prop or a minion where a
// test needs one (the run is pinned there: a sync-test never restores to before a test changed the state). Places come
// from the floor's markers (World.places), never from numbers copied out of the level.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// Floor 1's props the tests move, by marker order (game/levels/floor_1.tscn): its first barrel, its first room's crate
// and heavy crate.
BARREL :: 0
CRATE :: 2
HEAVY_CRATE :: 3

// The run's active floor (its navigation, places and cap).
floor_of :: proc(run: ^headless.Run(g.Game)) -> ^g.Floor {
	return &run.simulation.world.floors[run.simulation.state.level.id]
}

// Slot `slot`'s hero_spawn on the run's floor.
spawn_of :: proc(run: ^headless.Run(g.Game), slot: int) -> [3]f32 {
	return floor_of(run).places.hero_spawns[slot]
}

// `seconds` of play with these inputs by slot (the seated members present).
play :: proc(run: ^headless.Run(g.Game), inputs: [g.PLAYERS]g.Input, seconds: f32 = 1) {
	for _ in 0 ..< int(seconds * g.TICK_HZ) do headless.run_step(run, inputs)
}

// One tick of slot `slot` pressing `button` with `input`, then one with the button up again (the next press is an
// edge), the other seated slots idle.
press :: proc(run: ^headless.Run(g.Game), slot: int, button: g.Button, input: g.Input = {}) {
	inputs: [g.PLAYERS]g.Input
	inputs[slot] = input
	inputs[slot].buttons += {button}
	headless.run_step(run, inputs)
	inputs[slot].buttons -= {button}
	headless.run_step(run, inputs)
}

// One tick in which slot 0 hurts slot `slot`'s hero for `damage` (Command_Dev_Hurt).
hurt :: proc(run: ^headless.Run(g.Game), slot: int, damage: i16) {
	headless.run_command(run, 0, g.Command_Dev_Hurt{sim.player_in_slot(run.simulation, slot), damage})
}

// The hero faces `want` (to within a Dir2's quantization).
expect_facing :: proc(t: ^testing.T, hero: ^g.Hero, want: [2]f32, loc := #caller_location) {
	testing.expectf(t, dmath.length(hero.facing - want) < 1e-3, "faces %v, not %v", hero.facing, want, loc = loc)
}

// Moves slot `slot`'s hero to stand at `feet`, at rest, facing `facing`, and pins the run there.
place_hero :: proc(run: ^headless.Run(g.Game), slot: int, feet: [3]f32, facing := [2]f32{1, 0}) {
	hero := sim.slot_data(run.simulation, slot)
	physics.character_teleport(run.simulation.world.phys, &hero.body, feet + {0, g.HERO_CENTRE_ABOVE_FEET, 0})
	hero.pos, hero.facing = feet, facing
	headless.run_pin(run)
}

// The prop of marker `index` (the props are made in marker order), and its handle.
prop_at :: proc(run: ^headless.Run(g.Game), index: int) -> (^g.Prop, sim.Handle(g.Prop)) {
	walk := sim.iterate(&run.simulation.state.props)
	for prop, handle in sim.next(&walk) {
		if int(handle.index) == index do return prop, handle
	}
	return nil, {}
}

// Moves the prop of marker `index` to stand at rest on `floor_point`, unturned, and pins the run there.
place_prop :: proc(run: ^headless.Run(g.Game), index: int, floor_point: [3]f32) {
	prop, _ := prop_at(run, index)
	centre := floor_point + {0, g.PROP_SPECS[prop.kind].half.y, 0}
	physics.body_teleport(run.simulation.world.phys, prop.body, centre)
	headless.run_pin(run)
}

// A minion in `phase` on the walkable floor nearest `near`, facing `facing`, pinned there.
place_minion :: proc(
	run: ^headless.Run(g.Game),
	near: [3]f32,
	phase: g.Minion_Phase,
	facing := [2]f32{0, 1},
	pack: u8 = 0,
) -> sim.Handle(g.Minion) {
	spot, on_floor := g.floor_spot(floor_of(run), near, 2)
	assert(on_floor, "a test's minion is off the floor")
	state := &run.simulation.state
	handle, spawned := g.spawn_minion(state, spot.point, spot.poly, facing, phase, state.clock.time, pack)
	assert(spawned, "the minion table is full")
	headless.run_pin(run)
	return handle
}

// Every minion goes (the floor's packs, for a test of its own minions), and the run is pinned.
clear_minions :: proc(run: ^headless.Run(g.Game)) {
	sim.despawn_all(&run.simulation.state.minions)
	headless.run_pin(run)
}
