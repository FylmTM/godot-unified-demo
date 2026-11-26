// The abilities' rule tests (abilities.odin, the class files, fireballs.odin): the Knight's block and shield charge, the
// Rogue's roll, the Mage's fireball, and what they share (cutting an attack short, nothing during a co-op pause). Each
// on a sync-tested run (headless.Run) that ends synced, so every ability here also starts and ends under rollback.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// A run with slot 0's hero of `class` standing at its spawn facing +X (and `seated` heroes in all), and no minion.
@(private = "file")
ability_hero :: proc(class: g.Class, seated := 1) -> headless.Run(g.Game) {
	run := headless.run_begin(&g.GAME, 1, seated = seated)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{class})
	clear_minions(&run)
	place_hero(&run, 0, spawn_of(&run, 0), {1, 0})
	return run
}

// Slot 0 holds `input` for `ticks` ticks.
@(private = "file")
hold :: proc(run: ^headless.Run(g.Game), input: g.Input, ticks: int) {
	for _ in 0 ..< ticks do headless.run_step(run, [g.PLAYERS]g.Input{0 = input})
}

// A blocking Knight takes BLOCK_TAKE of a skeleton's swing from in front (the shield clangs: Event_Blocked), and the
// whole of one from behind.
@(test)
the_shield_takes_blows_from_the_front_only :: proc(t: ^testing.T) {
	for side in ([]f32{1, -1}) {
		run := ability_hero(.Knight)
		defer headless.run_end(&run)
		knight := sim.slot_data(run.simulation, 0)
		place_minion(&run, knight.pos + {side * 1.4, 0, 0}, .Chase, {-side, 0})
		hold(&run, {buttons = {.Ability}}, int(g.MINION_WINDUP_TICKS) + 4) // one swing lands
		testing.expect_value(t, knight.action, g.Action.Block)
		blocked := i16(dmath.round(f32(g.MINION_DAMAGE) * g.BLOCK_TAKE))
		want := g.HERO_HP - (blocked if side > 0 else g.MINION_DAMAGE)
		testing.expectf(t, knight.hp == want, "a swing from %v: %v HP left, not %v", side, knight.hp, want)
		testing.expect_value(t, headless.run_events(&run, g.Event_Blocked), 1 if side > 0 else 0)
		scenarios.expect_synced(t, &run)
	}
}

// Blocking slows the Knight to BLOCK_SPEED, and Ability held cuts a held Attack's swing short: the Knight blocks
// instead of attacking, and attacks again once it lets go of Ability (the cut attack's cooldown run).
@(test)
the_block_slows_and_cuts_an_attack_short :: proc(t: ^testing.T) {
	run := ability_hero(.Knight)
	defer headless.run_end(&run)
	knight := sim.slot_data(run.simulation, 0)
	hold(&run, {buttons = {.Attack}}, 3)
	testing.expect_value(t, knight.action, g.Action.Attack)
	hold(&run, {move_x = 127, buttons = {.Attack, .Ability}}, int(g.CLASS_SPECS[.Knight].cooldown))
	testing.expect_value(t, knight.action, g.Action.Block)
	want := g.CLASS_SPECS[.Knight].max_speed * g.BLOCK_SPEED
	testing.expectf(t, abs(knight.vel.x - want) < 0.15, "blocks at %v m/s, not %v", knight.vel.x, want)
	hold(&run, {buttons = {.Attack}}, 1)
	testing.expect_value(t, knight.action, g.Action.Attack)
	scenarios.expect_synced(t, &run)
}

// Attack pressed while blocking charges: the Knight dashes along its facing at CHARGE_SPEED for CHARGE_S, its stick
// and aim turning it not at all, knocking a skeleton in its way aside (CHARGE_DAMAGE, a stagger's knock); the
// charge's cooldown holds the next one back.
@(test)
a_shield_charge_dashes_and_knocks_aside :: proc(t: ^testing.T) {
	run := ability_hero(.Knight)
	defer headless.run_end(&run)
	knight := sim.slot_data(run.simulation, 0)
	start := knight.pos
	in_the_way := place_minion(&run, start + {2.5, 0, 0}, .Rise)
	hold(&run, {buttons = {.Ability}}, 2)
	hold(&run, {buttons = {.Ability, .Attack}}, 1) // along the facing it has as it presses
	testing.expect_value(t, knight.action, g.Action.Charge)
	testing.expect_value(t, headless.run_events(&run, g.Event_Ability), 2) // the block, then the charge
	hold(&run, {buttons = {.Ability}, move_z = 127, aim = dmath.dir2({0, 1})}, int(g.CHARGE_TICKS) - 1)
	testing.expect_value(t, knight.action, g.Action.Charge)
	expect_facing(t, knight, {1, 0})
	travelled := knight.pos.x - start.x
	testing.expectf(t, travelled > 0.75 * g.CHARGE_SPEED * g.CHARGE_S, "charged %v m", travelled)
	minion := sim.get(&run.simulation.state.minions, in_the_way)
	testing.expectf(t, minion.hp < g.MINION_HP && minion.hp >= g.MINION_HP - 4 * g.CHARGE_DAMAGE, "hp %v", minion.hp)
	hold(&run, {buttons = {.Ability}}, 1)
	testing.expect_value(t, knight.action, g.Action.Block) // the charge over, the shield still up
	hold(&run, {buttons = {.Ability, .Attack}}, 1)
	testing.expect_value(t, knight.action, g.Action.Block) // its cooldown runs: no second charge
	scenarios.expect_synced(t, &run)
}

// The Rogue's roll goes along the stick (not the aim) at ROLL_SPEED, and keeps that line whatever the aim and stick do
// through it; nothing hurts the Rogue in its first ROLL_SAFE_S, and a blow lands from then, though it still rolls.
@(test)
a_roll_is_safe_only_early :: proc(t: ^testing.T) {
	run := ability_hero(.Rogue)
	defer headless.run_end(&run)
	rogue := sim.slot_data(run.simulation, 0)
	hold(&run, {buttons = {.Ability}, move_z = 127, aim = dmath.dir2({1, 0})}, 1)
	testing.expect_value(t, rogue.action, g.Action.Roll)
	expect_facing(t, rogue, {0, 1})
	hold(&run, {aim = dmath.dir2({1, 0}), move_x = 127}, int(g.ROLL_SAFE_TICKS) - 2) // mid-roll: they turn it not
	expect_facing(t, rogue, {0, 1})
	testing.expectf(t, abs(rogue.vel.z - g.ROLL_SPEED) < 0.5, "rolls at %v m/s, not %v", rogue.vel.z, g.ROLL_SPEED)
	hurt(&run, 0, 30) // its age now ROLL_SAFE_TICKS - 1
	testing.expect_value(t, rogue.hp, g.HERO_HP)
	hurt(&run, 0, 30) // ROLL_SAFE_TICKS: the safe start is over
	testing.expect_value(t, rogue.action, g.Action.Roll)
	testing.expect_value(t, rogue.hp, g.HERO_HP - 30)
	scenarios.expect_synced(t, &run)
}

// Slot 0's Mage casts a fireball on `input` (Ability pressed with it, then held without), and the row it leaves is
// returned with where fireball_target said, on the tick before, it would land: the cast reads the same proc on the same
// state and input.
@(private = "file")
cast_on :: proc(run: ^headless.Run(g.Game), input: g.Input) -> (fireball: g.Fireball, predicted: [3]f32) {
	pressed := input
	pressed.buttons += {.Ability}
	hold(run, pressed, 1)
	hold(run, input, int(g.FIREBALL_WINDUP_TICKS) - 1)
	predicted = g.fireball_target(run.simulation.world.phys, sim.slot_data(run.simulation, 0), input)
	hold(run, input, 1)
	walk := sim.iterate(&run.simulation.state.fireballs)
	for row in sim.next(&walk) do fireball = row^
	return
}

// A fireball leaves at the cast's windup, for the point its aim reaches (Input.reach), which is fireball_target's on the
// tick's input (the view's ring calls it on the newest one); it bursts FIREBALL_FLIGHT_S later.
@(test)
a_fireball_lands_at_the_reach :: proc(t: ^testing.T) {
	run := ability_hero(.Mage)
	defer headless.run_end(&run)
	mage := sim.slot_data(run.simulation, 0)
	aim := g.Input {
		aim   = dmath.dir2({1, 0}),
		reach = g.reach_steps(4.5),
	}
	fireball, predicted := cast_on(&run, aim)
	testing.expect_value(t, int(run.simulation.state.fireballs.count), 1)
	testing.expect_value(t, mage.action, g.Action.None)
	testing.expect_value(t, fireball.to, predicted)
	landing := dmath.length(fireball.to.xz - mage.pos.xz)
	testing.expectf(t, abs(landing - 4.5) < 0.1, "lands %v m out, not at the reach (4.5)", landing)
	hold(&run, aim, int(g.FIREBALL_FLIGHT_TICKS) - 1)
	testing.expect_value(t, headless.run_events(&run, g.Event_Fireball_Burst), 0)
	hold(&run, aim, 1)
	testing.expect_value(t, headless.run_events(&run, g.Event_Fireball_Burst), 1)
	testing.expect_value(t, int(run.simulation.state.fireballs.count), 0)
	scenarios.expect_synced(t, &run)
}

// A fireball aimed through a wall lands FIREBALL_WALL_GAP short of it, and the wall shields what is behind it: a
// skeleton beside the burst in the hall takes FIREBALL_DAMAGE, one as near behind the wall nothing; a barrel by the
// burst is blown away, a crate as near behind the wall stays put (blast_bodies). A hero beside the burst isn't moved.
@(test)
a_fireball_stops_at_walls_and_moves_props :: proc(t: ^testing.T) {
	run := ability_hero(.Mage, seated = 2)
	defer headless.run_end(&run)
	place_hero(&run, 0, {10, 0, -8}, {0, -1}) // facing the wall at z = -12 (its hall face at -11.5)
	place_hero(&run, 1, {8.6, 0, -9.8})
	bystander := sim.slot_data(run.simulation, 1)
	beside := place_minion(&run, {8.5, 0, -11}, .Rise)
	behind := place_minion(&run, {10, 0, -13.5}, .Rise)
	hidden := sim.get(&run.simulation.state.minions, behind)
	hidden.pos.z = -12.6 // just past the wall's far face: within FIREBALL_RADIUS of the burst, through the wall
	place_prop(&run, BARREL, {11.5, 0, -10.5})
	place_prop(&run, CRATE, {10.8, 0, -13.3}) // behind the wall, as near the burst as the barrel
	fireball, _ := cast_on(&run, {aim = dmath.dir2({0, -1}), reach = g.reach_steps(8)})
	testing.expectf(t, abs(fireball.to.z - (-11.5 + g.FIREBALL_WALL_GAP)) < 0.05, "lands at %v", fireball.to)
	hold(&run, {}, int(g.FIREBALL_FLIGHT_TICKS) - 1)
	standing := bystander.pos
	hold(&run, {}, 6) // the burst, and a few ticks after it
	testing.expect_value(t, headless.run_events(&run, g.Event_Fireball_Burst), 1)
	minions := &run.simulation.state.minions
	testing.expect_value(t, sim.get(minions, beside).hp, g.MINION_HP - g.FIREBALL_DAMAGE)
	testing.expect_value(t, sim.get(minions, behind).hp, g.MINION_HP)
	barrel, _ := prop_at(&run, BARREL)
	moving := dmath.length(physics.body_linear_velocity(run.simulation.world.phys, barrel.body))
	testing.expectf(t, moving > 1, "the barrel by the burst moves at %v m/s", moving)
	crate, _ := prop_at(&run, CRATE)
	shielded := dmath.length(physics.body_linear_velocity(run.simulation.world.phys, crate.body))
	testing.expectf(t, shielded < 0.01, "the crate behind the wall moves at %v m/s", shielded)
	shoved := dmath.length(bystander.pos - standing)
	testing.expectf(t, shoved < 0.02, "the hero beside the burst moved %v m", shoved)
	scenarios.expect_synced(t, &run)
}

// No prop is blown over a wall: a crate (the lightest) right by a fireball's landing rises nowhere near a wall's
// 2.4 m, though the blast sends it off.
@(test)
a_blast_throws_no_prop_over_a_wall :: proc(t: ^testing.T) {
	run := ability_hero(.Mage)
	defer headless.run_end(&run)
	place_hero(&run, 0, {10, 0, -4}, {0, -1})
	place_prop(&run, CRATE, {10, 0, -8.3}) // by the landing, 4 m up the hall
	cast_on(&run, {aim = dmath.dir2({0, -1}), reach = g.reach_steps(4)})
	crate, _ := prop_at(&run, CRATE)
	highest, fastest: f32
	for _ in 0 ..< g.FIREBALL_FLIGHT_TICKS + g.TICK_HZ {
		headless.run_step(&run)
		bottom := physics.body_position(run.simulation.world.phys, crate.body).y - g.PROP_SPECS[.Crate].half.y
		speed := dmath.length(physics.body_linear_velocity(run.simulation.world.phys, crate.body))
		highest, fastest = dmath.max(highest, bottom), dmath.max(fastest, speed)
	}
	testing.expectf(t, fastest > 5, "the blast sent the crate off at %v m/s", fastest)
	testing.expectf(t, highest < 1.2, "the crate's bottom rose to %v m", highest)
	scenarios.expect_synced(t, &run)
}

// A press during the co-op pause starts nothing, and a button held through the resume is no press after it: no
// fireball, no cooldown spent.
@(test)
no_ability_from_a_paused_press :: proc(t: ^testing.T) {
	run := ability_hero(.Mage)
	defer headless.run_end(&run)
	mage := sim.slot_data(run.simulation, 0)
	headless.run_command(&run, 0, g.Command_Set_Paused{true})
	hold(&run, {buttons = {.Ability}}, 2)
	hold(&run, {}, 2)
	hold(&run, {buttons = {.Ability}}, 2) // and held into the resume
	headless.run_command(&run, [g.PLAYERS]g.Input{0 = {buttons = {.Ability}}}, 0, g.Command_Set_Paused{false})
	hold(&run, {buttons = {.Ability}}, int(g.FIREBALL_WINDUP_TICKS) + 2)
	testing.expect_value(t, mage.action, g.Action.None)
	testing.expect_value(t, mage.ability_ready, sim.Timer{})
	testing.expect_value(t, headless.run_events(&run, g.Event_Ability), 0)
	scenarios.expect_synced(t, &run)
}

// The scripted players (script.odin) use every ability the rules have, so the standard scenarios and the reference run
// roll back over each. What the script itself does, whatever the floor holds: in the reference run's length, each
// class's hero, up with its hands free, gets an Ability press, and a blocking Knight an Attack press (a charge). What the
// rules make of the presses that need nothing round the hero: the Knight's block and charge, the Rogue's roll and the
// Mage's fireball start, a fireball bursts, and a downed hero is revived (slot 3's dev revive). A Barbarian's press
// heaves only what its cone holds, which the floor decides: heave_test.odin holds the heave on its own set-ups.
@(test)
the_script_uses_every_ability :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, REFERENCE.seed)
	defer headless.run_end(&run)
	pressed: [g.Class]int // Ability presses the script gave a hero up and free, by its class
	used: [g.Class]int
	held: [g.PLAYERS]g.Buttons
	charge_presses, charges, bursts, revives := 0, 0, 0, 0
	for _ in 0 ..< REFERENCE.ticks {
		tick := run.simulation.tick + 1
		for slot in 0 ..< REFERENCE.players {
			hero := sim.slot_data(run.simulation, slot)
			if hero == nil do continue
			input := g.scripted_input(run.simulation.seed, slot, tick, &run.simulation.state, run.simulation.setup)
			if .Ability in input.buttons &&
			   .Ability not_in held[slot] &&
			   hero.action != .Down &&
			   g.can_start_ability(hero) {
				pressed[hero.class] += 1
			}
			if .Attack in input.buttons && .Attack not_in held[slot] && hero.action == .Block do charge_presses += 1
			held[slot] = input.buttons
		}
		headless.run_scripted(&run, REFERENCE.players)
		for &raw in sim.events_at(run.simulation, run.simulation.tick) {
			#partial switch event in sim.event_value(&raw, g.Event) {
			case g.Event_Ability:
				used[event.class] += 1
				if sim.player_data(&run.simulation.state.players, event.player).action == .Charge do charges += 1
			case g.Event_Fireball_Burst:
				bursts += 1
			case g.Event_Hero_Revived:
				revives += 1
			}
		}
	}
	for class in g.Class do testing.expectf(t, class == .Any || pressed[class] > 0, "no %v Ability press: %v", class, pressed)
	testing.expectf(t, charge_presses > 0, "no Attack press while a Knight blocks")
	for class in ([]g.Class{.Knight, .Rogue, .Mage}) do testing.expectf(t, used[class] > 0, "no %v ability: %v", class, used)
	testing.expectf(
		t,
		charges > 0 && bursts > 0 && revives > 0,
		"charges %d, bursts %d, revives %d",
		charges,
		bursts,
		revives,
	)
	scenarios.expect_synced(t, &run)
}

// A charging Knight's shield takes a blow from the front whole: a skeleton's swing landing on it, off to the side of the
// charge (out of its blast's reach, in the shield's arc), hurts nothing and clangs.
@(test)
a_charge_takes_blows_from_the_front :: proc(t: ^testing.T) {
	run := ability_hero(.Knight)
	defer headless.run_end(&run)
	knight := sim.slot_data(run.simulation, 0)
	hold(&run, {buttons = {.Ability}}, 2)
	side := [2]f32{0.6427876, 0.7660444} // 50 degrees off the facing (+X): in the shield's arc, clear of the blast
	handle := place_minion(&run, knight.pos + [3]f32{side.x, 0, side.y} * 1.6, .Attack, -side)
	state := &run.simulation.state
	swinger := sim.get(&state.minions, handle)
	swinger.target = sim.player_in_slot(run.simulation, 0)
	swinger.since = state.clock.time + 1 - sim.Game_Time(g.MINION_WINDUP_TICKS) // it lands on the next tick
	headless.run_pin(&run)
	hold(&run, {buttons = {.Ability, .Attack}}, 1) // the charge starts as the swing lands
	testing.expect_value(t, knight.action, g.Action.Charge)
	testing.expect_value(t, headless.run_events(&run, g.Event_Blocked), 1)
	testing.expect_value(t, knight.hp, g.HERO_HP)
	scenarios.expect_synced(t, &run)
}

// No ability while the hands are full or busy: a Knight carrying a crate doesn't block, a Mage carrying it doesn't
// cast, and a Rogue whose throw is still under way doesn't roll; none of them spends its cooldown.
@(test)
no_ability_while_carrying_or_throwing :: proc(t: ^testing.T) {
	run := ability_hero(.Knight)
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 0)
	place_prop(&run, CRATE, hero.pos + {1.4, 0, 0})
	press(&run, 0, .Interact)
	play(&run, {}, g.PICK_UP_S)
	testing.expect(t, hero.held != {}, "it carries the crate")
	hold(&run, {buttons = {.Ability}}, 4)
	testing.expect(t, hero.action != .Block, "a Knight carrying blocks")
	hold(&run, {}, 1)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Mage})
	press(&run, 0, .Ability)
	testing.expect(t, hero.action != .Cast, "a Mage carrying casts")
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Rogue})
	press(&run, 0, .Attack) // the throw
	play(&run, {}, g.THROW_WINDUP_S)
	testing.expect(t, hero.held == {} && hero.action == .Throw, "the crate left, the throw still under way")
	press(&run, 0, .Ability)
	testing.expect(t, hero.action != .Roll, "a Rogue mid-throw rolls")
	testing.expect_value(t, hero.ability_ready, sim.Timer{})
	scenarios.expect_synced(t, &run)
}

// A hero down starts no ability, whatever its class (a teammate up, so the floor doesn't restart).
@(test)
no_ability_while_down :: proc(t: ^testing.T) {
	for class in ([]g.Class{.Knight, .Mage, .Rogue}) {
		run := ability_hero(class, seated = 2)
		defer headless.run_end(&run)
		hero := sim.slot_data(run.simulation, 0)
		hurt(&run, 0, g.HERO_HP)
		hold(&run, {}, 1)
		hold(&run, {buttons = {.Ability, .Attack}}, 4)
		testing.expectf(t, hero.action == .Down, "a downed %v: %v", class, hero.action)
		testing.expect_value(t, hero.ability_ready, sim.Timer{})
		scenarios.expect_synced(t, &run)
	}
}

// The Rogue's roll and the Mage's fireball wait their cooldowns: pressed again once the first is over, nothing, and a
// tick before the cooldown runs out, nothing; once it has, again.
@(test)
the_roll_and_the_fireball_wait_their_cooldowns :: proc(t: ^testing.T) {
	Case :: struct {
		class:    g.Class,
		action:   g.Action,
		lasts:    u32,
		cooldown: u32,
	}
	cases := []Case {
		{.Rogue, .Roll, g.ROLL_TICKS, g.ROLL_COOLDOWN_TICKS},
		{.Mage, .Cast, g.FIREBALL_WINDUP_TICKS, g.FIREBALL_COOLDOWN_TICKS},
	}
	for c in cases {
		run := ability_hero(c.class)
		defer headless.run_end(&run)
		hero := sim.slot_data(run.simulation, 0)
		hold(&run, {buttons = {.Ability}}, 1) // the first: tick 0 of its cooldown
		testing.expect_value(t, hero.action, c.action)
		hold(&run, {}, int(c.lasts))
		hold(&run, {buttons = {.Ability}}, 1)
		testing.expectf(t, hero.action == .None, "%v again once over: %v", c.class, hero.action)
		hold(&run, {}, int(c.cooldown - c.lasts - 3))
		hold(&run, {buttons = {.Ability}}, 1) // tick cooldown - 1
		testing.expectf(t, hero.action == .None, "%v a tick early: %v", c.class, hero.action)
		hold(&run, {}, 1)
		hold(&run, {buttons = {.Ability}}, 1) // tick cooldown + 1
		testing.expectf(t, hero.action == c.action, "%v once the cooldown ran out: %v", c.class, hero.action)
		scenarios.expect_synced(t, &run)
	}
}

// An elite's blow lands on slot 0's hero on the next tick: a Warrior `offset` from it (on the floor plan) swinging at
// it, its windup all but run. The run is pinned.
@(private = "file")
elite_swings_at :: proc(run: ^headless.Run(g.Game), offset: [2]f32) {
	hero := sim.slot_data(run.simulation, 0)
	facing := dmath.normalize(-offset)
	handle := place_elite(run, .Warrior, hero.pos + {offset.x, 0, offset.y}, facing, .Idle)
	state := &run.simulation.state
	warrior := elite_of(run, handle)
	g.rouse_elite(run.simulation.world.phys, warrior, state.clock.time) // awake, as the rules wake a sleeper
	warrior.phase, warrior.target = .Attack, sim.player_in_slot(run.simulation, 0)
	warrior.since = state.clock.time + 1 - sim.Game_Time(g.ELITE_SPECS[.Warrior].windup)
	headless.run_pin(run)
}

// A skeleton Mage's bone bolt flies at slot 0's hero from `offset` away (on the floor plan, at FLIGHT_HEIGHT): a row of
// the bolts, a Mage's (its elite out of the way, rising). The run is pinned.
@(private = "file")
bone_bolt_at :: proc(run: ^headless.Run(g.Game), offset: [2]f32) {
	hero := sim.slot_data(run.simulation, 0)
	mage := place_elite(run, .Mage, spawn_of(run, 0) + {8, 0, 0}, {-1, 0}, .Rise)
	state := &run.simulation.state
	bolt, _, spawned := sim.spawn(&state.bolts)
	assert(spawned, "the bolt table is full")
	toward := dmath.normalize(-offset)
	bolt^ = {
		pos      = hero.pos + {offset.x, g.FLIGHT_HEIGHT, offset.y},
		vel      = [3]f32{toward.x, 0, toward.y} * g.BONE_BOLT_SPEED,
		cast_at  = state.clock.time,
		by_elite = mage,
	}
	headless.run_pin(run)
}

// A blocking Knight's shield takes an elite's blows as it takes a skeleton's: a Warrior's swing and a skeleton Mage's
// bone bolt from the front let BLOCK_TAKE through (the shield clangs: Event_Blocked), and the whole of either from
// behind.
@(test)
the_shield_takes_elite_blows_and_bone_bolts_from_the_front :: proc(t: ^testing.T) {
	for side in ([]f32{1, -1}) {
		for bolt in ([]bool{false, true}) {
			run := ability_hero(.Knight)
			defer headless.run_end(&run)
			clear_elites(&run)
			knight := sim.slot_data(run.simulation, 0)
			hold(&run, {buttons = {.Ability}}, 2)
			if bolt do bone_bolt_at(&run, {side * 1.5, 0})
			else do elite_swings_at(&run, {side * 1.5, 0})
			hold(&run, {buttons = {.Ability}}, 8) // the bolt flies 1.5 m in 6 ticks
			testing.expect_value(t, knight.action, g.Action.Block)
			damage := g.ELITE_SPECS[.Mage if bolt else .Warrior].damage
			blocked := i16(dmath.round(f32(damage) * g.BLOCK_TAKE))
			want := g.HERO_HP - (blocked if side > 0 else damage)
			what := "bone bolt" if bolt else "Warrior's swing"
			testing.expectf(t, knight.hp == want, "a %s from %v: %v HP, not %v", what, side, knight.hp, want)
			testing.expect_value(t, headless.run_events(&run, g.Event_Blocked), 1 if side > 0 else 0)
			scenarios.expect_synced(t, &run)
		}
	}
}

// The Rogue's roll lets an elite's blows by in its safe start as it lets a skeleton's: a Warrior's swing and a bone
// bolt landing early in the roll hurt nothing (the bolt bursts on it all the same), where the Rogue standing still
// takes each whole.
@(test)
the_roll_clears_elite_blows_and_bone_bolts :: proc(t: ^testing.T) {
	for rolling in ([]bool{true, false}) {
		for bolt in ([]bool{false, true}) {
			run := ability_hero(.Rogue)
			defer headless.run_end(&run)
			clear_elites(&run)
			rogue := sim.slot_data(run.simulation, 0)
			if rolling do hold(&run, {buttons = {.Ability}}, 3) // along its facing, +X: toward the blow
			if bolt do bone_bolt_at(&run, {1.5, 0})
			else do elite_swings_at(&run, {1.5, 0})
			hold(&run, {}, 8) // the bolt flies 1.5 m in 6 ticks (less when the Rogue rolls into it)
			age := u32(run.simulation.state.clock.time - rogue.action_started)
			testing.expect(
				t,
				!rolling || (rogue.action == .Roll && age < g.ROLL_SAFE_TICKS),
				"still in its safe start",
			)
			damage := g.ELITE_SPECS[.Mage if bolt else .Warrior].damage
			want := g.HERO_HP if rolling else g.HERO_HP - damage
			what := "bone bolt" if bolt else "Warrior's swing"
			testing.expectf(t, rogue.hp == want, "a %s, rolling %v: %v HP, not %v", what, rolling, rogue.hp, want)
			if bolt do testing.expect_value(t, headless.run_events(&run, g.Event_Bolt_Burst), 1)
			scenarios.expect_synced(t, &run)
		}
	}
}
