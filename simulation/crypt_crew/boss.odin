// The boss, the Bone King: the vault's `boss` marker's, an elite of its own kind (Elite_Kind.King, elite_king.odin:
// its approach, its cleave and its slam), so the elite machinery gives it its Box3D body, its damage (damage_elite,
// which asks boss_takes and boss_hurt here), the crossbow's rewound ray, its sight and its view. This file is the fight
// round it: the King sleeps at its marker until a hero comes into sight or hits it, and wakes with BOSS_HP and
// BOSS_HP_PER_HERO for each other hero present then (times the difficulty's boss_hp_scale). Its guard is the Warrior's,
// always up save for BOSS_GUARD_DOWN_S after a thrown prop, a charge or a fireball breaks it (break_guard): the damage
// window, and the party's split between those who break it and those who strike.
//
// Its stages, at two thirds and one third of its health: it roars, every brazier goes out (douse_braziers), and it is
// warded, taking no damage, while it walks to the middle and stands; BOSS_SUMMON skeletons rise at the rim graves (the
// director's quota, State.rising) and the surges come every BOSS_SURGE_S. Lighting BOSS_WARD_NEED of the vault's
// braziers (by the heroes present now, so a joiner raises it and a leaver lowers it) breaks the ward. No blow takes it
// past its stage's end, so each stage's health is dealt in that stage. From its second stage on it slams
// (elite_king.odin), its first slam BOSS_SLAM_EVERY_S after the ward breaks; its third moves BOSS_STAGE_SPEED faster.
// Its fall puts BOSS_GOLD in the purse and wins the run (run_won); a wipe restarts the vault, the King asleep and whole.
package crypt_crew

import "unified:dmath"
import "unified:sim"

// The boss's place (a `boss` marker), one a floor at most.
Boss_Def :: struct {
	pos:    [3]f32,
	facing: [2]f32, // the marker's +Z on the floor plan, as an elite marker's: the way its model faces
	placed: bool, // the floor has one
	_pad:   [3]u8,
}

// The floor's boss (State.boss): zero on a floor without a boss marker.
Boss :: struct {
	elite:     sim.Handle(Elite), // the King (its row lingers as it dies, then the handle names nothing)
	next_slam: sim.Timer, // from its second stage on, unwarded: its next slam waits for it (started as its ward breaks)
	hp_max:    i16, // its full health, set as it wakes (0: asleep)
	stage:     u8, // 1, 2 or 3 (0: no boss)
	warded:    bool, // it takes no damage until enough braziers are lit
}

// The King roared into `stage` (2 or 3): its braziers went out and its ward is up.
Event_Boss_Stage :: struct {
	stage: u8,
}

// The King's slam struck the floor at `position` (its feet).
Event_Boss_Slam :: struct {
	position: sim.Position,
}

// The King's ward went up (`up`) or broke.
Event_Boss_Ward :: struct {
	up: bool,
}

// The King fell at `position`: the run is won, and the purse holds `gold` with its BOSS_GOLD (the HUD's purse shows it,
// as a pickup's total).
Event_Boss_Defeated :: struct {
	position: sim.Position,
	gold:     u32,
}

// ---- the run's hooks: docs/plan.md, milestone 7 step 1 (the run) wires them to Run and DIFFICULTY at its merge.

// What the difficulty multiplies the King's health by (DIFFICULTY[...].boss_hp; 1 until the run lands).
boss_hp_scale :: proc(t: ^Tick) -> f32 {
	return 1
}

// The run is won (the King fell): the run's phase moves to Won (a no-op until the run lands).
run_won :: proc(t: ^Tick) {
}

// ----

// The floor's King, asleep at its marker (entering a floor: the boss is reset whether the floor has one or not; none
// under a held crowd, as no elite rises then).
spawn_boss :: proc(t: ^Tick) {
	t.state.boss = {}
	def := &floor_of(t).places.boss
	if !def.placed || t.setup.crowd != .None do return
	handle, ok := spawn_elite(t.state, t.world, .King, def.pos, def.facing, .Idle, t.time)
	assert(ok, "crypt_crew: no elite row for the boss") // a floor is entered with the elite table empty
	t.state.boss = {
		elite = handle,
		stage = 1,
	}
}

// The King's elite row, if it is alive (neither dying nor gone); nil otherwise.
boss_elite :: proc(t: ^Tick) -> ^Elite {
	if t.state.boss.stage == 0 do return nil
	elite := sim.get(&t.state.elites, t.state.boss.elite)
	return elite if elite != nil && elite.phase != .Dying else nil
}

// Whether the King is warded now (the surges' clock asks: surge_every).
boss_warded :: proc(t: ^Tick) -> bool {
	return t.state.boss.warded && boss_elite(t) != nil
}

// The King's full health for the heroes present now: BOSS_HP, BOSS_HP_PER_HERO more for each beyond the first, times
// the difficulty's scale, rounded.
boss_full_hp :: proc(t: ^Tick) -> i16 {
	extra := dmath.max(sim.present_count(t) - 1, 0)
	base := f32(BOSS_HP) + f32(BOSS_HP_PER_HERO) * f32(extra)
	return i16(dmath.to_i32_clamped(dmath.round(base * boss_hp_scale(t)), 1, i32(max(i16))))
}

// How many lit braziers break the ward with the heroes present now (BOSS_WARD_NEED; with nobody present, a lone hero's).
ward_need :: proc(t: ^Tick) -> i32 {
	return BOSS_WARD_NEED[dmath.clamp(sim.present_count(t), 1, PLAYERS) - 1]
}

// The King woke (it was asleep, `hp_max` 0): its full health is set for the heroes present now (boss_full_hp), what it
// took on waking kept (a blow that woke it).
@(private = "file")
wake_boss :: proc(t: ^Tick, elite: ^Elite) {
	boss := &t.state.boss
	boss.hp_max = boss_full_hp(t)
	elite.hp += boss.hp_max - ELITE_SPECS[.King].hp
}

// What reaches the King of a blow that would take `taken` (damage_elite asks, the guard already judged): nothing while
// it is warded; else at most down to its stage's end (two thirds of its health in stage 1, one third in stage 2), so a
// blow never skips a stage. A blow that wakes it is taken from its full health (wake_boss).
boss_takes :: proc(t: ^Tick, elite: ^Elite, taken: i16) -> i16 {
	boss := &t.state.boss
	if boss.hp_max == 0 do wake_boss(t, elite)
	if boss.warded do return 0
	return dmath.min(taken, elite.hp - stage_end(boss))
}

// The health at which the King's stage ends: two thirds of its full health in stage 1, one third in stage 2, none in
// stage 3 (its death).
@(private = "file")
stage_end :: proc(boss: ^Boss) -> i16 {
	switch boss.stage {
	case 1:
		return i16(i32(boss.hp_max) * 2 / 3)
	case 2:
		return i16(i32(boss.hp_max) / 3)
	}
	return 0
}

// After a blow the King took (damage_elite): at its stage's end, its next stage begins (enter_stage).
boss_hurt :: proc(t: ^Tick, elite: ^Elite) {
	boss := &t.state.boss
	if boss.stage < 3 && elite.hp > 0 && elite.hp <= stage_end(boss) do enter_stage(t, elite, boss.stage + 1)
}

// The King roars into `stage`: what it was doing stops (a cleave or a slam cut off), every brazier goes out, its ward
// goes up, BOSS_SUMMON skeletons are owed to the graves (as a surge's, up to the floor's cap and the table's rows), and
// the next surge comes BOSS_SURGE_S on (surge_every keeps that pace while it is warded).
@(private = "file")
enter_stage :: proc(t: ^Tick, elite: ^Elite, stage: u8) {
	boss := &t.state.boss
	boss.stage, boss.warded = stage, true
	elite.phase, elite.since = .Chase, t.time
	douse_braziers(t)
	room := dmath.min(floor_of(t).minion_cap - minions_alive(&t.state.minions), free_rows(&t.state.minions))
	t.state.rising += u32(dmath.max(dmath.min(BOSS_SUMMON, room - int(t.state.rising)), 0))
	sim.timer_start_ticks(t, &t.state.surge, BOSS_SURGE_TICKS)
	sim.emit(t, Event_Boss_Stage{stage = stage})
	sim.emit(t, Event_Boss_Ward{up = true})
}

// Each tick (after the elites age): the King woken by sight is given its full health (wake_boss), and a ward up breaks
// once ward_need braziers are lit, the slam's clock starting then (elite_king.odin: slam_every).
update_boss :: proc(t: ^Tick) {
	elite := boss_elite(t)
	if elite == nil do return
	boss := &t.state.boss
	if boss.hp_max == 0 && elite.phase != .Idle do wake_boss(t, elite)
	if !boss.warded || braziers_lit(t) < ward_need(t) do return
	boss.warded = false
	sim.timer_start_ticks(t, &boss.next_slam, slam_every(boss))
	sim.emit(t, Event_Boss_Ward{up = false})
}

// The King fell (damage_elite, its row dying): BOSS_GOLD goes in the purse, the views are told, and the run is won.
boss_defeated :: proc(t: ^Tick, elite: ^Elite) {
	t.state.boss.warded = false
	t.state.gold += BOSS_GOLD
	sim.emit(t, Event_Boss_Defeated{position = sim.Position(elite.pos), gold = t.state.gold})
	run_won(t)
}
