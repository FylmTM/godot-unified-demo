// The braziers' rule tests (braziers.odin), on the workshop, whose two braziers work its store gate: kindling one by
// holding Interact beside it (BRAZIER_LIGHT_S, twice as fast with two), a blow breaking the kindling off, a fireball
// lighting one (two at once when both are in its reach), the gate counting its braziers lit beside its plates
// pressed, and a lighting bringing the next surge near. Each on a sync-tested run (headless.Run) that ends synced, so
// every lighting here also rolls back.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

// The workshop's braziers by marker order (game/levels/workshop.tscn): both work the store gate.
BRAZIER_WEST :: 0
BRAZIER_EAST :: 1

// Where the brazier of marker index `index` stands (its stand's foot).
brazier_spot :: proc(run: ^headless.Run(g.Game), index: int) -> [3]f32 {
	return sim.slice(&floor_of(run).places.braziers)[index].pos
}

// The brazier of marker index `index` (the table's rows are the floor's markers in order), and its handle.
brazier_at :: proc(run: ^headless.Run(g.Game), index: int) -> (^g.Brazier, sim.Handle(g.Brazier)) {
	brazier, handle, _ := sim.item_at(&run.simulation.state.braziers, index)
	return brazier, handle
}

// A workshop run of `seated` heroes, each standing within BRAZIER_RANGE of the west brazier (south of it, a hand clear
// of its stand and of each other), facing it.
@(private = "file")
at_the_brazier :: proc(seated: int) -> headless.Run(g.Game) {
	run := workshop(seated)
	at := brazier_spot(&run, BRAZIER_WEST)
	for slot in 0 ..< seated {
		beside := [3]f32{f32(slot) - 0.5 * f32(seated - 1), 0, -1.25}
		place_hero(&run, slot, at + beside, dmath.normalize(-beside.xz))
	}
	return run
}

// `slots` hold Interact for `ticks` ticks (its first tick a press, when they weren't holding it already).
@(private = "file")
kindle :: proc(run: ^headless.Run(g.Game), slots: []int, ticks: int) {
	inputs: [g.PLAYERS]g.Input
	for slot in slots do inputs[slot].buttons = {.Interact}
	for _ in 0 ..< ticks do headless.run_step(run, inputs)
}

// Holding Interact beside a brazier lights it after BRAZIER_LIGHT_S of kindling, not a tick sooner: the kindler kindles
// meanwhile (and grabs nothing), then is free again, the brazier lit by it, announced, and no longer a target.
@(test)
a_brazier_lights_after_its_time :: proc(t: ^testing.T) {
	run := at_the_brazier(1)
	defer headless.run_end(&run)
	brazier, _ := brazier_at(&run, BRAZIER_WEST)
	hero := sim.slot_data(run.simulation, 0)
	kindle(&run, {0}, int(g.BRAZIER_LIGHT_TICKS) - 1)
	testing.expect_value(t, hero.action, g.Action.Kindle)
	testing.expect(t, !brazier.lit, "unlit a tick short of its time")
	testing.expect_value(t, brazier.progress, g.BRAZIER_LIGHT_TICKS - 1)
	kindle(&run, {0}, 1)
	testing.expect(t, brazier.lit, "lit at its time")
	testing.expect_value(t, hero.action, g.Action.None)
	testing.expect_value(t, hero.held, sim.Handle(g.Prop){})
	lit, _ := headless.run_last_event(&run, g.Event_Brazier)
	testing.expect(t, lit.lit, "its lighting is announced")
	testing.expect_value(t, lit.player, sim.player_in_slot(run.simulation, 0))
	testing.expect_value(t, brazier.by, sim.player_in_slot(run.simulation, 0))
	defs := sim.slice(&floor_of(&run).places.braziers)
	player := sim.player_in_slot(run.simulation, 0)
	target := g.kindle_target(&run.simulation.state.players, &run.simulation.state.braziers, defs, player)
	testing.expect_value(t, target, sim.Handle(g.Brazier){})
	scenarios.expect_synced(t, &run)
}

// Two kindling one brazier light it twice as fast, the first in slot order its lighter.
@(test)
two_kindle_twice_as_fast :: proc(t: ^testing.T) {
	run := at_the_brazier(2)
	defer headless.run_end(&run)
	brazier, _ := brazier_at(&run, BRAZIER_WEST)
	kindle(&run, {0, 1}, int(g.BRAZIER_LIGHT_TICKS / 2) - 1)
	testing.expect(t, !brazier.lit, "unlit a tick short of half its time")
	kindle(&run, {0, 1}, 1)
	testing.expect(t, brazier.lit, "lit at half its time")
	testing.expect_value(t, brazier.by, sim.player_in_slot(run.simulation, 0))
	scenarios.expect_synced(t, &run)
}

// A blow breaks a kindling off and the brazier loses its progress: holding on doesn't start it again, a new press
// does, from nothing; so does letting go.
@(test)
a_blow_breaks_the_kindling :: proc(t: ^testing.T) {
	run := at_the_brazier(1)
	defer headless.run_end(&run)
	brazier, _ := brazier_at(&run, BRAZIER_WEST)
	hero := sim.slot_data(run.simulation, 0)
	kindle(&run, {0}, 100)
	held := [g.PLAYERS]g.Input {
		0 = {buttons = {.Interact}},
	}
	headless.run_command(&run, held, 0, g.Command_Dev_Hurt{sim.player_in_slot(run.simulation, 0), 10})
	testing.expect_value(t, hero.action, g.Action.None)
	kindle(&run, {0}, 100) // still held: no new press
	testing.expect_value(t, hero.action, g.Action.None)
	testing.expect_value(t, brazier.progress, 0)
	testing.expect(t, !brazier.lit, "the blow broke it off")
	play(&run, {}, 0.1) // let go
	kindle(&run, {0}, int(g.BRAZIER_LIGHT_TICKS) - 1)
	testing.expect(t, !brazier.lit, "a new kindling starts from nothing")
	play(&run, {}, 0.1) // let go a tick before its time ...
	kindle(&run, {0}, int(g.BRAZIER_LIGHT_TICKS) - 1)
	testing.expect(t, !brazier.lit, "... and the progress is lost")
	kindle(&run, {0}, 1)
	testing.expect(t, brazier.lit, "lit by a whole kindling")
	scenarios.expect_synced(t, &run)
}

// A Mage's fireball bursting by a brazier lights it at once, the Mage its lighter; one bursting where two braziers are
// in its reach lights both (the east brazier's place moved near the west's for it).
@(test)
a_fireball_lights_braziers :: proc(t: ^testing.T) {
	for both in ([2]bool{false, true}) {
		run := workshop()
		defer headless.run_end(&run)
		west := brazier_spot(&run, BRAZIER_WEST)
		if both do sim.slice(&floor_of(&run).places.braziers)[BRAZIER_EAST].pos = west - {0, 0, 2.5}
		headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Mage})
		from := west - {0, 0, 5.5}
		place_hero(&run, 0, from, {0, 1})
		aim := g.Input {
			aim   = dmath.dir2([2]f32{0, 1}),
			reach = g.reach_steps(5.5),
		}
		press(&run, 0, .Ability, aim)
		play(&run, {0 = aim}, g.FIREBALL_WINDUP_S + g.FIREBALL_FLIGHT_S)
		testing.expect_value(t, headless.run_events(&run, g.Event_Fireball_Burst), 1)
		west_brazier, _ := brazier_at(&run, BRAZIER_WEST)
		east_brazier, _ := brazier_at(&run, BRAZIER_EAST)
		testing.expect(t, west_brazier.lit, "the burst lit the brazier")
		testing.expect_value(t, west_brazier.by, sim.player_in_slot(run.simulation, 0))
		testing.expect_value(t, east_brazier.lit, both)
		testing.expect_value(t, headless.run_events(&run, g.Event_Brazier), 2 if both else 1)
		scenarios.expect_synced(t, &run)
	}
}

// A gate counts its braziers lit as it counts its plates pressed (gate_count): the store gate (its need raised to 2
// for this) stays shut with its plate pressed alone or a brazier lit alone, and opens with both.
@(test)
a_gate_counts_its_braziers_and_plates :: proc(t: ^testing.T) {
	run := workshop(2)
	defer headless.run_end(&run)
	sim.slice(&floor_of(&run).places.gates)[STORE_GATE].need = 2
	gate, _ := gate_at(&run, STORE_GATE)
	place_hero(&run, 1, plate_spot(&run, STORE_PLATE))
	play(&run, {}, 0.5)
	testing.expect(t, !gate.open, "a plate alone is one of two")
	place_hero(&run, 1, spawn_of(&run, 1))
	brazier, _ := brazier_at(&run, BRAZIER_WEST)
	brazier.lit = true
	headless.run_pin(&run)
	play(&run, {}, 0.5)
	testing.expect(t, !gate.open, "a brazier alone is one of two")
	place_hero(&run, 1, plate_spot(&run, STORE_PLATE))
	play(&run, {}, 0.5)
	testing.expect(t, gate.open, "a plate and a brazier are two")
	scenarios.expect_synced(t, &run)
}

// A lighting brings the next surge within BRAZIER_SURGE_S (the workshop's surges held off: due at the end of time): the
// surge's clock runs out then, and starts again.
@(test)
a_lighting_brings_the_surge_near :: proc(t: ^testing.T) {
	run := workshop()
	defer headless.run_end(&run)
	state := &run.simulation.state
	headless.run_command(&run, 0, g.Command_Dev_Light_Braziers{})
	testing.expect_value(t, headless.run_events(&run, g.Event_Brazier), 2)
	due := state.clock.time + sim.Game_Time(g.BRAZIER_SURGE_TICKS)
	testing.expect_value(t, state.surge.target, due)
	play(&run, {}, g.BRAZIER_SURGE_S)
	testing.expect_value(t, state.surge.start, due) // raise_surges started the next one as this one ran out
	scenarios.expect_synced(t, &run)
}

// A fireball bursting within BRAZIER_BLAST of a brazier with a wall between lights nothing: on the vault, a brazier's
// place moved behind its Pillar1 and the fireball lobbed to the pillar's other side.
@(test)
a_wall_keeps_a_fireball_from_a_brazier :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Vault}, seated = 1)
	defer headless.run_end(&run)
	hold_surges(&run)
	pillar := [3]f32{-3, 0, -3} // game/levels/vault.tscn's Pillar1, 1.5 m square
	behind := pillar + {-1.35, 0, 0}
	sim.slice(&floor_of(&run).places.braziers)[0].pos = behind
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Mage})
	from := on_floor(&run, pillar + {4.5, 0, 0})
	place_hero(&run, 0, from, {-1, 0})
	aim := g.Input {
		aim   = dmath.dir2([2]f32{-1, 0}),
		reach = g.reach_steps(from.x - (pillar.x + 1.35)),
	}
	press(&run, 0, .Ability, aim)
	inputs := [g.PLAYERS]g.Input {
		0 = aim,
	}
	burst: g.Event_Fireball_Burst
	for _ in 0 ..< int((g.FIREBALL_WINDUP_S + g.FIREBALL_FLIGHT_S + 0.5) * g.TICK_HZ) {
		headless.run_step(&run, inputs)
		found: bool
		burst, found = headless.run_last_event(&run, g.Event_Fireball_Burst)
		if found do break
	}
	apart := dmath.length(burst.position.xz - behind.xz)
	testing.expectf(t, apart < g.BRAZIER_BLAST, "the burst %v m from the brazier, within its blast", apart)
	brazier, _ := brazier_at(&run, 0)
	testing.expect(t, !brazier.lit, "the wall kept the fire off")
	scenarios.expect_synced(t, &run)
}

// A hero carrying a prop kindles nothing: its Interact press at a brazier drops the prop, and holding it on starts no
// kindling.
@(test)
full_hands_kindle_nothing :: proc(t: ^testing.T) {
	run := at_the_brazier(1)
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 0)
	away := brazier_spot(&run, BRAZIER_WEST) + {0, 0, -4}
	place_hero(&run, 0, away, {0, -1})
	place_prop(&run, 0, away + {0, 0, -1.1})
	play(&run, {}, 0.2)
	press(&run, 0, .Interact) // the prop in front of it, away from the brazier: grabbed
	testing.expect(t, hero.held != {}, "the prop is in its hands")
	place_hero(&run, 0, brazier_spot(&run, BRAZIER_WEST) + {0, 0, -1.25}, {0, 1})
	play(&run, {}, 1)
	testing.expect(t, hero.held != {} && hero.action == .None, "still carried at the brazier, its pick-up done")
	kindle(&run, {0}, int(g.TICK_HZ / 2))
	brazier, _ := brazier_at(&run, BRAZIER_WEST)
	testing.expect_value(t, hero.held, sim.Handle(g.Prop){})
	testing.expect(
		t,
		hero.action != .Kindle && brazier.progress == 0,
		"the press dropped the prop and kindled nothing",
	)
	scenarios.expect_synced(t, &run)
}
