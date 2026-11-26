// The skeleton Warrior: slow, tough and shielded. It walks its target's field straight at it and swings an axe (its
// spec's windup, then the blow, as a minion's swing). Its shield takes most of a blow from its front: the guard judges
// where the blow comes from against where the Warrior faces (never the attacker's facing), and a Warrior turns at
// ELITE_TURN_COS a tick, so a hero who gets round it hits it whole. A stagger lowers the shield, and a broken guard
// (break_guard: a thrown prop, a Knight's charge, a Mage's fireball) keeps it down for GUARD_BREAK_S.
package crypt_crew

import "unified:dmath"
import "unified:sim"

// The Warrior's way: along its target's field, standing once ELITE_STAND inside its reach.
warrior_heading :: proc(t: ^Tick, floor: ^Floor, elite: ^Elite, spot: Nav_Point) -> [2]f32 {
	if elite_in_reach(t, elite, ELITE_STAND) do return {}
	return path_heading(t, floor, elite, spot)
}

// A chasing Warrior swings once its target is in reach and in front of it (it turns to it first).
warrior_ready :: proc(t: ^Tick, elite: ^Elite) {
	if elite_in_reach(t, elite) && elite_faces_target(t, elite) do start_elite_attack(t, elite)
}

// Whether an elite holds a shield up at game time `now`: a Warrior, neither rising nor dying, not staggered, its guard
// not broken. What warrior_guards asks, and what the view's glint shows.
shield_up :: proc(now: sim.Game_Time, elite: ^Elite) -> bool {
	if elite.kind != .Warrior || elite.phase == .Rise || elite.phase == .Dying do return false
	return !sim.timer_running(now, elite.stagger) && !sim.timer_running(now, elite.guard_down)
}

// Whether a blow from `from` (on the floor plan) meets a Warrior's shield: its shield is up (shield_up) and `from`
// lies within ELITE_GUARD_COS of its facing. A blow from its own centre (a dev hurt) has no side and is never guarded.
warrior_guards :: proc(t: ^Tick, elite: ^Elite, from: [2]f32) -> bool {
	if !shield_up(t.time, elite) do return false
	toward := dmath.normalize(from - elite.pos.xz)
	return toward != {} && dmath.dot(toward, elite.facing) >= ELITE_GUARD_COS
}

// What a guarded blow of `damage` takes: ELITE_GUARD_TAKE of it, rounded, at least 1.
guard_take :: proc(damage: i16) -> i16 {
	return i16(dmath.to_i32_clamped(dmath.round(f32(damage) * ELITE_GUARD_TAKE), 1, i32(max(i16))))
}
