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

// `handle`'s elite swings at nothing (an attack with no target, which lands on nobody): its facing locked for its
// spec's duration, awake, a Warrior's shield up. The run is pinned.
brace :: proc(run: ^headless.Run(g.Game), handle: sim.Handle(g.Elite)) {
	elite := elite_of(run, handle)
	elite.phase, elite.since, elite.target = .Attack, run.simulation.state.clock.time, {}
	headless.run_pin(run)
}

// A Knight's blow at a Warrior `offset` from it (on the floor plan), the Knight facing `knight_facing` and the
// Warrior `warrior_facing`, the Warrior swinging at nothing (brace: its facing locked) or asleep, with its guard
// broken first when `broken`: the Warrior after it. It is placed the tick before the blow lands.
@(private = "file")
knight_blow_at_warrior :: proc(
	t: ^testing.T,
	offset: [2]f32,
	knight_facing, warrior_facing: [2]f32,
	broken := false,
	asleep := false,
) -> (
	hp: i16,
	phase: g.Elite_Phase,
) {
	run := alone_as(.Knight, knight_facing)
	defer headless.run_end(&run)
	spawn := spawn_of(&run, 0)
	windup := g.CLASS_SPECS[.Knight].windup // the attack's first tick is its age 0: it lands on the windup + 1-th
	hold_attack(&run, windup - 1 if broken else windup, knight_facing)
	warrior := place_elite(&run, .Warrior, spawn + {offset.x, 0, offset.y}, warrior_facing, .Idle)
	if !asleep do brace(&run, warrior)
	if broken {
		headless.run_command(&run, 0, g.Command_Dev_Break_Guards{}) // a tick of its own (Attack let go: no new press)
		testing.expect_value(t, headless.run_events(&run, g.Event_Guard_Broken), 1)
	}
	hold_attack(&run, 1, knight_facing)
	testing.expect_value(t, headless.run_events(&run, g.Event_Elite_Hit), 1)
	scenarios.expect_synced(t, &run)
	return elite_of(&run, warrior).hp, elite_of(&run, warrior).phase
}

// A Warrior's shield takes all but ELITE_GUARD_TAKE of a blow from its front (within ELITE_GUARD_COS), and none of one
// from behind or from its side. It judges where the blow comes from, never where the hero faces: a Knight in front of
// it facing away, its back to the shield, strikes what touches it (STRIKE_TOUCH) and is guarded all the same. A
// sleeper doesn't guard: the blow that wakes it lands whole.
@(test)
a_warriors_shield_guards_its_front :: proc(t: ^testing.T) {
	sword := g.CLASS_SPECS[.Knight].damage
	full := g.ELITE_SPECS[.Warrior].hp
	front, _ := knight_blow_at_warrior(t, {1.4, 0}, {1, 0}, {-1, 0})
	testing.expectf(t, front == full - g.guard_take(sword), "from the front: %d HP", front)
	testing.expect(t, g.guard_take(sword) < sword / 3, "a guarded blow takes a quarter")
	behind, _ := knight_blow_at_warrior(t, {1.4, 0}, {1, 0}, {1, 0})
	testing.expectf(t, behind == full - sword, "from behind: %d HP", behind)
	side, _ := knight_blow_at_warrior(t, {1.4, 0}, {1, 0}, {0, 1})
	testing.expectf(t, side == full - sword, "from its side: %d HP", side)
	touching, _ := knight_blow_at_warrior(t, {0.95, 0}, {-1, 0}, {-1, 0})
	testing.expectf(t, touching == full - g.guard_take(sword), "touching, the Knight facing away: %d HP", touching)
	asleep, woke := knight_blow_at_warrior(t, {1.4, 0}, {1, 0}, {-1, 0}, asleep = true)
	testing.expectf(t, asleep == full - sword && woke == .Chase, "asleep: %d HP, then %v", asleep, woke)
}

// A broken guard (dev_break_guards: break_guard, the entry a charge and a fireball will call) lets a blow from the
// front through whole, for GUARD_BREAK_S.
@(test)
a_broken_guard_lets_the_front_through :: proc(t: ^testing.T) {
	sword := g.CLASS_SPECS[.Knight].damage
	broken, _ := knight_blow_at_warrior(t, {1.4, 0}, {1, 0}, {-1, 0}, broken = true)
	testing.expectf(t, broken == g.ELITE_SPECS[.Warrior].hp - sword, "the guard broken: %d HP", broken)
}

// A run with slot 0's Barbarian at its spawn facing +X and slot 1's Knight 3.2 m beyond it facing back, no
// minion and no elite.
@(private = "file")
cleaver_and_knight :: proc() -> headless.Run(g.Game) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Barbarian})
	headless.run_command(&run, 1, g.Command_Dev_Set_Class{.Knight})
	clear_minions(&run)
	clear_elites(&run)
	place_hero(&run, 0, spawn_of(&run, 0), {1, 0})
	place_hero(&run, 1, spawn_of(&run, 0) + {3.2, 0, 0}, {-1, 0})
	return run
}

// Slot 0 (the Barbarian) holds Attack aimed +X for `ticks`, slot 1 (the Knight) joining in, aimed -X, from
// `knight_from` (-1: never).
@(private = "file")
cleave :: proc(run: ^headless.Run(g.Game), ticks: int, knight_from := -1) {
	for k in 0 ..< ticks {
		inputs: [g.PLAYERS]g.Input
		inputs[0] = {
			buttons = {.Attack},
			aim     = dmath.dir2({1, 0}),
		}
		if knight_from >= 0 && k >= knight_from do inputs[1] = {
			buttons = {.Attack},
			aim     = dmath.dir2({-1, 0}),
		}
		headless.run_step(run, inputs)
	}
}

// A cleave from a Warrior's front is guarded: a quarter of it, no knock, no stagger, its swing goes on. From behind it
// lands whole: the Warrior is knocked away (ELITE_KNOCK_TAKE of the cleave's knock), staggered, its swing cut off, and
// its shield is down while it reels: a Knight's blow from its front three ticks later lands whole too.
@(test)
a_stagger_lowers_the_shield :: proc(t: ^testing.T) {
	cleaver := g.CLASS_SPECS[.Barbarian]
	windup := int(cleaver.windup)
	for from_front in ([]bool{true, false}) {
		run := cleaver_and_knight()
		defer headless.run_end(&run)
		facing := [2]f32{-1, 0} if from_front else {1, 0} // toward the Barbarian, or toward the Knight
		warrior := place_elite(&run, .Warrior, spawn_of(&run, 0) + {1.6, 0, 0}, facing, .Idle)
		brace(&run, warrior)
		elite := elite_of(&run, warrior)
		cleave(&run, windup + 1, -1 if from_front else windup + 3 - int(g.CLASS_SPECS[.Knight].windup))
		speed := dmath.length(physics.body_linear_velocity(run.simulation.world.phys, elite.body.body).xz)
		now := run.simulation.state.clock.time
		full := g.ELITE_SPECS[.Warrior].hp
		if from_front {
			testing.expect_value(t, elite.hp, full - g.guard_take(cleaver.damage))
			testing.expectf(t, speed < 0.2, "a guarded cleave knocked it to %v m/s", speed)
			testing.expect(t, !sim.timer_running(now, elite.stagger), "a guarded cleave staggered it")
			testing.expect_value(t, elite.phase, g.Elite_Phase.Attack)
		} else {
			testing.expect_value(t, elite.hp, full - cleaver.damage)
			testing.expectf(t, speed > 2, "the cleave knocked it to %v m/s only", speed)
			testing.expect(t, sim.timer_running(now, elite.stagger), "the cleave didn't stagger it")
			testing.expect_value(t, elite.phase, g.Elite_Phase.Chase)
			cleave(&run, 3, 0)
			sword := g.CLASS_SPECS[.Knight].damage
			testing.expectf(
				t,
				elite.hp == full - cleaver.damage - sword,
				"the Knight's blow while it reels: %d HP",
				elite.hp,
			)
		}
		scenarios.expect_synced(t, &run)
	}
}

// A stagger cuts a Mage's summoning off: no minion rises, and it tries again SUMMON_RETRY_S on, not at once.
@(test)
a_stagger_cuts_a_summoning_off :: proc(t: ^testing.T) {
	run := cleaver_and_knight()
	defer headless.run_end(&run)
	mage := place_elite(&run, .Mage, spawn_of(&run, 0) + {1.6, 0, 0.4}, {-1, 0}, .Chase)
	cleave(&run, int(g.CLASS_SPECS[.Barbarian].windup) - 4)
	elite := elite_of(&run, mage)
	elite.phase, elite.since, elite.target =
		.Summon, run.simulation.state.clock.time, sim.player_in_slot(run.simulation, 0)
	headless.run_pin(&run)
	cleave(&run, 5)
	now := run.simulation.state.clock.time
	testing.expect_value(t, elite.phase, g.Elite_Phase.Chase)
	retry := u32(elite.next_summon.target - now)
	testing.expectf(
		t,
		retry + 8 >= g.SUMMON_RETRY_TICKS && retry <= g.SUMMON_RETRY_TICKS,
		"it tries again in %d ticks",
		retry,
	)
	play(&run, {}, g.SUMMON_CAST_S + 0.5)
	testing.expect_value(t, g.minions_alive(&run.simulation.state.minions), 0)
	scenarios.expect_synced(t, &run)
}

// An elite turns at most ELITE_TURN_COS a tick, and a Warrior swings only at a hero in front of it: one in reach behind
// it is swung at only once the Warrior has turned to it.
@(test)
a_warrior_turns_before_it_swings :: proc(t: ^testing.T) {
	run := alone_as(.Knight)
	defer headless.run_end(&run)
	warrior := place_elite(&run, .Warrior, spawn_of(&run, 0) + {1.4, 0, 0}, {1, 0}, .Chase)
	elite := elite_of(&run, warrior)
	hero := sim.slot_data(run.simulation, 0)
	last := elite.facing
	for _ in 0 ..< 2 * g.TICK_HZ {
		headless.run_step(&run)
		turn := dmath.dot(elite.facing, last)
		testing.expectf(t, turn >= g.ELITE_TURN_COS - 1e-4, "it turned %v (cos) in a tick", turn)
		last = elite.facing
		if elite.phase != .Attack do continue
		to_hero := dmath.normalize(hero.pos.xz - elite.pos.xz)
		testing.expectf(t, dmath.dot(to_hero, elite.facing) >= g.ELITE_STRIKE_COS, "it swung facing %v", elite.facing)
		break
	}
	testing.expect_value(t, elite.phase, g.Elite_Phase.Attack)
	scenarios.expect_synced(t, &run)
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

// A Rogue circles round a hero standing still and lunges from behind it, whether it starts near or walks in from
// another room (circling alone spends its patience: FLANK_GIVE_UP_S): when its lunge starts it is behind the hero's
// facing; the lunge drives it faster than it walks (LUNGE_SPEED), lands, and it backs off (Retreat).
@(test)
a_flanker_lunges_from_behind :: proc(t: ^testing.T) {
	for start in ([][3]f32{{5, 0, 0.3}, {0, 0, 0}}) {
		run := alone_as(.Knight)
		defer headless.run_end(&run)
		spawn := spawn_of(&run, 0)
		from := spawn + start if start != {} else [3]f32{8, 0, -16} // near, or the north room: 30 m of path
		rogue := place_elite(&run, .Rogue, from, {-1, 0}, .Chase)
		elite := elite_of(&run, rogue)
		hero := sim.slot_data(run.simulation, 0)
		lunged := false
		for _ in 0 ..< 12 * g.TICK_HZ {
			headless.run_step(&run)
			if elite.phase != .Attack do continue
			out := dmath.normalize(elite.pos.xz - hero.pos.xz)
			testing.expectf(t, dmath.dot(out, hero.facing) < -0.5, "from %v it lunged from %v of the hero", from, out)
			lunged = true
			break
		}
		testing.expectf(t, lunged, "from %v the Rogue never lunged", from)
		fastest: f32 // its speed before it meets the hero's capsule
		for elite.phase == .Attack {
			headless.run_step(&run)
			apart := dmath.length(elite.pos.xz - hero.pos.xz)
			if apart > g.HERO_RADIUS + g.ELITE_RADIUS + 0.2 do fastest = dmath.max(fastest, dmath.length(elite.vel.xz))
		}
		testing.expectf(t, fastest >= g.LUNGE_SPEED, "it lunged at %v m/s", fastest)
		testing.expect_value(t, elite.phase, g.Elite_Phase.Retreat)
		testing.expect_value(t, hero.hp, g.HERO_HP - g.ELITE_SPECS[.Rogue].damage)
		scenarios.expect_synced(t, &run)
	}
}

// A Rogue doesn't lunge through a wall: at its spot behind a hero whose back is to the great hall's north wall, on the
// north room's side of it, it walks round instead.
@(test)
a_flanker_never_lunges_through_a_wall :: proc(t: ^testing.T) {
	run := alone_as(.Knight)
	defer headless.run_end(&run)
	place_hero(&run, 0, {10, 0, -11}, {0, 1}) // the wall from x 8 to 12 (its doorway is west of it)
	hero := sim.slot_data(run.simulation, 0)
	rogue := place_elite(&run, .Rogue, hero.pos - {0, 0, g.FLANK_BEHIND}, {0, 1}, .Chase)
	elite := elite_of(&run, rogue)
	eye := elite.pos + {0, g.EYE_HEIGHT, 0}
	seen := hero.pos + {0, g.EYE_HEIGHT, 0}
	_, walled := physics.world_cast_ray_closest(run.simulation.world.phys, eye, seen - eye, g.SIGHT_FILTER)
	testing.expectf(t, walled && dmath.length(g.flank_spot(hero) - elite.pos.xz) <= g.FLANK_ARRIVE, "at %v", elite.pos)
	for _ in 0 ..< 16 {
		headless.run_step(&run)
		testing.expect(t, elite.phase != .Attack, "it lunged through the wall")
	}
	scenarios.expect_synced(t, &run)
}

// A Mage keeps between MAGE_NEAR and MAGE_FAR of its target: one raised too close backs off into the band, its first
// cast a bone bolt BONE_BOLT_FIRST_S after it took to the chase (no summoning: that is SUMMON_EVERY_S off), and its
// bolts hit the hero standing there for exactly their damage.
@(test)
a_mage_keeps_its_band_and_casts :: proc(t: ^testing.T) {
	run := alone_as(.Knight)
	defer headless.run_end(&run)
	hall := [3]f32{4, 0, 2} // the great hall's open south-west, out of sight of the floor's sleepers
	place_hero(&run, 0, hall, {1, 0})
	mage := place_elite(&run, .Mage, hall + {3, 0, 0}, {-1, 0}, .Chase)
	chased := run.simulation.state.clock.time
	first_cast: sim.Game_Time
	for _ in 0 ..< 224 { 	// 3.5 s
		headless.run_step(&run)
		if spelled, found := headless.run_last_event(&run, g.Event_Elite_Cast); found && first_cast == 0 {
			first_cast = run.simulation.state.clock.time
			testing.expect_value(t, spelled.spell, g.Elite_Spell.Bone_Bolt)
		}
	}
	testing.expectf(t, first_cast >= chased + sim.Game_Time(g.BONE_BOLT_FIRST_TICKS), "it cast at %d", first_cast)
	elite := elite_of(&run, mage)
	hero := sim.slot_data(run.simulation, 0)
	apart := dmath.length(elite.pos.xz - hero.pos.xz)
	testing.expectf(t, apart >= g.MAGE_NEAR - 0.3 && apart <= g.MAGE_FAR, "it stands %v m off", apart)
	testing.expect_value(t, g.minions_alive(&run.simulation.state.minions), 0)
	hits := headless.run_events(&run, g.Event_Hero_Hurt)
	testing.expectf(t, hits >= 1, "no bone bolt hit the hero")
	testing.expect_value(t, int(hero.hp), int(g.HERO_HP) - hits * int(g.ELITE_SPECS[.Mage].damage))
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
	headless.run_command(&run, 0, g.Command_Dev_Hurt_Elites{1}) // the fallen take nothing
	testing.expect_value(t, headless.run_events(&run, g.Event_Elite_Hit), 1)
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

// Every ELITE_SURGE_EVERY-th surge on a floor brings an elite, rising at a grave, the kinds in turn: the third surge a
// Warrior, the sixth a Rogue, the ninth a Mage.
@(test)
the_third_surge_brings_an_elite :: proc(t: ^testing.T) {
	for kind in g.Elite_Kind {
		run := headless.run_begin(&g.GAME, 1, seated = 1)
		defer headless.run_end(&run)
		clear_minions(&run)
		clear_elites(&run)
		state := &run.simulation.state
		state.floor_surges = u32(g.ELITE_SURGE_EVERY * (int(kind) + 1) - 1)
		headless.run_pin(&run)
		for headless.run_events(&run, g.Event_Surge) == 0 do headless.run_step(&run)
		testing.expect_value(t, int(state.elites.count), 1)
		elite, _, _ := sim.item_at(&state.elites, 0)
		testing.expect_value(t, elite.kind, kind)
		testing.expect_value(t, elite.phase, g.Elite_Phase.Rise)
		near_grave := false
		for &grave in sim.slice(&floor_of(&run).places.graves) {
			near_grave ||= dmath.length(grave.point.xz - elite.pos.xz) <= g.ELITE_RISE_RING + 0.5
		}
		testing.expect(t, near_grave, "it rose at a grave")
		scenarios.expect_synced(t, &run)
	}
}

// A surge or a dev spawn raises no elite past ELITES_ALIVE_MAX alive, and each rises clear of every other and of the
// heroes (elite_room), on the ring round its place when the place is taken.
@(test)
the_elites_alive_are_capped :: proc(t: ^testing.T) {
	run := alone_as(.Knight)
	defer headless.run_end(&run)
	state := &run.simulation.state
	hero := sim.slot_data(run.simulation, 0)
	for kind in 0 ..< g.ELITES_ALIVE_MAX + 2 {
		headless.run_command(&run, 0, g.Command_Dev_Spawn_Elite{g.Elite_Kind(kind % len(g.Elite_Kind))})
		for i in 0 ..< int(state.elites.high_water) {
			a, _, a_live := sim.item_at(&state.elites, i)
			if !a_live do continue
			apart := dmath.length(a.pos.xz - hero.pos.xz)
			testing.expectf(
				t,
				apart >= g.ELITE_RADIUS + g.HERO_RADIUS - 0.05,
				"an elite rose %v m from the hero",
				apart,
			)
			for k in i + 1 ..< int(state.elites.high_water) {
				b, _, b_live := sim.item_at(&state.elites, k)
				if !b_live do continue
				apart = dmath.length(a.pos.xz - b.pos.xz)
				testing.expectf(t, apart >= 2 * g.ELITE_RADIUS - 0.05, "two elites rose %v m apart", apart)
			}
		}
	}
	testing.expect_value(t, g.elites_alive(&state.elites), g.ELITES_ALIVE_MAX)
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

// A run whose population is held (State.held: a benchmark's, a crowd's) gets no elite: the floor's markers place none
// under a held crowd, a dev spawn raises none, and a Mage's summoning raises no minion past the held count.
@(test)
a_held_population_gets_no_elite :: proc(t: ^testing.T) {
	run := headless.run_begin_with_setup(&g.GAME, 1, g.Setup{crowd = .Chase}, seated = 1)
	defer headless.run_end(&run)
	state := &run.simulation.state
	testing.expect_value(t, int(state.elites.count), 0)
	headless.run_command(&run, 0, g.Command_Dev_Spawn_Elite{.Warrior})
	testing.expect_value(t, int(state.elites.count), 0)
	clear_minions(&run)
	state.held = 3
	headless.run_pin(&run)
	mage := place_elite(&run, .Mage, spawn_of(&run, 0) + {5, 0, 0}, {-1, 0}, .Chase)
	elite := elite_of(&run, mage)
	elite.next_summon = {state.clock.time, state.clock.time + 2}
	elite.next_bolt = {state.clock.time, state.clock.time + 1000}
	headless.run_pin(&run)
	for _ in 0 ..< g.SUMMON_CAST_TICKS + 32 {
		headless.run_step(&run)
		testing.expectf(t, g.minions_alive(&state.minions) <= 3, "%d alive", g.minions_alive(&state.minions))
	}
	scenarios.expect_synced(t, &run)
}

// A bolt that strikes an elite hurts it once, the Mage's damage, and its burst hurts the other elite beside it
// (knock_elites, skipping the one struck).
@(test)
a_bolts_burst_spares_the_struck_elite :: proc(t: ^testing.T) {
	run := alone_as(.Mage)
	defer headless.run_end(&run)
	spawn := spawn_of(&run, 0)
	struck := place_elite(&run, .Rogue, spawn + {4, 0, 0}, {-1, 0}, .Rise)
	beside := place_elite(&run, .Rogue, spawn + {4, 0, 1.2}, {-1, 0}, .Rise)
	hold_attack(&run, g.CLASS_SPECS[.Mage].windup + 24, {1, 0})
	full := g.ELITE_SPECS[.Rogue].hp
	testing.expect_value(t, elite_of(&run, struck).hp, full - g.CLASS_SPECS[.Mage].damage)
	testing.expect_value(t, elite_of(&run, beside).hp, full - g.BURST_DAMAGE)
	scenarios.expect_synced(t, &run)
}

// The barrel flung along +X at an elite from `at`, as slot 0's throw when `thrown` (its throw running), the run pinned.
@(private = "file")
fling_at_elite :: proc(run: ^headless.Run(g.Game), at: [3]f32, thrown: bool) {
	place_prop(run, BARREL, at)
	barrel, _ := prop_at(run, BARREL)
	now := run.simulation.state.clock.time
	barrel.thrown_by = sim.player_in_slot(run.simulation, 0)
	if thrown && !sim.timer_running(now, barrel.thrown) do barrel.thrown = {now, now + sim.Game_Time(g.THROWN_TICKS)}
	physics.body_set_linear_velocity(run.simulation.world.phys, barrel.body, {g.THROW_SPEED, 0, 0})
	headless.run_pin(run)
}

// A prop hurts an elite only while its throw runs, and once per throw: flung again at it in the same throw, it hurts
// it no more; a prop flung as fast with no throw running hurts nobody.
@(test)
a_throw_hurts_an_elite_once :: proc(t: ^testing.T) {
	for thrown in ([]bool{false, true}) {
		run := alone_as(.Knight)
		defer headless.run_end(&run)
		spawn := spawn_of(&run, 0)
		warrior := place_elite(&run, .Warrior, spawn + {3.5, 0, 0}, {-1, 0}, .Rise)
		fling_at_elite(&run, spawn + {1.4, 0, 0}, thrown)
		play(&run, {}, 0.4)
		full := g.ELITE_SPECS[.Warrior].hp
		testing.expect_value(t, elite_of(&run, warrior).hp, full - g.PROP_HIT_DAMAGE if thrown else full)
		fling_at_elite(&run, spawn + {1.4, 0, 0}, thrown) // the same throw, at it again
		play(&run, {}, 0.4)
		testing.expect_value(t, elite_of(&run, warrior).hp, full - g.PROP_HIT_DAMAGE if thrown else full)
		scenarios.expect_synced(t, &run)
	}
}

// A hero walking into a standing elite barely moves it (ELITE_DENSITY, ELITE_GROUND_FORCE): an elite isn't shoved
// about, asleep or awake.
@(test)
a_hero_cannot_shove_an_elite :: proc(t: ^testing.T) {
	run := alone_as(.Knight)
	defer headless.run_end(&run)
	warrior := place_elite(&run, .Warrior, spawn_of(&run, 0) + {1.2, 0, 0}, {1, 0}, .Idle)
	from := elite_of(&run, warrior).pos
	push := [g.PLAYERS]g.Input {
		0 = {move_x = 127},
	}
	play(&run, push, 2)
	moved := dmath.length(elite_of(&run, warrior).pos.xz - from.xz)
	testing.expectf(t, moved < 0.3, "the hero shoved it %v m", moved)
	scenarios.expect_synced(t, &run)
}

// A joiner arrives clear of elites: the first spot of its ring (ARRIVAL_SLOT_TURN) holds one, so it arrives at another,
// ARRIVAL_CLEAR from it.
@(test)
a_joiner_arrives_clear_of_elites :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	clear_elites(&run)
	anchor := spawn_of(&run, 0) + {2, 0, 0}
	place_hero(&run, 0, anchor, {1, 0})
	first := dmath.DIR8[g.ARRIVAL_SLOT_TURN % len(dmath.DIR8)] // slot 1's first spot
	elite := elite_of(
		&run,
		place_elite(&run, .Warrior, anchor + {first.x, 0, first.y} * g.ARRIVAL_RING, {1, 0}, .Rise),
	)
	headless.run_seat(&run, 1, 2)
	headless.run_step(&run)
	joiner := sim.slot_data(run.simulation, 1)
	apart := dmath.length(joiner.pos.xz - elite.pos.xz)
	testing.expectf(t, apart >= g.ARRIVAL_CLEAR, "it arrived %v m from the elite", apart)
	scenarios.expect_synced(t, &run)
}

// A Mage casts nothing at a target it can't see: behind the wall between the north room and the great hall, its
// summoning due, it walks round instead.
@(test)
a_mage_casts_only_in_sight :: proc(t: ^testing.T) {
	run := alone_as(.Knight)
	defer headless.run_end(&run)
	place_hero(&run, 0, {10, 0, -10}, {0, -1}) // the wall from x 8 to 12, its doorway west of it
	mage := place_elite(&run, .Mage, {10, 0, -14}, {0, 1}, .Chase)
	elite := elite_of(&run, mage)
	now := run.simulation.state.clock.time
	elite.next_summon, elite.next_bolt = {now, now + 2}, {now, now + 2}
	headless.run_pin(&run)
	play(&run, {}, 0.5)
	testing.expect_value(t, headless.run_events(&run, g.Event_Elite_Cast), 0)
	testing.expect_value(t, elite.phase, g.Elite_Phase.Chase)
	scenarios.expect_synced(t, &run)
}
