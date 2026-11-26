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

// The Rogue's roll goes along the stick (not the aim) at ROLL_SPEED; nothing hurts the Rogue in its first ROLL_SAFE_S,
// and a blow lands from then, though it still rolls.
@(test)
a_roll_is_safe_only_early :: proc(t: ^testing.T) {
	run := ability_hero(.Rogue)
	defer headless.run_end(&run)
	rogue := sim.slot_data(run.simulation, 0)
	hold(&run, {buttons = {.Ability}, move_z = 127, aim = dmath.dir2({1, 0})}, 1)
	testing.expect_value(t, rogue.action, g.Action.Roll)
	expect_facing(t, rogue, {0, 1})
	hold(&run, {}, int(g.ROLL_SAFE_TICKS) - 2)
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
// burst is blown away (physics.world_explode).
@(test)
a_fireball_stops_at_walls_and_moves_props :: proc(t: ^testing.T) {
	run := ability_hero(.Mage)
	defer headless.run_end(&run)
	place_hero(&run, 0, {10, 0, -8}, {0, -1}) // facing the wall at z = -12 (its hall face at -11.5)
	beside := place_minion(&run, {8.5, 0, -11}, .Rise)
	behind := place_minion(&run, {10, 0, -13.5}, .Rise)
	hidden := sim.get(&run.simulation.state.minions, behind)
	hidden.pos.z = -12.6 // just past the wall's far face: within FIREBALL_RADIUS of the burst, through the wall
	place_prop(&run, BARREL, {11.5, 0, -10.5})
	fireball, _ := cast_on(&run, {aim = dmath.dir2({0, -1}), reach = g.reach_steps(8)})
	testing.expectf(t, abs(fireball.to.z - (-11.5 + g.FIREBALL_WALL_GAP)) < 0.05, "lands at %v", fireball.to)
	hold(&run, {}, int(g.FIREBALL_FLIGHT_TICKS) + 1)
	minions := &run.simulation.state.minions
	testing.expect_value(t, sim.get(minions, beside).hp, g.MINION_HP - g.FIREBALL_DAMAGE)
	testing.expect_value(t, sim.get(minions, behind).hp, g.MINION_HP)
	barrel, _ := prop_at(&run, BARREL)
	moving := dmath.length(physics.body_linear_velocity(run.simulation.world.phys, barrel.body))
	testing.expectf(t, moving > 1, "the barrel by the burst moves at %v m/s", moving)
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
// roll back over each: in the reference run's length, each class's ability starts (a Knight's block and a charge among
// them), a fireball bursts and a downed hero is revived.
@(test)
the_script_uses_every_ability :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, REFERENCE.seed)
	defer headless.run_end(&run)
	used: [g.Class]int
	charges, bursts, revives := 0, 0, 0
	for _ in 0 ..< REFERENCE.ticks {
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
	for class in ([]g.Class{.Knight, .Mage, .Rogue}) do testing.expectf(t, used[class] > 0, "no %v ability: %v", class, used)
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
