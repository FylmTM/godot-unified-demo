// The Barbarian's heave (barbarian.odin): what it grabs and what it never does, the held body limp on the hold, the
// throw and its landing's blast, letting an unthrown body down, every way a heave ends early, and the Barbarian's
// faster prop throws. Each on a sync-tested run (headless.Run) that ends synced, so every heave here also rolls back:
// the limp bodies, their masses and the hold's joint included (check_refs after every restore).
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// How far ahead of the Barbarian a body it should grab stands (feet to feet): in its reach (GRAB_RANGE past both
// capsules), in front.
GRAB_AHEAD :: f32(1.3)

// A run with slot 0's Barbarian at its spawn facing +X (`seated` heroes in all, the others where they arrived), no
// minion and no elite.
@(private = "file")
barbarian_run :: proc(seated := 1) -> headless.Run(g.Game) {
	run := headless.run_begin(&g.GAME, 1, seated = seated)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Barbarian})
	clear_minions(&run)
	clear_elites(&run)
	place_hero(&run, 0, spawn_of(&run, 0), {1, 0})
	return run
}

// Slot 0 holds `input` (the others idle) for `ticks` ticks.
@(private = "file")
hold :: proc(run: ^headless.Run(g.Game), input: g.Input, ticks: int) {
	for _ in 0 ..< ticks do headless.run_step(run, [g.PLAYERS]g.Input{0 = input})
}

// Steps until a thrown body lands (Event_Heave_Landed), at most HEAVE_FLIGHT_MAX_S; whether it landed.
@(private = "file")
until_landed :: proc(run: ^headless.Run(g.Game), inputs: [g.PLAYERS]g.Input = {}) -> bool {
	landed := headless.run_events(run, g.Event_Heave_Landed)
	for _ in 0 ..< g.HEAVE_FLIGHT_MAX_TICKS + 1 {
		headless.run_step(run, inputs)
		if headless.run_events(run, g.Event_Heave_Landed) > landed do return true
	}
	return false
}

// Whether a character's body is limp (no drive, no pogo).
@(private = "file")
limp :: proc(body: physics.Character) -> bool {
	return .Limp in body.flags
}

// Where the hold carries the feet of a heaved body whose capsule's centre is `centre_above_feet` over them, for the
// Barbarian `hero`: heave_frame's point (from the Barbarian's centre), less that height.
@(private = "file")
hold_point :: proc(hero: ^g.Hero, centre_above_feet: f32) -> [3]f32 {
	return hero.pos + g.heave_frame(hero).p + {0, g.HERO_CENTRE_ABOVE_FEET - centre_above_feet, 0}
}

// An elite thrown into a pack lands a blast. Ability's press heaves the Warrior asleep in front: it wakes (its sleeper's
// kinematic capsule a character's body again, spawn_elite), goes limp and hangs on the hold in front of the Barbarian,
// light in the hands (HEAVE_MASS), and stops guarding; Attack throws it (its own
// weight back) along the facing, and where it lands the skeletons round it take HEAVE_LAND_DAMAGE, as the Warrior does
// itself, staggered. Then it stands on its own again: not limp, on its feet, walking after its target.
@(test)
a_heave_throws_an_elite_into_a_pack :: proc(t: ^testing.T) {
	run := barbarian_run()
	defer headless.run_end(&run)
	barbarian := sim.slot_data(run.simulation, 0)
	start := barbarian.pos
	handle := place_elite(&run, .Warrior, start + {GRAB_AHEAD, 0, 0}, {-1, 0}, .Idle)
	pack: [8]sim.Handle(g.Minion) // a line of them along the throw, so its landing is among them wherever it falls
	for &minion, i in pack do minion = place_minion(&run, start + {3.5 + f32(i), 0, 0}, .Rise)
	warrior := elite_of(&run, handle)
	phys := run.simulation.world.phys
	testing.expect_value(t, physics.body_type(phys, warrior.body.body), physics.Body_Type.Kinematic) // asleep

	press(&run, 0, .Ability)
	testing.expect_value(t, headless.run_events(&run, g.Event_Heaved), 1)
	testing.expect_value(t, barbarian.action, g.Action.Heave)
	testing.expect_value(t, warrior.phase, g.Elite_Phase.Held)
	testing.expect(t, limp(warrior.body), "the held Warrior is limp")
	testing.expect_value(t, physics.body_type(phys, warrior.body.body), physics.Body_Type.Dynamic)
	testing.expect(t, !g.shield_up(run.simulation.state.clock.time, warrior), "a held Warrior guards nothing")
	testing.expect_value(t, physics.body_mass(phys, warrior.body.body), g.HEAVE_MASS)
	hold(&run, {}, int(g.TICK_HZ / 2))
	hung := dmath.length(warrior.pos - hold_point(barbarian, g.ELITE_CENTRE_ABOVE_FEET))
	testing.expectf(
		t,
		hung < 0.3,
		"the Warrior hangs %v m off the hold (at %v, the Barbarian at %v)",
		hung,
		warrior.pos,
		barbarian.pos,
	)

	press(&run, 0, .Attack)
	testing.expect_value(t, barbarian.action, g.Action.Hurl)
	hold(&run, {}, int(g.THROW_WINDUP_TICKS) - 1)
	testing.expect_value(t, warrior.phase, g.Elite_Phase.Thrown)
	testing.expect_value(t, barbarian.heaved, g.Heaved{})
	full := physics.body_mass(phys, warrior.body.body)
	testing.expectf(t, full > 4 * g.HEAVE_MASS, "thrown, it weighs its own %v kg again", full)
	testing.expect(t, until_landed(&run), "the Warrior lands")
	testing.expectf(t, warrior.pos.x > start.x + 4, "it landed at %v, thrown from %v", warrior.pos, start)
	testing.expect_value(t, warrior.hp, g.ELITE_SPECS[.Warrior].hp - g.HEAVE_LAND_DAMAGE)
	testing.expect(t, sim.timer_running(run.simulation.state.clock.time, warrior.stagger), "the landing staggers it")
	testing.expect(t, !limp(warrior.body), "landed, it stands on its own")
	struck := 0
	for minion in pack {
		struck += int(sim.get(&run.simulation.state.minions, minion).hp == g.MINION_HP - g.HEAVE_LAND_DAMAGE)
	}
	testing.expectf(t, struck >= 2, "the landing struck %d of the pack", struck)

	hold(&run, {}, int(g.TICK_HZ))
	floor := spawn_of(&run, 0).y
	testing.expectf(
		t,
		abs(warrior.pos.y - floor) < 0.1,
		"back on its feet at %v (the floor at %v)",
		warrior.pos,
		floor,
	)
	testing.expect(t, warrior.phase == .Chase || warrior.phase == .Attack, "it fights on")
	scenarios.expect_synced(t, &run)
}

// A heave grabs only what is in its grab cone and ready to be grabbed: an ally who is up is never heaved (nor is
// anything when nothing is in reach), and a press that grabs nothing spends no cooldown. Held HEAVE_MAX_S unthrown,
// the body is let down where it hangs, stands on its own, and the cooldown runs from there.
@(test)
a_heave_grabs_elites_and_the_downed_only :: proc(t: ^testing.T) {
	run := barbarian_run(seated = 2)
	defer headless.run_end(&run)
	barbarian := sim.slot_data(run.simulation, 0)
	ally := sim.slot_data(run.simulation, 1)
	place_hero(&run, 1, barbarian.pos + {GRAB_AHEAD, 0, 0}, {-1, 0})
	press(&run, 0, .Ability)
	testing.expect_value(t, headless.run_events(&run, g.Event_Heaved), 0)
	testing.expect_value(t, barbarian.ability_ready, sim.Timer{})
	testing.expect_value(t, ally.heave, g.Heave_Phase.None)

	place_hero(&run, 1, barbarian.pos + {-6, 0, 0}) // out of the way
	handle := place_elite(&run, .Rogue, barbarian.pos + {GRAB_AHEAD, 0, 0}, {-1, 0}, .Idle)
	rogue := elite_of(&run, handle)
	press(&run, 0, .Ability)
	testing.expect_value(t, rogue.phase, g.Elite_Phase.Held)
	hold(&run, {}, int(g.HEAVE_MAX_TICKS) - 2) // after the press's two ticks: HEAVE_MAX_S less a tick
	testing.expect_value(t, rogue.phase, g.Elite_Phase.Held)
	hold(&run, {}, 1)
	testing.expect_value(t, rogue.phase, g.Elite_Phase.Chase)
	testing.expect(t, !limp(rogue.body), "let down, it stands on its own")
	testing.expect_value(t, barbarian.action, g.Action.None)
	testing.expect_value(t, barbarian.heaved, g.Heaved{})
	testing.expect_value(t, headless.run_events(&run, g.Event_Heave_Landed), 0) // let down, never thrown
	testing.expect(t, sim.timer_running(run.simulation.state.clock.time, barbarian.ability_ready), "its cooldown runs")
	scenarios.expect_synced(t, &run)
}

// A downed ally is heaved and thrown as a rescue: limp in the Barbarian's hands, out of every reviver's reach while it
// hangs or flies, deaf to its own player's input (stick, aim and every button held throughout), and once it lands it
// lies where it fell, still down, held still by its drive, and an ally can revive it there.
@(test)
a_heave_throws_a_downed_ally_to_its_rescuers :: proc(t: ^testing.T) {
	run := barbarian_run(seated = 3)
	defer headless.run_end(&run)
	barbarian := sim.slot_data(run.simulation, 0)
	downed := sim.slot_data(run.simulation, 1)
	start := barbarian.pos
	place_hero(&run, 1, start + {GRAB_AHEAD, 0, 0}, {0, 1})
	place_hero(&run, 2, start + {6, 0, 2.5}, {0, -1}) // the rescuer, waiting beside where the throw comes down
	hurt(&run, 1, g.HERO_HP)
	testing.expect_value(t, downed.action, g.Action.Down)
	mashing := g.Input {
		move_x  = 127,
		move_z  = -127,
		aim     = dmath.dir2({0, -1}),
		reach   = 20,
		buttons = {.Attack, .Interact, .Ability},
	}
	inputs := [g.PLAYERS]g.Input {
		0 = {buttons = {.Ability}},
		1 = mashing,
	}
	headless.run_step(&run, inputs)
	inputs[0] = {}
	testing.expect_value(t, downed.heave, g.Heave_Phase.Held)
	testing.expect_value(t, downed.heaved_by, sim.player_in_slot(run.simulation, 0))
	testing.expect(t, limp(downed.body), "the held ally is limp")
	for _ in 0 ..< g.TICK_HZ / 2 do headless.run_step(&run, inputs)
	hung := dmath.length(downed.pos - hold_point(barbarian, g.HERO_CENTRE_ABOVE_FEET))
	testing.expectf(t, hung < 0.3, "the ally hangs %v m off the hold", hung)
	expect_facing(t, downed, {0, 1})
	testing.expect_value(t, downed.action, g.Action.Down)
	rescuer := sim.player_in_slot(run.simulation, 2)
	place_hero(&run, 2, downed.pos + {0.6, 0, 0}, {-1, 0}) // right beside it: a hanging ally is no one's to tend
	testing.expect_value(t, g.revive_target(&run.simulation.state.players, rescuer), sim.Player{})
	place_hero(&run, 2, start + {6, 0, 2.5}, {0, -1})

	inputs[0] = {
		buttons = {.Attack},
	}
	headless.run_step(&run, inputs)
	inputs[0] = {}
	for _ in 0 ..< g.THROW_WINDUP_TICKS do headless.run_step(&run, inputs)
	testing.expect_value(t, downed.heave, g.Heave_Phase.Thrown)
	testing.expect(t, until_landed(&run, inputs), "the ally lands")
	testing.expect_value(t, downed.heave, g.Heave_Phase.None)
	testing.expect_value(t, downed.action, g.Action.Down)
	testing.expect(t, !limp(downed.body), "landed, its drive holds it again")
	for _ in 0 ..< g.TICK_HZ / 2 do headless.run_step(&run, inputs)
	testing.expectf(t, dmath.length(downed.vel) < 0.05, "it lies still: %v m/s", downed.vel)
	testing.expectf(t, downed.pos.x > start.x + 4, "it came down at %v, thrown from %v", downed.pos, start)
	expect_facing(t, downed, {0, 1})
	testing.expect_value(t, headless.run_events(&run, g.Event_Ability), 1) // the heave's: none of the ally's own
	place_hero(&run, 2, downed.pos + {0.6, 0, 0}, {-1, 0})
	testing.expect_value(
		t,
		g.revive_target(&run.simulation.state.players, rescuer),
		sim.player_in_slot(run.simulation, 1),
	)
	scenarios.expect_synced(t, &run)
}

// Whatever ends a heave early lets the body go first, with no joint left on a body that goes (check_refs, synced):
// revived while held (a dev revive), the ally rises free of the hold and walks on its own stick; a held elite killed
// lets the Barbarian stand free; the Barbarian downed drops what it heaves; a held ally leaving is let go of.
@(test)
a_heave_ends_when_its_body_goes :: proc(t: ^testing.T) {
	run := barbarian_run(seated = 3)
	defer headless.run_end(&run)
	barbarian := sim.slot_data(run.simulation, 0)
	ally := sim.slot_data(run.simulation, 1)
	place_hero(&run, 2, barbarian.pos + {-6, 0, 0})
	heave_ally :: proc(run: ^headless.Run(g.Game)) {
		barbarian := sim.slot_data(run.simulation, 0)
		place_hero(run, 1, barbarian.pos + {GRAB_AHEAD, 0, 0})
		hurt(run, 1, g.HERO_HP)
		press(run, 0, .Ability)
	}

	heave_ally(&run)
	testing.expect_value(t, ally.heave, g.Heave_Phase.Held)
	headless.run_command(&run, 0, g.Command_Dev_Revive{})
	testing.expect_value(t, ally.action, g.Action.None)
	testing.expect_value(t, ally.heave, g.Heave_Phase.None)
	testing.expect_value(t, barbarian.heaved, g.Heaved{})
	testing.expect_value(t, barbarian.action, g.Action.None)
	testing.expect(t, !limp(ally.body), "revived, it stands on its own")
	from := ally.pos
	play(&run, {1 = {move_z = 127}}, 0.5)
	testing.expectf(t, ally.pos.z > from.z + 1, "it walks on its own stick: %v from %v", ally.pos, from)

	hold(&run, {}, int(g.HEAVE_COOLDOWN_TICKS))
	handle := place_elite(&run, .Mage, barbarian.pos + {GRAB_AHEAD, 0, 0}, {-1, 0}, .Idle)
	press(&run, 0, .Ability)
	testing.expect_value(t, elite_of(&run, handle).phase, g.Elite_Phase.Held)
	headless.run_command(&run, 0, g.Command_Dev_Hurt_Elites{g.ELITE_SPECS[.Mage].hp})
	testing.expect_value(t, elite_of(&run, handle).phase, g.Elite_Phase.Dying)
	testing.expect_value(t, barbarian.heaved, g.Heaved{})
	testing.expect_value(t, barbarian.action, g.Action.None)

	hold(&run, {}, int(g.HEAVE_COOLDOWN_TICKS))
	heave_ally(&run)
	testing.expect_value(t, ally.heave, g.Heave_Phase.Held)
	hurt(&run, 0, g.HERO_HP)
	testing.expect_value(t, barbarian.action, g.Action.Down)
	testing.expect_value(t, ally.heave, g.Heave_Phase.None)
	testing.expect(t, !limp(ally.body), "dropped, its drive holds it again")
	headless.run_command(&run, 2, g.Command_Dev_Revive{sim.player_in_slot(run.simulation, 0)})

	hold(&run, {}, int(g.HEAVE_COOLDOWN_TICKS))
	press(&run, 0, .Ability)
	testing.expect_value(t, ally.heave, g.Heave_Phase.Held)
	headless.run_seat(&run, 1, 0) // the held ally leaves
	headless.run_step(&run)
	testing.expect_value(t, barbarian.heaved, g.Heaved{})
	testing.expect_value(t, barbarian.action, g.Action.None)
	play(&run, {}, 0.5)
	scenarios.expect_synced(t, &run)
}

// The Barbarian throws a prop BARBARIAN_THROW times as fast along the floor as any other hero, with the same lift.
@(test)
the_barbarian_throws_props_harder :: proc(t: ^testing.T) {
	for class in ([]g.Class{.Knight, .Barbarian}) {
		run := headless.run_begin(&g.GAME, 1, seated = 1)
		defer headless.run_end(&run)
		headless.run_command(&run, 0, g.Command_Dev_Set_Class{class})
		clear_minions(&run)
		place_hero(&run, 0, spawn_of(&run, 0), {1, 0})
		place_prop(&run, BARREL, spawn_of(&run, 0) + {1.4, 0, 0})
		press(&run, 0, .Interact)
		play(&run, {}, 0.75)
		press(&run, 0, .Attack)
		for _ in 1 ..< g.THROW_WINDUP_TICKS do headless.run_step(&run)
		thrown := false
		for &raw in sim.events_at(run.simulation, run.simulation.tick) {
			if throw, ok := sim.event_value(&raw, g.Event).(g.Event_Prop_Thrown); ok {
				speed := g.THROW_SPEED * (g.BARBARIAN_THROW if class == .Barbarian else 1)
				testing.expect_value(t, throw.velocity, [3]f32{speed, g.THROW_LIFT, 0})
				thrown = true
			}
		}
		testing.expectf(t, thrown, "the %v threw", class)
		scenarios.expect_synced(t, &run)
	}
}
