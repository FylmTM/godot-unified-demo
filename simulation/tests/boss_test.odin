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

// A sync-tested run on the vault with `seated` heroes at `difficulty`, its surges held off (hold_surges); `window` is how
// far back each step is re-simulated.
@(private = "file")
vault :: proc(seated := 1, window: u32 = 8, difficulty := g.Difficulty.Normal) -> headless.Run(g.Game) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Vault, difficulty = difficulty}, window, seated)
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
// other hero present then, times the difficulty's boss_hp, the waking blow taken from that; on Hard as on Normal, a
// blow of all its health stops at its first stage's end.
@(test)
the_kings_health_is_the_partys :: proc(t: ^testing.T) {
	for difficulty in g.Difficulty {
		for seated in ([2]int{1, 3}) {
			run := vault(seated, difficulty = difficulty)
			defer headless.run_end(&run)
			king := king_of(&run)
			boss := &run.simulation.state.boss
			testing.expect_value(t, king.phase, g.Elite_Phase.Idle)
			testing.expect_value(t, boss.hp_max, 0)
			hurt_king(&run, 10)
			base := f32(g.BOSS_HP + g.BOSS_HP_PER_HERO * i16(seated - 1))
			full := i16(dmath.round(base * g.DIFFICULTY[difficulty].boss_hp))
			testing.expectf(
				t,
				boss.hp_max == full,
				"%v, %d: its full health %d, not %d",
				difficulty,
				seated,
				boss.hp_max,
				full,
			)
			testing.expectf(
				t,
				king.hp == full - 10,
				"%v, %d: %d of %d after the blow",
				difficulty,
				seated,
				king.hp,
				full,
			)
			testing.expect_value(t, boss.stage, 1)
			hurt_king(&run, boss.hp_max)
			testing.expectf(
				t,
				king.hp == i16(i32(full) * 2 / 3),
				"%v, %d: the stage ends at %d",
				difficulty,
				seated,
				king.hp,
			)
			testing.expect_value(t, boss.stage, 2)
			scenarios.expect_synced(t, &run)
		}
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
// take it past the stage's end. The ward breaks at its need (one brazier alone), and the third stage douses them
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
	testing.expect_value(t, state.rising, u32(g.BOSS_SUMMON[0]))
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

// The ward's need is the heroes present now (BOSS_WARD_NEED: 1, 2, 3, 4): a ward a brazier short holds and one at its
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
		decided := [g.PLAYERS]int{1, 2, 3, 4} // the design's, by party size
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

// The King's fall ends the run, won: the run's phase is Won, Event_Run_Ended says so, the save becomes the hub's (no run
// to continue: the vault's save goes), and the director raises nothing more (a surge due right after the fall never
// comes) until the party is back in the hub.
@(test)
the_kings_fall_ends_the_run :: proc(t: ^testing.T) {
	run := vault()
	defer headless.run_end(&run)
	state := &run.simulation.state
	testing.expect_value(t, state.saved.floor, g.Level_Id.Vault) // a run begun on the vault saved there
	hurt_king(&run, 1)
	to_stage(&run, 3)
	headless.run_command(&run, 0, g.Command_Dev_Light_Braziers{})
	hurt_king(&run, state.boss.hp_max)
	ended, found := headless.run_last_event(&run, g.Event_Run_Ended)
	testing.expect(t, found && ended.won && ended.depth == state.depth, "the fall ends the run, won")
	testing.expect_value(t, state.run.phase, g.Run_Phase.Won)
	testing.expect_value(t, state.saved.floor, g.Level_Id.Hub)
	state.surge = {
		start  = state.clock.time,
		target = state.clock.time + 2,
	}
	headless.run_pin(&run)
	surges := headless.run_events(&run, g.Event_Surge)
	play(&run, {}, 2)
	testing.expect_value(t, headless.run_events(&run, g.Event_Surge), surges)
	scenarios.expect_synced(t, &run)
}

// A late joiner in the vault mid-ward: a snapshot taken while the King stands warded in its second stage, a brazier lit
// and its stage's skeletons rising, continues to the same checksums as the run it came from, its refs clean, through a
// new hero's arrival there (the ward's need rising with it) and the braziers lit that break the ward for the three.
@(test)
a_late_joiner_in_the_vault_mid_ward :: proc(t: ^testing.T) {
	run := vault(2)
	defer headless.run_end(&run)
	boss := &run.simulation.state.boss
	hurt_king(&run, 1)
	for _ in 0 ..< 3 {
		if boss.stage >= 2 do break
		hurt_king(&run, boss.hp_max)
	}
	testing.expect(t, boss.stage == 2 && boss.warded, "the King warded in its second stage")
	light_braziers(&run, 1)
	play(&run, {}, 0.5) // its skeletons on their way up
	snapshot := sim.snapshot_encode(run.simulation, run.simulation.tick)
	defer delete(snapshot)
	late, err := headless.run_begin_from_snapshot(&g.GAME, snapshot)
	defer headless.run_end(&late)
	testing.expect_value(t, err, sim.Snap_Error.None)
	testing.expect_value(t, physics.check_refs(late.simulation.world.phys, &late.simulation.state), "")
	headless.run_seat(&run, 2, 3) // the joiner, on both
	headless.run_seat(&late, 2, 3)
	agreed := true
	for tick in 0 ..< 2 * g.TICK_HZ {
		if tick == g.TICK_HZ { 	// the three's need lit, on both
			light_braziers(&run, int(g.BOSS_WARD_NEED[2]))
			light_braziers(&late, int(g.BOSS_WARD_NEED[2]))
		}
		inputs := headless.run_inputs(&run)
		headless.run_step(&run, &inputs)
		headless.run_step(&late, &inputs)
		if agreed && sim.checksum(late.simulation) != sim.checksum(run.simulation) {
			testing.expectf(t, false, "the late joiner differs %d ticks on", tick + 1)
			agreed = false
		}
	}
	testing.expect(t, !boss.warded && !late.simulation.state.boss.warded, "the three's need broke the ward on both")
	testing.expect_value(t, sim.present_count(&late.simulation.state.players), 3)
	scenarios.expect_synced(t, &run)
	scenarios.expect_synced(t, &late)
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

// The vault is calm outside the King's wards: a surge due there raises nothing while it sleeps or fights unwarded. In a
// ward its stage raises BOSS_SUMMON for the heroes present, its surges come, and each is SURGE_BASE and SURGE_PER_HERO
// for each hero alone (no SURGE_GROWTH for the surges faced, no SURGE_PER_DEPTH for the floors gone down); a brazier lit
// there leaves the ward's surge clock as it was.
@(test)
the_vault_is_calm_outside_its_wards :: proc(t: ^testing.T) {
	run := vault(2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	state.depth, state.floor_surges = 3, 4
	due_now(&run)
	play(&run, {}, 1)
	testing.expect_value(t, headless.run_events(&run, g.Event_Surge), 0)
	hurt_king(&run, 1)
	due_now(&run)
	play(&run, {}, 1)
	testing.expect(
		t,
		headless.run_events(&run, g.Event_Surge) == 0 && state.rising == 0,
		"awake and unwarded: no surge",
	)
	hurt_king(&run, state.boss.hp_max)
	testing.expect(t, state.boss.warded, "warded")
	testing.expect_value(t, state.rising, u32(g.BOSS_SUMMON[1]))
	quiet(&run)
	due_now(&run)
	headless.run_step(&run)
	surge, surged := headless.run_last_event(&run, g.Event_Surge)
	testing.expect(t, surged, "a surge in the ward")
	testing.expect_value(t, surge.count, i32(g.SURGE_BASE + 2 * g.SURGE_PER_HERO))
	clock := state.surge
	headless.run_command(&run, 0, g.Command_Dev_Light_Braziers{})
	testing.expect(t, headless.run_events(&run, g.Event_Brazier) > 0, "braziers lit")
	testing.expect_value(t, state.surge, clock)
	scenarios.expect_synced(t, &run)
}

// The surge clock run out now (as the director reads it), the run pinned there.
@(private = "file")
due_now :: proc(run: ^headless.Run(g.Game)) {
	state := &run.simulation.state
	state.surge = {
		start  = state.clock.time,
		target = state.clock.time,
	}
	headless.run_pin(run)
}

// A lone hero wears the King's guard down: every BOSS_SOLO_GUARD_BLOWS-th blow it takes breaks it. With a second hero
// present the same blows break nothing (the party's throws, charges and fireballs do).
@(test)
a_lone_heros_blows_break_the_kings_guard :: proc(t: ^testing.T) {
	for seated in 1 ..= 2 {
		run := vault(seated)
		defer headless.run_end(&run)
		headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Knight})
		king := king_of(&run)
		hurt_king(&run, 1)
		quiet(&run)
		front := king.pos.xz + king.facing * (g.BOSS_RADIUS + g.HERO_RADIUS + 0.3)
		place_hero(&run, 0, on_floor(&run, {front.x, king.pos.y, front.y}), -king.facing)
		inputs: [g.PLAYERS]g.Input
		inputs[0].buttons = {.Attack}
		inputs[0].aim = dmath.dir2(-king.facing)
		guarded := 0
		for _ in 0 ..< 2 * g.TICK_HZ {
			headless.run_step(&run, inputs)
			for &raw in sim.events_at(run.simulation, run.simulation.tick) {
				if hit, ok := sim.event_value(&raw, g.Event).(g.Event_Elite_Hit); ok && hit.guarded && hit.damage > 0 {
					guarded += 1
				}
			}
			if guarded >= int(g.BOSS_SOLO_GUARD_BLOWS) do break
		}
		testing.expectf(t, guarded >= int(g.BOSS_SOLO_GUARD_BLOWS), "%d heroes: %d guarded blows", seated, guarded)
		broken := headless.run_events(&run, g.Event_Guard_Broken)
		testing.expectf(t, (broken == 1) == (seated == 1), "%d heroes: the guard broke %d times", seated, broken)
		scenarios.expect_synced(t, &run)
	}
}

// The vault's Pillar1 (game/levels/vault.tscn: 1.5 m square), and a spot for the King facing it, a hand clear of it.
@(private = "file")
PILLAR :: [3]f32{-3, 0, -3}
@(private = "file")
BY_PILLAR :: [3]f32{-1.4, 0, -3}

// Moves the King to stand at `feet` facing `facing`, at rest, and pins the run there.
@(private = "file")
place_king :: proc(run: ^headless.Run(g.Game), feet: [3]f32, facing: [2]f32) {
	king := king_of(run)
	physics.character_teleport(run.simulation.world.phys, &king.body, feet + {0, g.BOSS_CENTRE_ABOVE_FEET, 0})
	king.pos, king.facing = feet, facing
	headless.run_pin(run)
}

// A wall shields from the slam: a hero inside its ring behind a pillar takes nothing, one inside in the open takes it.
@(test)
a_wall_shields_from_the_slam :: proc(t: ^testing.T) {
	run := vault(2)
	defer headless.run_end(&run)
	state := &run.simulation.state
	boss := &state.boss
	hurt_king(&run, 1)
	to_stage(&run, 2)
	light_braziers(&run, int(g.BOSS_WARD_NEED[1]))
	headless.run_step(&run)
	testing.expect(t, !boss.warded, "the ward broke")
	king := on_floor(&run, BY_PILLAR)
	place_king(&run, king, {-1, 0})
	place_hero(&run, 0, on_floor(&run, PILLAR + {-1.2, 0, 0}), {1, 0}) // behind the pillar, 2.8 m off
	place_hero(&run, 1, on_floor(&run, king + {0, 0, 3}), {0, -1}) // in the open, 3 m off
	boss.next_slam.target = state.clock.time + 1
	headless.run_pin(&run)
	for _ in 0 ..< g.BOSS_SLAM_WINDUP_TICKS + 2 {
		headless.run_step(&run)
		if headless.run_events(&run, g.Event_Boss_Slam) > 0 do break
	}
	testing.expect_value(t, headless.run_events(&run, g.Event_Boss_Slam), 1)
	testing.expect_value(t, sim.slot_data(run.simulation, 0).hp, g.HERO_HP)
	testing.expect_value(t, sim.slot_data(run.simulation, 1).hp, g.HERO_HP - g.BOSS_SLAM_DAMAGE)
	scenarios.expect_synced(t, &run)
}

// The cleave meets every hero up in its arc within its reach and in sight, its target or not: a bystander in the arc is
// hit; one in the arc past its reach, one behind the King and its target behind a pillar are not.
@(test)
the_cleave_meets_its_arc_in_reach_and_sight :: proc(t: ^testing.T) {
	run := vault(4)
	defer headless.run_end(&run)
	state := &run.simulation.state
	hurt_king(&run, 1)
	quiet(&run)
	at := on_floor(&run, BY_PILLAR)
	place_king(&run, at, {-1, 0})
	place_hero(&run, 0, on_floor(&run, PILLAR + {-1.2, 0, 0}), {1, 0}) // in the arc and reach, behind the pillar
	place_hero(&run, 1, on_floor(&run, at + {-1, 0, 2.2})) // in the arc, 2.4 m off: hit
	place_hero(&run, 2, on_floor(&run, at + {-1.9, 0, 3.29})) // in the arc, 3.8 m off: past its reach
	place_hero(&run, 3, on_floor(&run, at + {2, 0, 0})) // behind it
	king := king_of(&run)
	king.target = sim.player_in_slot(run.simulation, 0)
	king.phase, king.since = .Attack, state.clock.time
	headless.run_pin(&run)
	for _ in 0 ..< g.ELITE_SPECS[.King].windup + 1 do headless.run_step(&run)
	hp: [g.PLAYERS]i16
	for slot in 0 ..< g.PLAYERS do hp[slot] = sim.slot_data(run.simulation, slot).hp
	hit := g.HERO_HP - g.ELITE_SPECS[.King].damage
	testing.expectf(t, hp == {g.HERO_HP, hit, g.HERO_HP, g.HERO_HP}, "after the cleave: %v", hp)
	scenarios.expect_synced(t, &run)
}

// A stage's summon owes no more than the floor's room: entered with the vault a skeleton short of its cap, one is owed.
@(test)
a_stages_summon_fits_the_floors_room :: proc(t: ^testing.T) {
	run := vault()
	defer headless.run_end(&run)
	state := &run.simulation.state
	hurt_king(&run, 1)
	quiet(&run)
	floor := floor_of(&run)
	spot, _ := g.floor_spot(floor, floor.places.hero_spawns[1], 2)
	for g.minions_alive(&state.minions) < floor.minion_cap - 1 {
		_, ok := g.spawn_minion(state, spot.point, spot.poly, {0, 1}, .Idle, state.clock.time, 0)
		if !ok do break
	}
	headless.run_pin(&run)
	testing.expect(t, g.BOSS_SUMMON[0] > 1, "a summon larger than the room")
	hurt_king(&run, state.boss.hp_max)
	testing.expect_value(t, state.boss.stage, 2)
	testing.expect_value(t, state.rising, 1)
	scenarios.expect_synced(t, &run)
}
