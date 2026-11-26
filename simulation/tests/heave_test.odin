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

// An elite thrown into a pack lands a blast. Ability's press heaves the Warrior asleep in front: it wakes (a sleeper's
// dormant character a dynamic body again), goes limp and hangs on the hold in front of the Barbarian, light in the
// hands (HEAVE_MASS), and stops guarding; Attack throws it (its own weight back) along the facing; it lands on the
// floor, and the skeletons round it take HEAVE_LAND_DAMAGE, as the Warrior does itself, staggered. Then it stands on its
// own again: not limp, on its feet, walking after its target.
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
	testing.expect(t, physics.character_dormant(&warrior.body), "asleep, it is dormant")

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
	testing.expectf(t, warrior.pos.y - start.y < 0.4, "it landed on the floor, not in the air: %v", warrior.pos)
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
	mass := physics.body_mass(run.simulation.world.phys, rogue.body.body)
	testing.expectf(t, mass > 4 * g.HEAVE_MASS, "let down, it weighs its own %v kg again", mass)
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
	place_hero(&run, 2, downed.pos * {1, 0, 1} + {0.6, 0, 0}, {-1, 0}) // under it as it flies
	testing.expect_value(t, g.revive_target(&run.simulation.state.players, rescuer), sim.Player{})
	place_hero(&run, 2, start + {6, 0, 2.5}, {0, -1})
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

// Heaves an elite of `kind` asleep GRAB_AHEAD in front of slot 0's Barbarian (Ability's press): its handle.
@(private = "file")
heave_ahead :: proc(run: ^headless.Run(g.Game), kind: g.Elite_Kind = .Warrior) -> sim.Handle(g.Elite) {
	barbarian := sim.slot_data(run.simulation, 0)
	handle := place_elite(run, kind, barbarian.pos + {GRAB_AHEAD, 0, 0}, {-1, 0}, .Idle)
	press(run, 0, .Ability)
	return handle
}

// A thrown body passes through every hero until it lands: an ally standing in its path and a downed one lying there
// are never struck (a 300 kg skeleton at THROW_SPEED would bowl either over), and it lands beyond them.
@(test)
a_thrown_body_passes_through_heroes :: proc(t: ^testing.T) {
	run := barbarian_run(seated = 3)
	defer headless.run_end(&run)
	start := sim.slot_data(run.simulation, 0).pos
	standing, lying := sim.slot_data(run.simulation, 1), sim.slot_data(run.simulation, 2)
	place_hero(&run, 1, start + {3, 0, 0}, {-1, 0})
	place_hero(&run, 2, start + {4.5, 0, 0}, {-1, 0})
	hurt(&run, 2, g.HERO_HP)
	warrior := elite_of(&run, heave_ahead(&run))
	hold(&run, {}, 8)
	up, down := standing.pos, lying.pos
	press(&run, 0, .Attack)
	testing.expect(t, until_landed(&run), "the Warrior lands")
	testing.expectf(t, dmath.length(standing.pos - up) < 0.05, "the ally in its path moved to %v", standing.pos)
	testing.expectf(t, dmath.length(lying.pos - down) < 0.05, "the downed ally in its path moved to %v", lying.pos)
	testing.expectf(t, warrior.pos.x > start.x + 5, "it landed beyond them, at %v", warrior.pos)
	scenarios.expect_synced(t, &run)
}

// A Barbarian that turns about and throws at once (the body swinging through it on the hold) is left standing where it
// was: the body passes through its thrower too, and lands behind it.
@(test)
a_throw_behind_leaves_the_thrower_standing :: proc(t: ^testing.T) {
	run := barbarian_run()
	defer headless.run_end(&run)
	barbarian := sim.slot_data(run.simulation, 0)
	warrior := elite_of(&run, heave_ahead(&run))
	hold(&run, {}, 6)
	standing := barbarian.pos
	behind := g.Input {
		aim = dmath.dir2({-1, 0}),
	}
	thrown := behind
	thrown.buttons = {.Attack}
	hold(&run, thrown, 1)
	hold(&run, behind, int(g.THROW_WINDUP_TICKS))
	testing.expect(t, until_landed(&run, {0 = behind}), "the Warrior lands")
	moved := dmath.length(barbarian.pos.xz - standing.xz)
	testing.expectf(t, moved < 0.3, "its own throw shoved the Barbarian %v m", moved)
	testing.expectf(t, warrior.pos.x < standing.x - 2, "it landed behind, at %v", warrior.pos)
	scenarios.expect_synced(t, &run)
}

// A thrown elite can't be heaved again until HEAVE_COOLDOWN_S after it landed, by when it stands on its own, its
// stagger over: a Barbarian walking up to it and pressing Ability all the while takes it up no sooner.
@(test)
a_thrown_elite_is_back_on_its_feet_before_the_next_heave :: proc(t: ^testing.T) {
	run := barbarian_run()
	defer headless.run_end(&run)
	barbarian := sim.slot_data(run.simulation, 0)
	warrior := elite_of(&run, heave_ahead(&run))
	hold(&run, {}, 4)
	press(&run, 0, .Attack)
	testing.expect(t, until_landed(&run), "the Warrior lands")
	landed := run.simulation.state.clock.time
	for i in 0 ..< 2 * g.HEAVE_COOLDOWN_TICKS {
		if headless.run_events(&run, g.Event_Heaved) == 2 do break
		offset := warrior.pos.xz - barbarian.pos.xz
		input := g.Input {
			aim = dmath.dir2(dmath.normalize(offset)),
		}
		if dmath.length(offset) > 1.2 do input.move_x, input.move_z = dmath.axis_i8(dmath.normalize(offset).x), dmath.axis_i8(dmath.normalize(offset).y)
		if i % 2 == 0 do input.buttons = {.Ability}
		hold(&run, input, 1)
	}
	testing.expect_value(t, headless.run_events(&run, g.Event_Heaved), 2)
	again := u32(run.simulation.state.clock.time - landed)
	testing.expectf(t, again >= g.HEAVE_COOLDOWN_TICKS, "heaved again %d ticks after it landed", again)
	scenarios.expect_synced(t, &run)
}

// A dev class change while heaving lets the body down (release_heave): the elite stands on its own, its own weight
// back, and the hero (a Knight now) holds nothing.
@(test)
a_class_change_lets_the_heave_down :: proc(t: ^testing.T) {
	run := barbarian_run()
	defer headless.run_end(&run)
	barbarian := sim.slot_data(run.simulation, 0)
	warrior := elite_of(&run, heave_ahead(&run))
	testing.expect_value(t, warrior.phase, g.Elite_Phase.Held)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Knight})
	testing.expect_value(t, barbarian.heaved, g.Heaved{})
	testing.expect(t, warrior.phase != .Held, "let down, it fights on")
	testing.expect(t, !limp(warrior.body), "let down, it stands on its own")
	mass := physics.body_mass(run.simulation.world.phys, warrior.body.body)
	testing.expectf(t, mass > 4 * g.HEAVE_MASS, "it weighs its own %v kg again", mass)
	scenarios.expect_synced(t, &run)
}

// What a heave never takes: an elite out of its cone (beside the Barbarian, past GRAB_ANYWHERE), behind a wall (in_grab's
// ray), still rising, or already flying from a throw, and an ally another Barbarian holds. An elite in front, in reach,
// is taken.
@(test)
a_heave_takes_only_whats_free_and_in_front :: proc(t: ^testing.T) {
	run := barbarian_run(seated = 3)
	defer headless.run_end(&run)
	barbarian := sim.slot_data(run.simulation, 0)
	start := barbarian.pos
	missed :: proc(t: ^testing.T, run: ^headless.Run(g.Game), what: string, loc := #caller_location) {
		heaves := headless.run_events(run, g.Event_Heaved)
		press(run, 0, .Ability)
		testing.expectf(t, headless.run_events(run, g.Event_Heaved) == heaves, "heaved %s", what, loc = loc)
	}
	place_elite(&run, .Rogue, start + {0, 0, 1.4}, {0, -1}, .Idle) // 90 degrees off its facing
	missed(t, &run, "an elite beside it")
	clear_elites(&run)
	place_elite(&run, .Rogue, start + {GRAB_AHEAD, 0, 0}, {-1, 0}, .Rise)
	missed(t, &run, "a rising elite")
	clear_elites(&run)
	flying := place_elite(&run, .Rogue, start + {GRAB_AHEAD, 0, 0}, {-1, 0}, .Chase)
	elite_of(&run, flying).phase = .Thrown
	headless.run_pin(&run)
	missed(t, &run, "a flying elite")
	clear_elites(&run)
	// Floor 1's great hall: its north wall's face at z = -11.5, the room beyond it from -12
	place_hero(&run, 0, {10, 0, -11}, {0, -1})
	state := &run.simulation.state
	g.spawn_elite(state, run.simulation.world, .Rogue, {10, 0, -12.6}, {0, 1}, .Idle, state.clock.time)
	headless.run_pin(&run)
	missed(t, &run, "an elite behind a wall")
	scenarios.expect_synced(t, &run)
}

// An ally another Barbarian holds is nobody else's to heave; the body a heave holds follows its facing round as the
// hero turns (update_holds); a hero heaving walks at HEAVE_SPEED of its speed; Interact pressed while heaving grabs no
// prop.
@(test)
a_heave_holds_its_body :: proc(t: ^testing.T) {
	run := barbarian_run(seated = 3)
	defer headless.run_end(&run)
	headless.run_command(&run, 1, g.Command_Dev_Set_Class{.Barbarian})
	barbarian := sim.slot_data(run.simulation, 0)
	other := sim.slot_data(run.simulation, 1)
	ally := sim.slot_data(run.simulation, 2)
	start := [3]f32{6, 0, 0} // the great hall: room to turn round in
	place_hero(&run, 0, start, {1, 0})
	place_hero(&run, 2, start + {GRAB_AHEAD, 0, 0})
	place_hero(&run, 1, start + {2 * GRAB_AHEAD, 0, 0}, {-1, 0})
	hurt(&run, 2, g.HERO_HP)
	press(&run, 0, .Ability)
	testing.expect_value(t, ally.heave, g.Heave_Phase.Held)
	press(&run, 1, .Ability)
	testing.expect_value(t, other.heaved, g.Heaved{})
	testing.expect_value(t, ally.heaved_by, sim.player_in_slot(run.simulation, 0))
	place_hero(&run, 1, start + {-6, 0, 0})
	place_prop(&run, CRATE, start + {0, 0, -1.15}) // right against its side: a free hand would take it
	press(&run, 0, .Interact)
	testing.expect_value(t, barbarian.held, sim.Handle(g.Prop){})
	testing.expect_value(t, barbarian.heaved, g.Heaved{hero = sim.player_in_slot(run.simulation, 2)})
	hold(&run, {move_x = 127}, int(g.TICK_HZ * 3 / 8))
	want := g.CLASS_SPECS[.Barbarian].max_speed * g.HEAVE_SPEED
	testing.expectf(t, abs(barbarian.vel.x - want) < 0.2, "heaving, it walks at %v m/s, not %v", barbarian.vel.x, want)
	hold(&run, {aim = dmath.dir2({0, 1})}, int(g.TICK_HZ * 3 / 4)) // within HEAVE_MAX_S of the grab
	testing.expect_value(t, barbarian.action, g.Action.Heave)
	hung := dmath.length(ally.pos - hold_point(barbarian, g.HERO_CENTRE_ABOVE_FEET))
	testing.expectf(t, hung < 0.3, "turned, the ally hangs %v m off the hold", hung)
	scenarios.expect_synced(t, &run)
}

// When a thrown body has landed (heave_landed): falling, with the floor (or a prop) within HEAVE_LAND_GAP under it, so
// one rising over a crate flies on; and HEAVE_FLIGHT_MAX_S after the throw wherever it is. A
// downed ally revived as it flies is let down there and then.
@(test)
a_thrown_body_lands_when_it_should :: proc(t: ^testing.T) {
	{
		run := barbarian_run()
		defer headless.run_end(&run)
		warrior := elite_of(&run, heave_ahead(&run))
		hold(&run, {}, 4)
		press(&run, 0, .Attack)
		hold(&run, {}, int(g.THROW_WINDUP_TICKS))
		testing.expect_value(t, warrior.phase, g.Elite_Phase.Thrown)
		// A crate's top a hand under the rising body (it leaves the hands going up): no landing while it rises.
		place_prop(&run, CRATE, warrior.pos * {1, 0, 1} + {0, warrior.pos.y - 0.95, 0})
		hold(&run, {}, 1)
		testing.expect_value(t, headless.run_events(&run, g.Event_Heave_Landed), 0)
		testing.expect_value(t, warrior.phase, g.Elite_Phase.Thrown)
		scenarios.expect_synced(t, &run)
	}
	{
		run := barbarian_run()
		defer headless.run_end(&run)
		warrior := elite_of(&run, heave_ahead(&run))
		hold(&run, {}, 4)
		press(&run, 0, .Attack)
		hold(&run, {}, int(g.THROW_WINDUP_TICKS) + 2)
		testing.expect_value(t, warrior.phase, g.Elite_Phase.Thrown)
		warrior.since = run.simulation.state.clock.time + 1 - sim.Game_Time(g.HEAVE_FLIGHT_MAX_TICKS)
		headless.run_pin(&run)
		hold(&run, {}, 1)
		testing.expect_value(t, headless.run_events(&run, g.Event_Heave_Landed), 1)
		testing.expectf(t, warrior.pos.y > 0.3, "landed by its flight's end, in the air at %v", warrior.pos)
		scenarios.expect_synced(t, &run)
	}
	{
		run := barbarian_run(seated = 2)
		defer headless.run_end(&run)
		ally := sim.slot_data(run.simulation, 1)
		place_hero(&run, 1, sim.slot_data(run.simulation, 0).pos + {GRAB_AHEAD, 0, 0})
		hurt(&run, 1, g.HERO_HP)
		press(&run, 0, .Ability)
		press(&run, 0, .Attack)
		hold(&run, {}, int(g.THROW_WINDUP_TICKS))
		testing.expect_value(t, ally.heave, g.Heave_Phase.Thrown)
		headless.run_command(&run, 0, g.Command_Dev_Revive{})
		testing.expect_value(t, ally.heave, g.Heave_Phase.None)
		testing.expect(t, !limp(ally.body), "revived in flight, it is let down at once")
		scenarios.expect_synced(t, &run)
	}
}

// A landing's blast breaks a Warrior's guard as a thrown prop's hit does: a Warrior braced beside where a thrown ally
// comes down, its shield toward the landing, takes the whole of HEAVE_LAND_DAMAGE.
@(test)
a_landing_breaks_the_guard :: proc(t: ^testing.T) {
	landing: [3]f32
	for braced in ([]bool{false, true}) {
		run := barbarian_run(seated = 2)
		defer headless.run_end(&run)
		ally := sim.slot_data(run.simulation, 1)
		place_hero(&run, 1, sim.slot_data(run.simulation, 0).pos + {GRAB_AHEAD, 0, 0})
		hurt(&run, 1, g.HERO_HP)
		press(&run, 0, .Ability)
		press(&run, 0, .Attack)
		hold(&run, {}, int(g.THROW_WINDUP_TICKS))
		warrior: sim.Handle(g.Elite)
		if braced { 	// beside the first run's landing, facing it
			warrior = place_elite(&run, .Warrior, landing + {0, 0, 1.3}, {0, -1}, .Idle)
			brace(&run, warrior)
		}
		testing.expect(t, until_landed(&run), "the ally lands")
		if !braced {
			landing = ally.pos
			continue
		}
		testing.expectf(t, dmath.length(ally.pos - landing) < 0.01, "it landed at %v, not %v", ally.pos, landing)
		testing.expect_value(t, headless.run_events(&run, g.Event_Guard_Broken), 1)
		testing.expect_value(t, elite_of(&run, warrior).hp, g.ELITE_SPECS[.Warrior].hp - g.HEAVE_LAND_DAMAGE)
		scenarios.expect_synced(t, &run)
	}
}
