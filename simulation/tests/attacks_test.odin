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

// A run with slot 0's hero of `class` standing at its spawn facing +X (and `seated` heroes in all), and no minion.
@(private = "file")
hero_of :: proc(class: g.Class, seated := 1) -> headless.Run(g.Game) {
	run := headless.run_begin(&g.GAME, 1, seated = seated)
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

// A blow lands its windup after the attack starts, not a tick sooner; held, the next attack starts exactly a cooldown
// after the first.
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
	attack_for(&run, spec.cooldown - spec.windup - 1) // up to the tick before a cooldown from the first start
	testing.expect_value(t, headless.run_events(&run, g.Event_Hero_Attacked), 1)
	attack_for(&run, 1)
	testing.expect_value(t, headless.run_events(&run, g.Event_Hero_Attacked), 2)
	scenarios.expect_synced(t, &run)
}

// Something touching the hero is struck whatever the arc: a minion at the Knight's back, touching it, is hit; one half
// a metre further back is not.
@(test)
a_blow_strikes_what_touches_the_hero :: proc(t: ^testing.T) {
	touching := g.HERO_RADIUS + g.MINION_RADIUS + g.STRIKE_TOUCH / 2
	for gap in ([]f32{0, 0.5}) {
		run := hero_of(.Knight)
		defer headless.run_end(&run)
		behind := place_minion(&run, spawn_of(&run, 0) - {touching + gap, 0, 0}, .Rise)
		attack_for(&run, g.CLASS_SPECS[.Knight].windup + 1)
		struck := sim.get(&run.simulation.state.minions, behind).hp < g.MINION_HP
		testing.expectf(t, struck == (gap == 0), "the minion %v m further back: struck %v", gap, struck)
		scenarios.expect_synced(t, &run)
	}
}

// The floor plan's extent: the navigation mesh's corners.
@(private = "file")
mesh_extent :: proc(run: ^headless.Run(g.Game)) -> (low, high: [2]f32) {
	low, high = {max(f32), max(f32)}, {-max(f32), -max(f32)}
	for vertex in run.simulation.world.mesh.vertices {
		low = {dmath.min(low.x, vertex.x), dmath.min(low.y, vertex.z)}
		high = {dmath.max(high.x, vertex.x), dmath.max(high.y, vertex.z)}
	}
	return
}

// Two floor spots `step` apart along +X or +Z with something of `mask` between them `height` above the floor (and, for
// a low cover pair, no wall at chest or flight height), and the direction from the first to the second: the first such
// pair on a grid over the floor's extent (false: none).
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
	low, high := mesh_extent(run)
	for across in ([][2]f32{{1, 0}, {0, 1}}) {
		for x := low.x; x < high.x; x += 0.5 {
			for z := low.y; z < high.y; z += 0.5 {
				near := g.floor_spot(world, {x, 0, z}, 0.1) or_continue
				far := g.floor_spot(world, near.point + [3]f32{across.x, 0, across.y} * step, 0.1) or_continue
				_, blocked := physics.world_cast_ray_closest(
					world.phys,
					near.point + {0, height, 0},
					far.point - near.point,
					filter,
				)
				if !blocked do continue
				if mask == g.CAT_LOW {
					walled := false
					for above in ([]f32{g.CHEST_HEIGHT, g.FLIGHT_HEIGHT}) {
						_, hit := physics.world_cast_ray_closest(
							world.phys,
							near.point + {0, above, 0},
							far.point - near.point,
							walls,
						)
						walled ||= hit
					}
					if walled do continue
				}
				return near.point, far.point, across, true
			}
		}
	}
	return
}

// A wall between a hero and a minion in reach shields the minion from a blow, a bolt (which bursts on the wall) and a
// shot (which stops at it), and a prop beside it from the blow.
@(test)
walls_shield_from_blows_bolts_and_shots :: proc(t: ^testing.T) {
	for class in ([]g.Class{.Barbarian, .Mage, .Rogue}) {
		run := hero_of(class)
		defer headless.run_end(&run)
		from, to, dir, found := blocked_pair(&run, g.CAT_WALL, g.FLIGHT_HEIGHT, 2.4) // a wall and its margins
		if !testing.expect(t, found, "Floor 1 has a wall with floor on both sides") do return
		place_hero(&run, 0, from, dir)
		shielded := place_minion(&run, to, .Rise)
		attack_for(&run, g.CLASS_SPECS[class].windup + 16)
		testing.expectf(t, sim.get(&run.simulation.state.minions, shielded).hp == g.MINION_HP, "%v struck", class)
		#partial switch class {
		case .Mage:
			testing.expect_value(t, headless.run_events(&run, g.Event_Bolt_Burst), 1)
		case .Rogue:
			shot, _ := headless.run_last_event(&run, g.Event_Crossbow_Shot)
			testing.expect_value(t, headless.run_events(&run, g.Event_Crossbow_Shot), 1)
			testing.expect(t, !shot.hit, "the shot hit through the wall")
		}
		scenarios.expect_synced(t, &run)
	}
}

// A wall between a hero and a prop in its blow's reach shields the prop: it isn't shoved.
@(test)
walls_shield_props_from_blows :: proc(t: ^testing.T) {
	run := hero_of(.Barbarian)
	defer headless.run_end(&run)
	from, to, dir, found := blocked_pair(&run, g.CAT_WALL, g.CHEST_HEIGHT, 2.4)
	if !testing.expect(t, found, "Floor 1 has a wall with floor on both sides") do return
	place_hero(&run, 0, from, dir)
	place_prop(&run, CRATE, to)
	attack_for(&run, g.CLASS_SPECS[.Barbarian].windup + 1)
	crate, _ := prop_at(&run, CRATE)
	moving := dmath.length(physics.body_linear_velocity(run.simulation.world.phys, crate.body))
	testing.expectf(t, moving < 0.01, "the crate behind the wall moves at %v m/s", moving)
	scenarios.expect_synced(t, &run)
}

// A bolt and a shot fly over low cover and strike the minion beyond it.
@(test)
bolts_and_shots_fly_over_low_cover :: proc(t: ^testing.T) {
	for class in ([]g.Class{.Mage, .Rogue}) {
		run := hero_of(class)
		defer headless.run_end(&run)
		from, to, dir, found := blocked_pair(&run, g.CAT_LOW, 0.5, 3)
		if !testing.expect(t, found, "Floor 1 has low cover with floor on both sides") do return
		place_hero(&run, 0, from, dir)
		beyond := place_minion(&run, to, .Rise)
		attack_for(&run, g.CLASS_SPECS[class].windup + 24)
		struck := sim.get(&run.simulation.state.minions, beyond).hp < g.MINION_HP
		testing.expectf(t, struck, "%v's flight stopped at the cover", class)
		scenarios.expect_synced(t, &run)
	}
}

// Low cover stays low and resting light props stay under the flight: a bolt's orb clears them by FLIGHT_CLEARANCE, and
// a heavy crate stands into it.
@(test)
the_flight_clears_low_things_and_meets_heavy_crates :: proc(t: ^testing.T) {
	under := g.FLIGHT_HEIGHT - g.BOLT_RADIUS - g.FLIGHT_CLEARANCE
	testing.expect(t, g.LOW_COVER_TOP <= under, "low cover reaches the orb")
	for kind in ([]g.Prop_Kind{.Barrel, .Crate}) {
		top := 2 * g.PROP_SPECS[kind].half.y
		testing.expectf(t, top <= under, "a resting %v (%v m) reaches the orb", kind, top)
	}
	testing.expect(t, 2 * g.PROP_SPECS[.Heavy_Crate].half.y > g.FLIGHT_HEIGHT, "a heavy crate is flown over")
}

// A resting crate is flown over (the minion beyond is struck, the crate stays); a heavy crate is met: shoved, and the
// minion behind it spared. For the bolt and the shot alike.
@(test)
bolts_and_shots_fly_over_crates_and_meet_heavy_crates :: proc(t: ^testing.T) {
	for class in ([]g.Class{.Mage, .Rogue}) {
		for index in ([]int{CRATE, HEAVY_CRATE}) {
			run := hero_of(class)
			defer headless.run_end(&run)
			spawn := spawn_of(&run, 0)
			place_prop(&run, index, spawn + {2.5, 0, 0})
			beyond := place_minion(&run, spawn + {5, 0, 0}, .Rise)
			attack_for(&run, g.CLASS_SPECS[class].windup + 32) // the bolt flies 5 m
			prop, _ := prop_at(&run, index)
			heavy := index == HEAVY_CRATE
			shoved := physics.body_position(run.simulation.world.phys, prop.body).x - (spawn.x + 2.5) > 0.05
			struck := sim.get(&run.simulation.state.minions, beyond).hp < g.MINION_HP
			testing.expectf(t, shoved == heavy, "%v, prop %d: shoved %v", class, index, shoved)
			testing.expectf(t, struck != heavy, "%v, prop %d: the minion beyond struck %v", class, index, struck)
			scenarios.expect_synced(t, &run)
		}
	}
}

// The crossbow never pierces: of two minions in its line, only the nearer is hit.
@(test)
the_crossbow_never_pierces :: proc(t: ^testing.T) {
	run := hero_of(.Rogue)
	defer headless.run_end(&run)
	spawn := spawn_of(&run, 0)
	near := place_minion(&run, spawn + {3, 0, 0}, .Rise)
	far := place_minion(&run, spawn + {5, 0, 0}, .Rise)
	attack_for(&run, g.CLASS_SPECS[.Rogue].windup + 1)
	minions := &run.simulation.state.minions
	testing.expect_value(t, sim.get(minions, near).hp, g.MINION_HP - g.CLASS_SPECS[.Rogue].damage)
	testing.expect_value(t, sim.get(minions, far).hp, g.MINION_HP)
	scenarios.expect_synced(t, &run)
}

// A bolt's burst hurts each other minion within BURST_RADIUS for BURST_DAMAGE and knocks it away from the burst; one
// farther is untouched.
@(test)
a_burst_hurts_and_knocks_its_neighbours :: proc(t: ^testing.T) {
	run := hero_of(.Mage)
	defer headless.run_end(&run)
	spawn := spawn_of(&run, 0)
	struck := place_minion(&run, spawn + {4, 0, 0}, .Rise)
	beside := place_minion(&run, spawn + {4, 0, 1}, .Rise)
	apart := place_minion(&run, spawn + {4, 0, -2.5}, .Rise)
	held := [g.PLAYERS]g.Input {
		0 = {buttons = {.Attack}},
	}
	for headless.run_events(&run, g.Event_Bolt_Burst) == 0 do headless.run_step(&run, held)
	minions := &run.simulation.state.minions
	burst, _ := headless.run_last_event(&run, g.Event_Bolt_Burst)
	testing.expect_value(t, sim.get(minions, struck).hp, g.MINION_HP - g.CLASS_SPECS[.Mage].damage)
	neighbour := sim.get(minions, beside)
	testing.expect_value(t, neighbour.hp, g.MINION_HP - g.BURST_DAMAGE)
	away := dmath.normalize(neighbour.pos.xz - burst.position.xz)
	knocked := dmath.length(neighbour.knock - away * g.BURST_KNOCK) < 0.05
	testing.expectf(t, knocked, "knocked %v, not away %v", neighbour.knock, away)
	testing.expect_value(t, sim.get(minions, apart).hp, g.MINION_HP)
	scenarios.expect_synced(t, &run)
}

// A bolt that meets nothing fizzles BOLT_LIFE_S after its cast, with no burst.
@(test)
a_bolt_fizzles_at_its_life :: proc(t: ^testing.T) {
	run := hero_of(.Mage)
	defer headless.run_end(&run)
	state := &run.simulation.state
	bolt, _, _ := sim.spawn(&state.bolts) // standing still: it meets nothing
	bolt^ = {
		pos     = spawn_of(&run, 0) + {0, g.FLIGHT_HEIGHT, 0},
		cast_at = state.clock.time,
		caster  = sim.player_in_slot(run.simulation, 0),
	}
	headless.run_pin(&run)
	for _ in 0 ..< g.BOLT_LIFE_TICKS - 1 do headless.run_step(&run)
	testing.expect_value(t, int(state.bolts.count), 1)
	headless.run_step(&run)
	testing.expect_value(t, int(state.bolts.count), 0)
	testing.expect_value(t, headless.run_events(&run, g.Event_Bolt_Burst), 0)
	scenarios.expect_synced(t, &run)
}

// With every bolt row taken, the Mage's spell fizzles: no bolt more, no burst.
@(test)
a_full_bolts_table_fizzles_the_spell :: proc(t: ^testing.T) {
	run := hero_of(.Mage)
	defer headless.run_end(&run)
	state := &run.simulation.state
	for _ in 0 ..< g.MAX_BOLTS {
		bolt, _, _ := sim.spawn(&state.bolts)
		bolt^ = {
			pos     = spawn_of(&run, 0) + {0, g.FLIGHT_HEIGHT, -1},
			cast_at = state.clock.time,
		}
	}
	headless.run_pin(&run)
	attack_for(&run, g.CLASS_SPECS[.Mage].windup + 2)
	testing.expect_value(t, int(state.bolts.count), g.MAX_BOLTS)
	testing.expect_value(t, headless.run_events(&run, g.Event_Bolt_Burst), 0)
	scenarios.expect_synced(t, &run)
}

// A hero attacking moves at ATTACK_SPEED of its speed, and at its full speed again once the attack ends.
@(test)
attacking_slows_the_hero :: proc(t: ^testing.T) {
	run := hero_of(.Knight)
	defer headless.run_end(&run)
	hero := sim.slot_data(run.simulation, 0)
	max_speed := g.CLASS_SPECS[.Knight].max_speed
	attacking := [g.PLAYERS]g.Input {
		0 = {move_x = 127, buttons = {.Attack}},
	}
	for _ in 0 ..< 20 do headless.run_step(&run, attacking)
	want := max_speed * g.ATTACK_SPEED
	testing.expectf(t, abs(hero.vel.x - want) < 0.15, "attacks at %v m/s, not %v", hero.vel.x, want)
	play(&run, {0 = {move_x = 127}}, 0.5)
	testing.expectf(t, abs(hero.vel.x - max_speed) < 0.15, "walks at %v m/s, not %v", hero.vel.x, max_speed)
	scenarios.expect_synced(t, &run)
}

// A hero attacking can't grab: Interact's press during the attack takes nothing.
@(test)
no_grab_while_attacking :: proc(t: ^testing.T) {
	run := hero_of(.Knight)
	defer headless.run_end(&run)
	place_prop(&run, CRATE, spawn_of(&run, 0) + {1.4, 0, 0})
	attack_for(&run, 3)
	press(&run, 0, .Interact)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).held, sim.Handle(g.Prop){})
	scenarios.expect_synced(t, &run)
}

// A hero downed during its windup lands no blow (a second hero stays up, so the floor doesn't restart).
@(test)
going_down_cuts_an_attack_short :: proc(t: ^testing.T) {
	run := hero_of(.Knight, seated = 2)
	defer headless.run_end(&run)
	play(&run, {}, g.SPAWN_GRACE_S) // a hero rising is unhurt for its grace
	front := place_minion(&run, spawn_of(&run, 0) + {1.6, 0, 0}, .Rise)
	attack_for(&run, 2)
	hurt(&run, 0, g.HERO_HP)
	attack_for(&run, g.CLASS_SPECS[.Knight].windup)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).action, g.Action.Down)
	testing.expect_value(t, sim.get(&run.simulation.state.minions, front).hp, g.MINION_HP)
	scenarios.expect_synced(t, &run)
}

// A class change mid-attack ends the attack: the new class's blow never lands on the old one's clock.
@(test)
a_class_change_ends_the_attack :: proc(t: ^testing.T) {
	run := hero_of(.Knight)
	defer headless.run_end(&run)
	front := place_minion(&run, spawn_of(&run, 0) + {1.6, 0, 0}, .Rise)
	attack_for(&run, 2)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Barbarian})
	testing.expect_value(t, sim.slot_data(run.simulation, 0).action, g.Action.None)
	for _ in 0 ..< g.CLASS_SPECS[.Barbarian].windup do headless.run_step(&run)
	testing.expect_value(t, sim.get(&run.simulation.state.minions, front).hp, g.MINION_HP)
	scenarios.expect_synced(t, &run)
}

// The crossbow resolves on the picture its shooter saw: a minion knocked across the shot's line, past it at the strike
// tick, is hit when the shooter's input says its screen was enough ticks behind (sim.Seen), and missed with no delay;
// the look back is capped at MAX_REWIND_S, however late a client claims to be. The run is sync-tested, so the rewind
// runs under rollback too.
@(test)
the_crossbow_shoots_where_the_shooter_saw :: proc(t: ^testing.T) {
	Case :: struct {
		seen:   u8,
		past:   f32, // the minion's centre's offset from the shot's line at the strike (metres, across it)
		struck: bool,
	}
	cases := []Case {
		{seen = 0, past = 0.6, struck = false}, // no delay: it is past the line
		{seen = 5, past = 0.6, struck = true}, // 4.5 ticks back it stood on it
		{seen = 14, past = 1.3, struck = false}, // 13.5 ticks back (0.21 s) it would; the cap stops the look at 0.125 s
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
		at, on_floor := g.floor_spot(run.simulation.world, spawn + {4, 0, shot.past - knock.y / g.TICK_HZ}, 0.2)
		testing.expect(t, on_floor, "the crossing minion stands on the floor")
		minion.pos, minion.poly, minion.knock = at.point, at.poly, knock // it moves knock / TICK_HZ on the strike tick
		headless.run_pin(&run)
		headless.run_step(&run, seen)
		struck := minion.hp < g.MINION_HP
		testing.expectf(t, struck == shot.struck, "seen %d, %v m past: struck %v", shot.seen, shot.past, struck)
		testing.expect_value(t, headless.run_events(&run, g.Event_Crossbow_Shot), 1)
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

// The barrel, at rest at `at`, sent along +X at `speed` as slot 0's throw (its throw running when `thrown`), the run
// pinned.
@(private = "file")
fling_barrel :: proc(run: ^headless.Run(g.Game), at: [3]f32, speed: f32, thrown: bool) -> ^g.Prop {
	place_prop(run, BARREL, at)
	barrel, _ := prop_at(run, BARREL)
	now := run.simulation.state.clock.time
	barrel.thrown_by = sim.player_in_slot(run.simulation, 0)
	if thrown do barrel.thrown = {
		start  = now,
		target = now + sim.Game_Time(g.THROWN_TICKS),
	}
	physics.body_set_linear_velocity(run.simulation.world.phys, barrel.body, {speed, 0, 0})
	headless.run_pin(run)
	return barrel
}

// A throw hurts at most PROP_HITS_MAX minions, however fast it flies.
@(test)
a_throw_hurts_at_most_its_cap :: proc(t: ^testing.T) {
	run := hero_of(.Knight)
	defer headless.run_end(&run)
	spawn := spawn_of(&run, 0)
	row: [8]sim.Handle(g.Minion) // two rows of four along the flight, both within the barrel's reach
	for &minion, i in row {
		side: f32 = 0.45 if i % 2 == 0 else -0.45
		minion = place_minion(&run, spawn + {2 + f32(i / 2), 0, side}, .Rise)
	}
	barrel := fling_barrel(&run, spawn + {1.2, 0, 0}, 40, thrown = true) // fast enough for every hit's PROP_HIT_KEEP
	play(&run, {}, 0.25)
	hurt := 0
	for minion in row {
		if sim.get(&run.simulation.state.minions, minion).hp < g.MINION_HP do hurt += 1
	}
	testing.expect_value(t, hurt, g.PROP_HITS_MAX)
	testing.expect_value(t, int(barrel.hits.count), g.PROP_HITS_MAX)
	scenarios.expect_synced(t, &run)
}

// A prop hurts only while its throw runs and it flies faster than PROP_HIT_SPEED: a slow throw, and a fast prop whose
// throw ran out, hurt nobody.
@(test)
a_slow_or_spent_throw_hurts_nobody :: proc(t: ^testing.T) {
	for fast in ([]bool{false, true}) {
		run := hero_of(.Knight)
		defer headless.run_end(&run)
		spawn := spawn_of(&run, 0)
		minion := place_minion(&run, spawn + {2.5, 0, 0}, .Rise)
		fling_barrel(&run, spawn + {1.2, 0, 0}, 10 if fast else g.PROP_HIT_SPEED * 0.75, thrown = !fast)
		play(&run, {}, 0.5)
		testing.expectf(t, sim.get(&run.simulation.state.minions, minion).hp == g.MINION_HP, "fast %v: hurt", fast)
		scenarios.expect_synced(t, &run)
	}
}
