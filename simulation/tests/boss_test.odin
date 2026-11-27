// The boss's rule tests (boss.odin, elite_king.odin), on the vault: the King's health set for the party as it wakes,
// its guard broken and back, its stages (every brazier doused, the ward up), the ward breaking at the need for the
// heroes present (a joiner raising it), the slam on its own clock hurting and throwing inside its ring only and blowing
// a crate and a ragdoll away, the King never heaved, its death winning, a wipe starting the vault over, and the King
// walking round a pillar (its capsule wider than the navigation's agent). Each on a
// sync-tested run (headless.Run) that ends synced, so every stage, ward and slam here also rolls back (check_refs
// after every restore); the slam's own run re-simulates the deepest window.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// The vault's props by marker order (game/levels/vault.tscn): its first heavy crate.
VAULT_HEAVY_CRATE :: 0

// A sync-tested run on the vault with `seated` heroes, its surges held off (hold_surges); `window` is how far back each
// step is re-simulated.
@(private = "file")
vault :: proc(seated := 1, window: u32 = 8) -> headless.Run(g.Game) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Vault}, window, seated)
	hold_surges(&run)
	return run
}

// The King (nil once its row is gone).
@(private = "file")
king_of :: proc(run: ^headless.Run(g.Game)) -> ^g.Elite {
	return sim.get(&run.simulation.state.elites, run.simulation.state.boss.elite)
}

// One tick in which slot 0 hurts the King for `damage`, from no side (Command_Dev_Hurt_Elites: no shield takes it).
@(private = "file")
hurt_king :: proc(run: ^headless.Run(g.Game), damage: i16) {
	headless.run_command(run, 0, g.Command_Dev_Hurt_Elites{damage})
}

// The skeletons a stage raised go, and the surges are held off again (the run pinned there): a test of the King alone.
@(private = "file")
quiet :: proc(run: ^headless.Run(g.Game)) {
	run.simulation.state.rising = 0
	hold_surges(run)
}

// The King's health down to each stage's end until it is in `stage` (warded), the wards on the way broken by lighting
// every brazier, the run quieted after it.
@(private = "file")
to_stage :: proc(run: ^headless.Run(g.Game), stage: int) {
	boss := &run.simulation.state.boss
	for _ in 0 ..< 3 { 	// a stage a blow, at most: a King that won't move on fails its test, never hangs it
		if int(boss.stage) >= stage do break
		hurt_king(run, boss.hp_max)
		if boss.warded && int(boss.stage) < stage do headless.run_command(run, 0, g.Command_Dev_Light_Braziers{})
	}
	quiet(run)
}

// The first `count` braziers lit (and the rest not), set as the state's: a test of the ward's count, not of a kindling.
@(private = "file")
light_braziers :: proc(run: ^headless.Run(g.Game), count: int) {
	walk := sim.iterate(&run.simulation.state.braziers)
	for brazier, handle in sim.next(&walk) do brazier.lit = int(handle.index) < count
	headless.run_pin(run)
}

// The King sleeps at its marker until it is hit (or sees a hero), and wakes with BOSS_HP and BOSS_HP_PER_HERO for each
// other hero present then, the waking blow taken from that: 1200 alone, 2000 with three.
@(test)
the_kings_health_is_the_partys :: proc(t: ^testing.T) {
	for seated in ([2]int{1, 3}) {
		run := vault(seated)
		defer headless.run_end(&run)
		king := king_of(&run)
		boss := &run.simulation.state.boss
		testing.expect_value(t, king.phase, g.Elite_Phase.Idle)
		testing.expect_value(t, boss.hp_max, 0)
		hurt_king(&run, 10)
		full := g.BOSS_HP + g.BOSS_HP_PER_HERO * i16(seated - 1)
		testing.expect_value(t, boss.hp_max, full)
		testing.expect_value(t, king.hp, full - 10)
		testing.expect_value(t, boss.stage, 1)
		scenarios.expect_synced(t, &run)
	}
}

// The King's guard is the Warrior's: a blow from its front takes ELITE_GUARD_TAKE; broken (a thrown prop, a charge, a
// fireball: dev_break_guards here), it is down for BOSS_GUARD_DOWN_S, and back up after.
@(test)
the_kings_guard_breaks_and_returns :: proc(t: ^testing.T) {
	run := vault()
	defer headless.run_end(&run)
	king := king_of(&run)
	hurt_king(&run, 1) // awake
	quiet(&run)
	testing.expect(t, g.shield_up(run.simulation.state.clock.time, king), "awake, it guards")
	headless.run_command(&run, 0, g.Command_Dev_Break_Guards{})
	testing.expect_value(t, headless.run_events(&run, g.Event_Guard_Broken), 1)
	play(&run, {}, g.BOSS_GUARD_DOWN_S - 0.25)
	testing.expect(t, !g.shield_up(run.simulation.state.clock.time, king), "down until its time")
	play(&run, {}, 0.5)
	testing.expect(t, g.shield_up(run.simulation.state.clock.time, king), "up again after BOSS_GUARD_DOWN_S")
	scenarios.expect_synced(t, &run)
}

// At two thirds of its health the King's next stage begins: it roars, every lit brazier goes out, its ward goes up and
// no blow hurts it, BOSS_SUMMON skeletons are owed to the graves and the surges come every BOSS_SURGE_S. A blow can't
// take it past the stage's end. The ward breaks at its need (two braziers alone), and the third stage douses them
// again.
@(test)
the_ward_holds_until_its_braziers_are_lit :: proc(t: ^testing.T) {
	run := vault()
	defer headless.run_end(&run)
	state := &run.simulation.state
	boss := &state.boss
	king := king_of(&run)
	hurt_king(&run, 1)
	light_braziers(&run, 4) // lit in its first stage: the stage puts them out
	hurt_king(&run, boss.hp_max) // a blow of all its health stops at the stage's end
	testing.expect_value(t, king.hp, i16(i32(boss.hp_max) * 2 / 3))
	testing.expect_value(t, boss.stage, 2)
	testing.expect(t, boss.warded, "warded")
	testing.expect_value(t, headless.run_events(&run, g.Event_Boss_Stage), 1)
	testing.expect_value(t, headless.run_events(&run, g.Event_Brazier), 4) // each one's going out
	walk := sim.iterate(&state.braziers)
	for brazier in sim.next(&walk) do testing.expect(t, !brazier.lit, "the stage put every brazier out")
	testing.expect_value(t, state.rising, g.BOSS_SUMMON)
	testing.expect_value(t, state.surge.target - state.surge.start, sim.Game_Time(g.BOSS_SURGE_TICKS))
	quiet(&run)
	hp := king.hp
	hurt_king(&run, 100)
	testing.expect_value(t, king.hp, hp)
	light_braziers(&run, int(g.BOSS_WARD_NEED[0]) - 1)
	play(&run, {}, 0.5)
	hurt_king(&run, 100)
	testing.expect(t, boss.warded && king.hp == hp, "a brazier short of its need, the ward holds")
	light_braziers(&run, int(g.BOSS_WARD_NEED[0]))
	headless.run_step(&run)
	testing.expect(t, !boss.warded, "its need lit, the ward breaks")
	testing.expect_value(t, headless.run_events(&run, g.Event_Boss_Ward), 2)
	hurt_king(&run, 100)
	testing.expect_value(t, king.hp, hp - 100)
	hurt_king(&run, boss.hp_max)
	testing.expect_value(t, boss.stage, 3)
	testing.expect(t, boss.warded, "warded again")
	walk = sim.iterate(&state.braziers)
	for brazier in sim.next(&walk) do testing.expect(t, !brazier.lit, "the third stage put the braziers out again")
	scenarios.expect_synced(t, &run)
}

// The ward's need is the heroes present now (BOSS_WARD_NEED: 2, 3, 4, 4): a ward a brazier short holds and one at its
// need breaks, for each party size; and a joiner mid-ward raises the need it must meet.
@(test)
the_wards_need_is_the_partys :: proc(t: ^testing.T) {
	for seated in 1 ..= g.PLAYERS {
		run := vault(seated)
		defer headless.run_end(&run)
		boss := &run.simulation.state.boss
		hurt_king(&run, 1)
		to_stage(&run, 2)
		need := int(g.BOSS_WARD_NEED[seated - 1])
		decided := [g.PLAYERS]int{2, 3, 4, 4} // the design's, by party size
		testing.expect_value(t, need, decided[seated - 1])
		light_braziers(&run, need - 1)
		headless.run_step(&run)
		testing.expectf(t, boss.warded, "%d heroes: %d lit hold it", seated, need - 1)
		light_braziers(&run, need)
		headless.run_step(&run)
		testing.expectf(t, !boss.warded, "%d heroes: %d lit break it", seated, need)
		scenarios.expect_synced(t, &run)
	}
	run := vault(1)
	defer headless.run_end(&run)
	boss := &run.simulation.state.boss
	hurt_king(&run, 1)
	to_stage(&run, 2)
	light_braziers(&run, 1)
	headless.run_seat(&run, 1, 2) // a joiner arrives mid-ward: the need is two heroes' now
	headless.run_step(&run)
	light_braziers(&run, int(g.BOSS_WARD_NEED[0]))
	headless.run_step(&run)
	testing.expect(t, boss.warded, "the lone hero's need no longer breaks it")
	light_braziers(&run, int(g.BOSS_WARD_NEED[1]))
	headless.run_step(&run)
	testing.expect(t, !boss.warded, "the pair's need does")
	scenarios.expect_synced(t, &run)
}

// From its second stage on the King slams on its own clock (Boss.next_slam): started BOSS_SLAM_EVERY_S off as its ward
// breaks (whatever the tick), and again from each slam's start; a slam starts the tick that clock has run out. It lands
// BOSS_SLAM_WINDUP_S in: a hero inside its ring takes BOSS_SLAM_DAMAGE and is thrown back, one outside takes nothing,
// and Box3D's explosion blows a heavy crate and a downed hero's ragdoll inside it away. Its run re-simulates the deepest
// window there is, so every tick round the slam rolls back and is played again.
@(test)
the_slam_strikes_inside_its_ring :: proc(t: ^testing.T) {
	run := vault(3, window = u32(headless.max_window(&g.GAME)))
	defer headless.run_end(&run)
	state := &run.simulation.state
	boss := &state.boss
	king := king_of(&run)
	hurt_king(&run, 1)
	to_stage(&run, 2)
	play(&run, {}, 3) // warded, it walks to the middle and stands: harmless meanwhile
	middle := floor_of(&run).places.boss.pos
	testing.expectf(t, dmath.length((king.pos - middle).xz) < g.BOSS_MIDDLE_NEAR + 0.1, "warded at %v", king.pos)
	place_hero(&run, 2, on_floor(&run, middle + {-3.5, 0, 0}))
	hurt(&run, 2, g.HERO_HP) // down: a ragdoll in the ring
	settle(&run)
	place_hero(&run, 0, on_floor(&run, middle + {0, 0, 4}), {0, -1})
	place_hero(&run, 1, on_floor(&run, middle + {0, 0, -6.5}), {0, 1})
	place_prop(&run, VAULT_HEAVY_CRATE, on_floor(&run, middle + {3.5, 0, 0}))
	light_braziers(&run, int(g.BOSS_WARD_NEED[2]))
	headless.run_step(&run)
	broke := state.clock.time
	testing.expect(t, !boss.warded, "the ward broke")
	testing.expect_value(t, boss.next_slam, sim.Timer{broke, broke + sim.Game_Time(g.BOSS_SLAM_EVERY_TICKS)})
	testing.expect_value(t, king.phase, g.Elite_Phase.Chase)
	boss.next_slam.target = state.clock.time + 1 // its clock runs out on the next tick
	headless.run_pin(&run)
	headless.run_step(&run)
	testing.expect_value(t, king.phase, g.Elite_Phase.Slam)
	slammed := state.clock.time
	testing.expect_value(t, boss.next_slam, sim.Timer{slammed, slammed + sim.Game_Time(g.BOSS_SLAM_EVERY_TICKS)})
	phys := run.simulation.world.phys
	crate, _ := prop_at(&run, VAULT_HEAVY_CRATE)
	crate_before := physics.body_position(phys, crate.body)
	downed := sim.slot_data(run.simulation, 2)
	pelvis_before := physics.body_position(phys, downed.ragdoll.bones[.Pelvis])
	near, far := sim.slot_data(run.simulation, 0), sim.slot_data(run.simulation, 1)
	for state.clock.time < slammed + sim.Game_Time(g.BOSS_SLAM_WINDUP_TICKS) - 1 do headless.run_step(&run)
	testing.expect_value(t, headless.run_events(&run, g.Event_Boss_Slam), 0)
	testing.expect_value(t, near.hp, g.HERO_HP)
	headless.run_step(&run)
	testing.expect_value(t, headless.run_events(&run, g.Event_Boss_Slam), 1)
	testing.expect_value(t, near.hp, g.HERO_HP - g.BOSS_SLAM_DAMAGE)
	testing.expect_value(t, far.hp, g.HERO_HP)
	thrown := physics.body_linear_velocity(phys, near.body.body).xz
	away := dmath.dot(thrown, dmath.normalize(near.pos.xz - king.pos.xz))
	testing.expectf(t, away > g.BOSS_SLAM_KNOCK - 1, "the near hero thrown back at %v m/s", away)
	play(&run, {}, 0.5)
	moved := dmath.length((physics.body_position(phys, crate.body) - crate_before).xz)
	testing.expectf(t, moved > 0.3, "the crate moved %v m", moved)
	flung := dmath.length((physics.body_position(phys, downed.ragdoll.bones[.Pelvis]) - pelvis_before).xz)
	testing.expectf(t, flung > 0.3, "the ragdoll moved %v m", flung)
	scenarios.expect_synced(t, &run)
}

// The Barbarian's heave never takes the King: a press beside it heaves nothing.
@(test)
the_king_is_never_heaved :: proc(t: ^testing.T) {
	run := vault()
	defer headless.run_end(&run)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Barbarian})
	king := king_of(&run)
	beside := king.pos + {0, 0, g.BOSS_RADIUS + g.HERO_RADIUS + 0.3}
	place_hero(&run, 0, on_floor(&run, beside), {0, -1})
	press(&run, 0, .Ability)
	testing.expect_value(t, headless.run_events(&run, g.Event_Heaved), 0)
	testing.expect(t, king.phase != .Held, "not held")
	scenarios.expect_synced(t, &run)
}

// The King's fall, at the end of its third stage, wins: it dies, BOSS_GOLD goes in the purse (no coins fall), and the
// views are told.
@(test)
the_kings_fall_wins :: proc(t: ^testing.T) {
	run := vault()
	defer headless.run_end(&run)
	state := &run.simulation.state
	hurt_king(&run, 1)
	to_stage(&run, 3)
	headless.run_command(&run, 0, g.Command_Dev_Light_Braziers{})
	gold := state.gold
	hurt_king(&run, state.boss.hp_max)
	testing.expect_value(t, king_of(&run).phase, g.Elite_Phase.Dying)
	testing.expect_value(t, headless.run_events(&run, g.Event_Boss_Defeated), 1)
	testing.expect_value(t, state.gold, gold + g.BOSS_GOLD)
	testing.expect_value(t, headless.run_events(&run, g.Event_Loot_Dropped), 0)
	scenarios.expect_synced(t, &run)
}

// A wipe in the vault starts it over: the King asleep at its marker, whole, in its first stage, unwarded, and the
// braziers out.
@(test)
a_wipe_starts_the_vault_over :: proc(t: ^testing.T) {
	run := vault()
	defer headless.run_end(&run)
	state := &run.simulation.state
	hurt_king(&run, 1)
	to_stage(&run, 2)
	hurt(&run, 0, g.HERO_HP)
	play(&run, {}, g.WIPE_S + 0.1)
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 1)
	king := king_of(&run)
	testing.expect_value(t, king.phase, g.Elite_Phase.Idle)
	testing.expect_value(t, king.hp, g.BOSS_HP)
	testing.expect_value(t, state.boss.stage, 1)
	testing.expect(t, !state.boss.warded && state.boss.hp_max == 0, "asleep and unwarded")
	walk := sim.iterate(&state.braziers)
	for brazier in sim.next(&walk) do testing.expect(t, !brazier.lit, "the braziers are out")
	scenarios.expect_synced(t, &run)
}

// The King, BOSS_RADIUS wide on a navigation mesh baked for a hero's radius, walks round a pillar to a hero hidden
// behind it, sliding along the pillar's corner rather than snagging on it.
@(test)
the_king_walks_round_a_pillar :: proc(t: ^testing.T) {
	run := vault()
	defer headless.run_end(&run)
	king := king_of(&run)
	hurt_king(&run, 1)
	quiet(&run)
	pillar := [3]f32{-3, 0, -3} // game/levels/vault.tscn's Pillar1
	place_hero(&run, 0, on_floor(&run, pillar + {0, 0, -3}), {0, 1})
	from := on_floor(&run, pillar + {0.4, 0, 3.5})
	physics.character_teleport(run.simulation.world.phys, &king.body, from + {0, g.BOSS_CENTRE_ABOVE_FEET, 0})
	king.pos = from
	headless.run_pin(&run)
	hero := sim.slot_data(run.simulation, 0)
	reach := g.BOSS_CLEAVE_REACH + g.HERO_RADIUS
	ticks := 0
	for ; ticks < 8 * g.TICK_HZ && dmath.length((king.pos - hero.pos).xz) > reach; ticks += 1 do headless.run_step(&run)
	testing.expectf(
		t,
		ticks < 4 * g.TICK_HZ,
		"the King stood %v m off after %v ticks",
		dmath.length((king.pos - hero.pos).xz),
		ticks,
	)
	scenarios.expect_synced(t, &run)
}
