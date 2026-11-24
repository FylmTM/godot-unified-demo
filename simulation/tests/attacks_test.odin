// The attacks' rule tests (attacks.odin, the class files, bolts.odin, and props.odin's prop_hits), each on a
// sync-tested run (headless.Run) that ends synced. Minions are raised in their Rise phase where a test needs them: a
// rising minion neither walks nor wakes, so it stands where it is put.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// A run with one hero of `class` standing at slot 0's spawn facing +X, and no minion.
@(private = "file")
hero_of :: proc(class: g.Class) -> headless.Run(g.Game) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{class})
	clear_minions(&run)
	place_hero(&run, 0, spawn_of(&run, 0), {1, 0})
	return run
}

// Slot 0 holds Attack for `ticks` ticks (one attack when it is no longer than the cooldown), then lets go.
@(private = "file")
attack_for :: proc(run: ^headless.Run(g.Game), ticks: u32) {
	held := [g.PLAYERS]g.Input {
		0 = {buttons = {.Attack}},
	}
	for _ in 0 ..< ticks do headless.run_step(run, held)
}

// Each class's attack strikes a minion in front of it, never one as near behind it.
@(test)
every_class_hits_in_front_not_behind :: proc(t: ^testing.T) {
	for class in ([]g.Class{.Knight, .Barbarian, .Mage, .Rogue}) {
		run := hero_of(class)
		defer headless.run_end(&run)
		spawn := spawn_of(&run, 0)
		front := place_minion(&run, spawn + {1.6, 0, 0}, .Rise)
		behind := place_minion(&run, spawn + {-1.6, 0, 0}, .Rise)
		attack_for(&run, g.CLASS_SPECS[class].windup + 16) // a bolt needs a few ticks to fly
		minions := &run.simulation.state.minions
		testing.expectf(t, sim.get(minions, front).hp < g.MINION_HP, "%v missed the minion in front", class)
		testing.expectf(t, sim.get(minions, behind).hp == g.MINION_HP, "%v struck the minion behind", class)
		scenarios.expect_synced(t, &run)
	}
}

// The Barbarian's cleave is wider than the Knight's sword: a minion 65° off the facing, in reach, is cleaved and not
// slashed.
@(test)
the_cleave_is_wider_than_the_sword :: proc(t: ^testing.T) {
	for class in ([]g.Class{.Knight, .Barbarian}) {
		run := hero_of(class)
		defer headless.run_end(&run)
		aside := place_minion(&run, spawn_of(&run, 0) + {0.68, 0, 1.45}, .Rise) // 1.6 m out, 65° off +X
		attack_for(&run, g.CLASS_SPECS[class].windup + 1)
		struck := sim.get(&run.simulation.state.minions, aside).hp < g.MINION_HP
		testing.expectf(t, struck == (class == .Barbarian), "%v's arc reached 65°: %v", class, struck)
		scenarios.expect_synced(t, &run)
	}
}

// A blow lands its windup after the attack starts, not a tick sooner; held, the attack repeats every cooldown.
@(test)
blows_land_after_the_windup_and_repeat_on_the_cooldown :: proc(t: ^testing.T) {
	run := hero_of(.Knight)
	defer headless.run_end(&run)
	spec := &g.CLASS_SPECS[.Knight]
	place_minion(&run, spawn_of(&run, 0) + {1.6, 0, 0}, .Rise)
	attack_for(&run, spec.windup)
	testing.expect_value(t, headless.run_events(&run, g.Event_Minion_Hit), 0)
	attack_for(&run, 1)
	testing.expect_value(t, headless.run_events(&run, g.Event_Minion_Hit), 1)
	attack_for(&run, 3 * spec.cooldown - spec.windup - 1) // three cooldowns from the first attack's start
	testing.expect_value(t, headless.run_events(&run, g.Event_Hero_Attacked), 3)
	scenarios.expect_synced(t, &run)
}

// Two floor spots `step` apart along +X or +Z with something of `mask` between them `height` above the floor (and, for
// a low cover pair, no wall at chest height), and the direction from the first to the second: the first such pair on a
// grid over the floor (false: none).
@(private = "file")
blocked_pair :: proc(
	run: ^headless.Run(g.Game),
	mask: u64,
	height, step: f32,
) -> (
	from, to: [3]f32,
	dir: [2]f32,
	found: bool,
) {
	world := run.simulation.world
	filter := physics.Filter {
		category = g.CAT_HERO,
		mask     = mask,
	}
	walls := physics.Filter {
		category = g.CAT_HERO,
		mask     = g.CAT_WALL,
	}
	for across in ([][2]f32{{1, 0}, {0, 1}}) {
		for x := f32(-24); x < 26; x += 0.5 {
			for z := f32(-22); z < 6; z += 0.5 {
				near := g.floor_spot(world, {x, 0, z}, 0.1) or_continue
				far := g.floor_spot(world, near.point + [3]f32{across.x, 0, across.y} * step, 0.1) or_continue
				lift := [3]f32{0, height, 0}
				_, blocked := physics.world_cast_ray_closest(
					world.phys,
					near.point + lift,
					far.point - near.point,
					filter,
				)
				if !blocked do continue
				chest := [3]f32{0, g.CHEST_HEIGHT, 0}
				_, walled := physics.world_cast_ray_closest(
					world.phys,
					near.point + chest,
					far.point - near.point,
					walls,
				)
				if mask == g.CAT_LOW && walled do continue
				return near.point, far.point, across, true
			}
		}
	}
	return
}

// A wall between a hero and a minion in reach shields the minion from a blow and from a bolt (and its burst).
@(test)
walls_block_blows_and_bolts :: proc(t: ^testing.T) {
	for class in ([]g.Class{.Barbarian, .Mage}) {
		run := hero_of(class)
		defer headless.run_end(&run)
		from, to, dir, found := blocked_pair(&run, g.CAT_WALL, g.CHEST_HEIGHT, 2.4) // a wall and its margins
		if !testing.expect(t, found, "Floor 1 has a wall with floor on both sides") do return
		place_hero(&run, 0, from, dir)
		shielded := place_minion(&run, to, .Rise)
		attack_for(&run, g.CLASS_SPECS[class].windup + 16)
		testing.expect_value(t, sim.get(&run.simulation.state.minions, shielded).hp, g.MINION_HP)
		scenarios.expect_synced(t, &run)
	}
}

// A bolt flies at chest height, over low cover, and strikes the minion beyond it.
@(test)
bolts_fly_over_low_cover :: proc(t: ^testing.T) {
	run := hero_of(.Mage)
	defer headless.run_end(&run)
	from, to, dir, found := blocked_pair(&run, g.CAT_LOW, 0.5, 3)
	if !testing.expect(t, found, "Floor 1 has low cover with floor on both sides") do return
	place_hero(&run, 0, from, dir)
	beyond := place_minion(&run, to, .Rise)
	attack_for(&run, g.CLASS_SPECS[.Mage].windup + 24)
	testing.expect(
		t,
		sim.get(&run.simulation.state.minions, beyond).hp < g.MINION_HP,
		"the bolt struck over the cover",
	)
	testing.expect_value(t, headless.run_events(&run, g.Event_Bolt_Burst), 1)
	scenarios.expect_synced(t, &run)
}

// The crossbow resolves on the picture its shooter saw: a minion knocked across the shot's line, past it at the strike
// tick, is hit when the shooter's input says its screen was enough ticks behind (sim.Seen), and missed with no delay;
// the look back is capped at MAX_REWIND_S, however late a client claims to be.
@(test)
the_crossbow_shoots_where_the_shooter_saw :: proc(t: ^testing.T) {
	Case :: struct {
		seen:   u8,
		past:   f32, // how far past the line's side the minion is at the strike (metres beyond its radius' reach)
		struck: bool,
	}
	cases := []Case {
		{seen = 0, past = 0.6, struck = false}, // no delay: it is past the line
		{seen = 5, past = 0.6, struck = true}, // 4.5 ticks back it stood on it
		{seen = 40, past = 1.3, struck = false}, // 39.5 ticks back it would; the cap stops the look at 0.125 s
	}
	for shot in cases {
		run := hero_of(.Rogue)
		defer headless.run_end(&run)
		spawn := spawn_of(&run, 0)
		crossing := place_minion(&run, spawn + {4, 0, 0}, .Rise)
		seen := [g.PLAYERS]g.Input {
			0 = {buttons = {.Attack}, seen = sim.Seen(shot.seen)},
		}
		for _ in 0 ..< g.CLASS_SPECS[.Rogue].windup do headless.run_step(&run, seen)
		minion := sim.get(&run.simulation.state.minions, crossing)
		knock := [2]f32{0, 6}
		at, _ := g.floor_spot(run.simulation.world, spawn + {4, 0, shot.past - knock.y / g.TICK_HZ}, 0.2)
		minion.pos, minion.poly, minion.knock = at.point, at.poly, knock // it moves knock / TICK_HZ on the strike tick
		headless.run_pin(&run)
		headless.run_step(&run, seen)
		struck := minion.hp < g.MINION_HP
		testing.expectf(t, struck == shot.struck, "seen %d, %v m past: struck %v", shot.seen, shot.past, struck)
		shots := headless.run_events(&run, g.Event_Crossbow_Shot)
		testing.expect_value(t, shots, 1)
		scenarios.expect_synced(t, &run)
	}
}

// A thrown prop hurts each minion its footprint meets once, and loses speed with each.
@(test)
a_thrown_prop_hurts_each_minion_once :: proc(t: ^testing.T) {
	run := hero_of(.Knight)
	defer headless.run_end(&run)
	spawn := spawn_of(&run, 0)
	place_prop(&run, BARREL, spawn + {1.4, 0, 0})
	press(&run, 0, .Interact)
	play(&run, {}, 0.75)
	first := place_minion(&run, spawn + {4, 0, 0}, .Rise)
	second := place_minion(&run, spawn + {5.5, 0, 0}, .Rise)
	press(&run, 0, .Attack)
	for _ in 0 ..< g.THROW_WINDUP_TICKS do headless.run_step(&run)
	barrel, _ := prop_at(&run, BARREL)
	thrown := dmath.length(physics.body_linear_velocity(run.simulation.world.phys, barrel.body).xz)
	play(&run, {}, 0.5)
	minions := &run.simulation.state.minions
	testing.expect_value(t, sim.get(minions, first).hp, g.MINION_HP - g.PROP_HIT_DAMAGE)
	testing.expect_value(t, sim.get(minions, second).hp, g.MINION_HP - g.PROP_HIT_DAMAGE)
	testing.expect_value(t, int(barrel.hits.count), 2)
	after := dmath.length(physics.body_linear_velocity(run.simulation.world.phys, barrel.body).xz)
	testing.expectf(t, after < thrown * g.PROP_HIT_KEEP, "it flew on at %v m/s from %v", after, thrown)
	scenarios.expect_synced(t, &run)
}
