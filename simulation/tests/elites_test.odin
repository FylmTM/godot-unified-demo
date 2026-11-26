// The elites' rule tests (elites.odin and a file per kind), each on a sync-tested run (headless.Run) that ends synced,
// so every one also rolls back over what it checks: the elites' Box3D bodies, their deaths and the floor's restart
// included (check_refs after every restore). A test raises an elite where it needs one (place_elite): rising, it stands
// where it is put and wakes nobody; the floor's own elites (its markers') sleep out of sight of the first room.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// An elite of `kind` on the walkable floor nearest `near`, facing `facing`, in `phase`, pinned there.
place_elite :: proc(
	run: ^headless.Run(g.Game),
	kind: g.Elite_Kind,
	near: [3]f32,
	facing: [2]f32,
	phase: g.Elite_Phase,
) -> sim.Handle(g.Elite) {
	spot, on_floor := g.floor_spot(floor_of(run), near, 2)
	assert(on_floor, "a test's elite is off the floor")
	state := &run.simulation.state
	handle, spawned := g.spawn_elite(state, run.simulation.world, kind, spot.point, facing, phase, state.clock.time)
	assert(spawned, "the elite table is full")
	headless.run_pin(run)
	return handle
}

// The elite `handle` names (nil: gone).
elite_of :: proc(run: ^headless.Run(g.Game), handle: sim.Handle(g.Elite)) -> ^g.Elite {
	return sim.get(&run.simulation.state.elites, handle)
}

// Every elite goes, bodies and all (the floor's sleepers, for a test of its own), and the run is pinned.
clear_elites :: proc(run: ^headless.Run(g.Game)) {
	physics.despawn_all(run.simulation.world.phys, &run.simulation.state.elites)
	headless.run_pin(run)
}

// A run with slot 0's hero of `class` at its spawn facing `facing`, alone, with no minion and no elite.
@(private = "file")
alone_as :: proc(class: g.Class, facing := [2]f32{1, 0}) -> headless.Run(g.Game) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{class})
	clear_minions(&run)
	clear_elites(&run)
	place_hero(&run, 0, spawn_of(&run, 0), facing)
	return run
}

// Slot 0 holds Attack for `ticks` ticks with its aim along `facing`.
@(private = "file")
hold_attack :: proc(run: ^headless.Run(g.Game), ticks: u32, facing: [2]f32) {
	held := [g.PLAYERS]g.Input {
		0 = {buttons = {.Attack}, aim = dmath.dir2(facing)},
	}
	for _ in 0 ..< ticks do headless.run_step(run, held)
}

// A Knight's blow at a Warrior `offset` from it (on the floor plan), the Knight facing `knight_facing` and the
// Warrior `warrior_facing`, with its guard broken first when `broken`: what the Warrior's health is after it. The
// Warrior is placed asleep the tick before the blow lands, so it has turned no more than a tick's turn.
@(private = "file")
knight_blow_at_warrior :: proc(
	t: ^testing.T,
	offset: [2]f32,
	knight_facing, warrior_facing: [2]f32,
	broken := false,
) -> i16 {
	run := alone_as(.Knight, knight_facing)
	defer headless.run_end(&run)
	spawn := spawn_of(&run, 0)
	windup := g.CLASS_SPECS[.Knight].windup // the attack's first tick is its age 0: it lands on the windup + 1-th
	hold_attack(&run, windup - 1 if broken else windup, knight_facing)
	warrior := place_elite(&run, .Warrior, spawn + {offset.x, 0, offset.y}, warrior_facing, .Idle)
	if broken {
		headless.run_command(&run, 0, g.Command_Dev_Break_Guards{}) // a tick of its own (Attack let go: no new press)
		testing.expect_value(t, headless.run_events(&run, g.Event_Guard_Broken), 1)
	}
	hold_attack(&run, 1, knight_facing)
	testing.expect_value(t, headless.run_events(&run, g.Event_Elite_Hit), 1)
	scenarios.expect_synced(t, &run)
	return elite_of(&run, warrior).hp
}

// A Warrior's shield takes all but ELITE_GUARD_TAKE of a blow from its front, never knocking it, and none of one from
// behind. It judges where the blow comes from, never where the hero faces: a Knight in front of it facing away, its
// back to the shield, strikes what touches it (STRIKE_TOUCH) and is guarded all the same.
@(test)
a_warriors_shield_guards_its_front :: proc(t: ^testing.T) {
	sword := g.CLASS_SPECS[.Knight].damage
	full := g.ELITE_SPECS[.Warrior].hp
	front := knight_blow_at_warrior(t, {1.4, 0}, {1, 0}, {-1, 0})
	testing.expectf(t, front == full - g.guard_take(sword), "from the front: %d HP", front)
	testing.expect(t, g.guard_take(sword) < sword / 3, "a guarded blow takes a quarter")
	behind := knight_blow_at_warrior(t, {1.4, 0}, {1, 0}, {1, 0})
	testing.expectf(t, behind == full - sword, "from behind: %d HP", behind)
	touching := knight_blow_at_warrior(t, {0.95, 0}, {-1, 0}, {-1, 0})
	testing.expectf(t, touching == full - g.guard_take(sword), "touching, the Knight facing away: %d HP", touching)
}

// A broken guard (dev_break_guards: break_guard, the entry a charge and a fireball will call) lets a blow from the
// front through whole, for GUARD_BREAK_S.
@(test)
a_broken_guard_lets_the_front_through :: proc(t: ^testing.T) {
	sword := g.CLASS_SPECS[.Knight].damage
	broken := knight_blow_at_warrior(t, {1.4, 0}, {1, 0}, {-1, 0}, broken = true)
	testing.expectf(t, broken == g.ELITE_SPECS[.Warrior].hp - sword, "the guard broken: %d HP", broken)
}

// A thrown prop that hits a Warrior from the front breaks its guard (Event_Guard_Broken) and hurts it whole, as it
// hurts a minion, its thrower's blow; the guard holds again GUARD_BREAK_S on.
@(test)
a_thrown_prop_breaks_the_guard :: proc(t: ^testing.T) {
	run := alone_as(.Knight)
	defer headless.run_end(&run)
	spawn := spawn_of(&run, 0)
	warrior := place_elite(&run, .Warrior, spawn + {4, 0, 0}, {-1, 0}, .Rise)
	place_prop(&run, BARREL, spawn + {1.4, 0, 0})
	press(&run, 0, .Interact)
	play(&run, {}, 0.75)
	press(&run, 0, .Attack)
	hit_at := run.simulation.state.clock.time
	play(&run, {}, 0.5)
	testing.expect_value(t, headless.run_events(&run, g.Event_Guard_Broken), 1)
	elite := elite_of(&run, warrior)
	testing.expect_value(t, elite.hp, g.ELITE_SPECS[.Warrior].hp - g.PROP_HIT_DAMAGE)
	testing.expect(t, sim.timer_running(run.simulation.state.clock.time, elite.guard_down), "the guard is down")
	for elite.guard_down.target > run.simulation.state.clock.time do headless.run_step(&run)
	testing.expectf(
		t,
		u32(run.simulation.state.clock.time - hit_at) <= g.GUARD_BREAK_TICKS + 32,
		"the guard was down %d ticks",
		run.simulation.state.clock.time - hit_at,
	)
	scenarios.expect_synced(t, &run)
}

// The crossbow resolves on the picture its shooter saw for an elite too, through Box3D's rewound ray: an elite whose
// body crosses the shot's line, past it at the strike tick, is hit when the shooter's screen was enough ticks behind
// (sim.Seen), and missed with no delay.
@(test)
the_crossbow_hits_an_elite_where_the_shooter_saw :: proc(t: ^testing.T) {
	for seen in ([]u8{0, 5}) {
		run := alone_as(.Rogue)
		defer headless.run_end(&run)
		spawn := spawn_of(&run, 0)
		crossing := place_elite(&run, .Rogue, spawn + {5, 0, 0}, {0, 1}, .Rise)
		held := [g.PLAYERS]g.Input {
			0 = {buttons = {.Attack}, seen = sim.Seen(seen)},
		}
		for _ in 0 ..< g.CLASS_SPECS[.Rogue].windup do headless.run_step(&run, held)
		elite := elite_of(&run, crossing)
		phys := run.simulation.world.phys
		// 0.6 m past the line, crossing away from it at 8 m/s: about 0.72 m past at the strike, 0.2 m four and a half
		// ticks back, within the capsule's radius
		physics.character_teleport(phys, &elite.body, spawn + {5, g.ELITE_CENTRE_ABOVE_FEET, 0.6})
		physics.body_set_linear_velocity(phys, elite.body.body, {0, 0, 8})
		headless.run_pin(&run)
		headless.run_step(&run, held)
		struck := elite.hp < g.ELITE_SPECS[.Rogue].hp
		testing.expectf(t, struck == (seen > 0), "seen %d: struck %v", seen, struck)
		scenarios.expect_synced(t, &run)
	}
}

// Bolts and shots meet an elite's body, and walls and heavy crates shield it: a resting crate between is flown over
// (the elite is struck), a heavy crate between stops the shot (it is spared).
@(test)
an_elite_behind_a_heavy_crate_is_spared :: proc(t: ^testing.T) {
	for class in ([]g.Class{.Mage, .Rogue}) {
		for index in ([]int{CRATE, HEAVY_CRATE}) {
			run := alone_as(class)
			defer headless.run_end(&run)
			spawn := spawn_of(&run, 0)
			place_prop(&run, index, spawn + {2.5, 0, 0})
			beyond := place_elite(&run, .Mage, spawn + {5, 0, 0}, {-1, 0}, .Rise)
			hold_attack(&run, g.CLASS_SPECS[class].windup + 32, {1, 0})
			struck := elite_of(&run, beyond).hp < g.ELITE_SPECS[.Mage].hp
			testing.expectf(t, struck == (index == CRATE), "%v, prop %d: struck %v", class, index, struck)
			scenarios.expect_synced(t, &run)
		}
	}
}

// A Rogue circles round a hero standing still and lunges from behind it: when its lunge starts, it is behind the hero's
// facing, and the lunge lands.
@(test)
a_flanker_lunges_from_behind :: proc(t: ^testing.T) {
	run := alone_as(.Knight)
	defer headless.run_end(&run)
	spawn := spawn_of(&run, 0)
	rogue := place_elite(&run, .Rogue, spawn + {5, 0, 0.3}, {-1, 0}, .Chase)
	elite := elite_of(&run, rogue)
	hero := sim.slot_data(run.simulation, 0)
	lunged := false
	for _ in 0 ..< 4 * g.TICK_HZ {
		headless.run_step(&run)
		if elite.phase != .Attack do continue
		out := dmath.normalize(elite.pos.xz - hero.pos.xz)
		testing.expectf(
			t,
			dmath.dot(out, hero.facing) < -0.5,
			"it lunged from %v of the hero facing %v",
			out,
			hero.facing,
		)
		lunged = true
		break
	}
	testing.expect(t, lunged, "the Rogue never lunged")
	play(&run, {}, 0.5)
	testing.expect_value(t, hero.hp, g.HERO_HP - g.ELITE_SPECS[.Rogue].damage)
	scenarios.expect_synced(t, &run)
}

// A Mage keeps between MAGE_NEAR and MAGE_FAR of its target: one raised too close backs off into the band, and its
// bone bolts hit the hero standing there.
@(test)
a_mage_keeps_its_band_and_casts :: proc(t: ^testing.T) {
	run := alone_as(.Knight)
	defer headless.run_end(&run)
	hall := [3]f32{4, 0, 2} // the great hall's open south-west, out of sight of the floor's sleepers
	place_hero(&run, 0, hall, {1, 0})
	mage := place_elite(&run, .Mage, hall + {3, 0, 0}, {-1, 0}, .Chase)
	play(&run, {}, 3.5)
	elite := elite_of(&run, mage)
	hero := sim.slot_data(run.simulation, 0)
	apart := dmath.length(elite.pos.xz - hero.pos.xz)
	testing.expectf(t, apart >= g.MAGE_NEAR - 0.3 && apart <= g.MAGE_FAR, "it stands %v m off", apart)
	testing.expect(t, headless.run_events(&run, g.Event_Elite_Cast) >= 1, "it cast")
	testing.expectf(t, hero.hp < g.HERO_HP, "no bone bolt hit the hero: %d HP", hero.hp)
	scenarios.expect_synced(t, &run)
}

// A Mage's summoning raises SUMMON_COUNT minions round it, never past the floor's cap: one short of it, one rises.
@(test)
a_summon_stays_under_the_cap :: proc(t: ^testing.T) {
	for short_of_cap in ([]int{g.SUMMON_COUNT + 2, 1}) {
		run := alone_as(.Knight)
		defer headless.run_end(&run)
		state := &run.simulation.state
		floor := floor_of(&run)
		rng := sim.rng_seed(3)
		for g.minions_alive(&state.minions) < floor.minion_cap - short_of_cap {
			spot := g.floor_point(floor, &rng)
			if dmath.length(spot.point.xz - spawn_of(&run, 0).xz) < g.AGGRO_RADIUS + 3 do continue // asleep, unseen
			g.spawn_minion(state, spot.point, spot.poly, {0, 1}, .Idle, state.clock.time)
		}
		mage := place_elite(&run, .Mage, spawn_of(&run, 0) + {5, 0, 0}, {-1, 0}, .Chase)
		elite := elite_of(&run, mage)
		elite.next_summon = {state.clock.time, state.clock.time + 2} // its summoning is due, its bolt far off
		elite.next_bolt = {state.clock.time, state.clock.time + 1000}
		headless.run_pin(&run)
		before := g.minions_alive(&state.minions)
		play(&run, {}, g.SUMMON_CAST_S + 0.25)
		risen := g.minions_alive(&state.minions) - before
		testing.expectf(
			t,
			risen == min(g.SUMMON_COUNT, short_of_cap),
			"%d short of the cap: %d rose",
			short_of_cap,
			risen,
		)
		testing.expect(t, g.minions_alive(&state.minions) <= floor.minion_cap, "past the cap")
		scenarios.expect_synced(t, &run)
	}
}

// A minion chasing a hero walks round an elite in its way (obstacles_of: pushed out of its capsule every tick), never
// through it, and reaches the hero.
@(test)
minions_walk_round_an_elite :: proc(t: ^testing.T) {
	run := alone_as(.Knight)
	defer headless.run_end(&run)
	spawn := spawn_of(&run, 0)
	elite := elite_of(&run, place_elite(&run, .Warrior, spawn + {2.4, 0, 0.15}, {-1, 0}, .Rise))
	minion := sim.get(&run.simulation.state.minions, place_minion(&run, spawn + {4.5, 0, 0}, .Chase, {-1, 0}))
	closest := max(f32)
	for _ in 0 ..< 90 { 	// 1.4 s
		headless.run_step(&run)
		closest = dmath.min(closest, dmath.length(minion.pos.xz - elite.pos.xz))
	}
	testing.expectf(t, closest >= g.ELITE_RADIUS + g.MINION_RADIUS - 0.01, "it came %v m from the elite", closest)
	hero := sim.slot_data(run.simulation, 0)
	near := g.HERO_RADIUS + g.MINION_RADIUS + g.MINION_REACH
	testing.expectf(t, dmath.length(minion.pos.xz - hero.pos.xz) <= near, "it stands %v m from the hero", minion.pos)
	scenarios.expect_synced(t, &run)
}

// An elite killed mid-swing falls (Dying, its body gone at once, so heroes walk over it), its swing never lands, and
// its row is freed DEATH_S on; the run rolls back across the death.
@(test)
an_elite_dies_mid_swing :: proc(t: ^testing.T) {
	run := alone_as(.Knight)
	defer headless.run_end(&run)
	spawn := spawn_of(&run, 0)
	warrior := place_elite(&run, .Warrior, spawn + {1.4, 0, 0}, {-1, 0}, .Chase)
	elite := elite_of(&run, warrior)
	for elite.phase != .Attack do headless.run_step(&run)
	headless.run_command(&run, 0, g.Command_Dev_Hurt_Elites{g.ELITE_SPECS[.Warrior].hp})
	testing.expect_value(t, elite.phase, g.Elite_Phase.Dying)
	testing.expect(t, elite.body == {}, "its body went with its death")
	testing.expect_value(t, headless.run_events(&run, g.Event_Elite_Died), 1)
	play(&run, {}, 1)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).hp, g.HERO_HP)
	play(&run, {}, g.DEATH_S)
	testing.expect(t, elite_of(&run, warrior) == nil, "its row is freed")
	testing.expect_value(t, run.simulation.state.kills, 1)
	scenarios.expect_synced(t, &run)
}

// The floor's markers put its elites to sleep where they stand; a hero coming into sight wakes one, a hit wakes one.
@(test)
the_floors_elites_sleep_until_seen_or_hit :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	defs := sim.slice(&floor_of(&run).places.elites)
	testing.expect(t, len(defs) >= 2, "Floor 1 has its elites")
	testing.expect_value(t, int(run.simulation.state.elites.count), len(defs))
	play(&run, {}, 1)
	elites := sim.iterate(&run.simulation.state.elites)
	for elite in sim.next(&elites) do testing.expect_value(t, elite.phase, g.Elite_Phase.Idle)
	first, handle, _ := sim.item_at(&run.simulation.state.elites, 0)
	place_hero(&run, 0, first.pos + {-6, 0, 0.5}, {1, 0})
	play(&run, {}, 0.25)
	testing.expect_value(t, first.phase, g.Elite_Phase.Chase)
	headless.run_command(&run, 0, g.Command_Dev_Hurt_Elites{1})
	elites = sim.iterate(&run.simulation.state.elites)
	for elite, other in sim.next(&elites) {
		if other != handle do testing.expect(t, elite.phase != .Idle, "a hit woke it")
	}
	scenarios.expect_synced(t, &run)
}

// Every ELITE_SURGE_EVERY-th surge on a floor brings an elite, rising at a grave, the kinds in turn.
@(test)
the_third_surge_brings_an_elite :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	clear_elites(&run)
	state := &run.simulation.state
	state.floor_surges = g.ELITE_SURGE_EVERY - 1
	headless.run_pin(&run)
	for headless.run_events(&run, g.Event_Surge) == 0 do headless.run_step(&run)
	testing.expect_value(t, int(state.elites.count), 1)
	elite, _, _ := sim.item_at(&state.elites, 0)
	testing.expect_value(t, elite.kind, g.Elite_Kind.Warrior)
	testing.expect_value(t, elite.phase, g.Elite_Phase.Rise)
	near_grave := false
	for &grave in sim.slice(&floor_of(&run).places.graves) {
		near_grave ||= dmath.length(grave.point.xz - elite.pos.xz) <= g.ELITE_RISE_RING + 0.5
	}
	testing.expect(t, near_grave, "it rose at a grave")
	scenarios.expect_synced(t, &run)
}

// A surge or a dev spawn raises no elite past ELITES_ALIVE_MAX alive.
@(test)
the_elites_alive_are_capped :: proc(t: ^testing.T) {
	run := alone_as(.Knight)
	defer headless.run_end(&run)
	for kind in 0 ..< g.ELITES_ALIVE_MAX + 2 {
		headless.run_command(&run, 0, g.Command_Dev_Spawn_Elite{g.Elite_Kind(kind % len(g.Elite_Kind))})
		place_hero(&run, 0, spawn_of(&run, 0) + {0, 0, f32(kind % 3) - 1}, {1, 0}) // the next one's place is free
	}
	testing.expect_value(t, g.elites_alive(&run.simulation.state.elites), g.ELITES_ALIVE_MAX)
	scenarios.expect_synced(t, &run)
}

// A floor's restart with elites alive (one rising, one swinging, one dying) and a leave of the hero they chase keep the
// physics world's refs clean (check_refs after every restore): every elite body goes with the restart, and the floor's
// sleepers come back.
@(test)
a_restart_and_a_leave_with_elites_alive :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	clear_minions(&run)
	spawn := spawn_of(&run, 0)
	place_elite(&run, .Warrior, spawn + {1.4, 0, 0}, {-1, 0}, .Chase)
	place_elite(&run, .Rogue, spawn + {4, 0, 2}, {-1, 0}, .Rise)
	dying := place_elite(&run, .Mage, spawn + {4, 0, -2}, {-1, 0}, .Chase)
	play(&run, {}, 1)
	elite_of(&run, dying).hp = 1
	headless.run_pin(&run)
	headless.run_command(&run, 0, g.Command_Dev_Hurt_Elites{1})
	headless.run_seat(&run, 1, 0) // slot 1 leaves
	play(&run, {}, 0.25)
	headless.run_command(&run, 0, g.Command_Dev_Hurt{damage = g.HERO_HP})
	for _ in 0 ..< 10 * g.TICK_HZ {
		if headless.run_events(&run, g.Event_Floor_Restarted) > 0 do break
		headless.run_step(&run)
	}
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 1)
	state := &run.simulation.state
	testing.expect_value(t, int(state.elites.count), int(floor_of(&run).places.elites.count))
	elites := sim.iterate(&state.elites)
	for elite in sim.next(&elites) do testing.expect_value(t, elite.phase, g.Elite_Phase.Idle)
	play(&run, {}, 0.5)
	scenarios.expect_synced(t, &run)
}
