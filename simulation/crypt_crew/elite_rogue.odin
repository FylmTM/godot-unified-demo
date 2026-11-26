// The skeleton Rogue: a flanker. Far from its target, or out of its sight, it walks the target's field; within
// FLANK_NEAR it circles round the target, FLANK_BEHIND out, to the spot that far behind the target's facing, and
// lunges from there: facing the target at its start, driven at LUNGE_SPEED through the windup and homing at a turn's
// pace, the blow landing as a swing does. A target that keeps turning to face it is lunged at anyway after
// FLANK_GIVE_UP_S, from FLANK_LUNGE. After a lunge it backs off for FLANK_RETREAT_S and circles again. Circling is
// plain geometry about the target's centre (a tangent and a pull back onto the circle), no trig: near a hero the floor
// is open, and its capsule slides round what it meets.
package crypt_crew

import "unified:dmath"
import "unified:sim"

// The Rogue's way: the path while it is far or out of sight; else round its target to the spot behind it, the short way
// round (its index breaks the tie of one dead ahead), pulled back onto the FLANK_BEHIND circle, and straight at the
// spot once within a quarter turn of it.
rogue_heading :: proc(t: ^Tick, floor: ^Floor, elite: ^Elite, spot: Nav_Point) -> [2]f32 {
	hero := sim.player_data(t, elite.target)
	from_hero := elite.pos.xz - hero.pos.xz
	distance := dmath.length(from_hero)
	if distance > FLANK_NEAR || distance == 0 || !elite_sees(t, elite, elite.target, FLANK_NEAR) {
		sim.timer_stop(&elite.patience) // not circling: its patience starts again when it circles again
		return path_heading(t, floor, elite, spot)
	}
	if elite.patience == {} do sim.timer_start_ticks(t, &elite.patience, FLANK_GIVE_UP_TICKS)
	behind := -hero.facing
	out := from_hero / distance
	if dmath.dot(out, behind) > 0.7071068 do return dmath.normalize(flank_spot(hero) - elite.pos.xz) // within 45°
	side := dmath.cross2(out, behind)
	if side == 0 do side = 1 if elite.pos.x < hero.pos.x else -1 // dead ahead: either way, the same on every peer
	tangent := [2]f32{-out.y, out.x} * (1 if side > 0 else -1)
	return dmath.normalize(tangent + out * ((FLANK_BEHIND - distance) * FLANK_PULL))
}

// The spot FLANK_BEHIND behind `hero`'s facing, on the floor plan.
flank_spot :: proc(hero: ^Hero) -> [2]f32 {
	return hero.pos.xz - hero.facing * FLANK_BEHIND
}

// A chasing Rogue that sees its target within FLANK_NEAR (no lunge through a wall) lunges once it is within
// FLANK_ARRIVE of its spot behind the target, or, once its patience ran out (FLANK_GIVE_UP_S of circling: walking in
// from afar spends none), from within FLANK_LUNGE of it: facing it at once (a lunge has a direction).
rogue_ready :: proc(t: ^Tick, elite: ^Elite) {
	if !elite_sees(t, elite, elite.target, FLANK_NEAR) do return
	hero := sim.player_data(t, elite.target)
	arrived := dmath.length_sq(flank_spot(hero) - elite.pos.xz) <= FLANK_ARRIVE * FLANK_ARRIVE
	impatient := elite.patience != {} && !sim.timer_running(t, elite.patience)
	close := dmath.length_sq(hero.pos.xz - elite.pos.xz) <= FLANK_LUNGE * FLANK_LUNGE
	if !arrived && !(impatient && close) do return
	if to_hero := dmath.normalize(hero.pos.xz - elite.pos.xz); to_hero != {} do elite.facing = to_hero
	sim.timer_stop(&elite.patience)
	start_elite_attack(t, elite)
}
