// The heroes' movement: each turns to its aim (else its move), walks through physics.Character (a dynamic capsule
// driven toward the stick's velocity, held above the floor by a spring), and after the physics step has its feet and
// velocity read back into the block, where the rules and the views read them without asking Box3D.
package crypt_crew

import "unified:dmath"
import "unified:nav"
import "unified:physics"
import "unified:sim"

// Where a hero looks after this input: along its aim, else along its move once the stick is pushed past TURN_STICK,
// else where it looked. The view calls it too, on the newest local input, so the local hero turns at once.
hero_facing :: proc(input: Input, facing: [2]f32) -> [2]f32 {
	if aim := dmath.dir2_vec(input.aim); aim != {} do return aim
	move := dmath.stick(input.move_x, input.move_z)
	if dmath.length_sq(move) > TURN_STICK * TURN_STICK do return dmath.normalize(move)
	return facing
}

// The hero's warp epoch as its view pushes it: its own (Hero.warp) and its body's added, so a new body and a teleport
// both move it on.
hero_warp :: proc(phys: ^physics.World, hero: ^Hero) -> u8 {
	return hero.warp + physics.body_warp(phys, hero.body.body)
}

// Each present hero that is up faces its input (hero_facing), unless it dashes: a charge and a roll keep their line.
face_heroes :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		if hero.action == .Down || hero.action == .Charge || hero.action == .Roll do continue
		hero.facing = hero_facing(sim.input(t, player), hero.facing)
	}
}

// Each slot's hero up on the walkable floor (the World's hero_spots, scratch rebuilt every tick from the block): the
// floor's point nearest its feet within HERO_NAV_REACH (floor_spot); nav.NO_POLY for an empty slot, a hero down, or
// one off the floor (on a crate's top, say). What minions chase and surges measure from.
locate_heroes :: proc(t: ^Tick) {
	floor := floor_of(t)
	for &spot, slot in t.world.hero_spots {
		player := sim.player_in_slot(t, slot)
		on_floor := false
		if hero_up(t, player) do spot, on_floor = floor_spot(floor, sim.player_data(t, player).pos, HERO_NAV_REACH)
		if !on_floor do spot.poly = nav.NO_POLY
	}
}

// Each present hero's controller is driven toward its stick at its class's max_speed, slowed by what it carries
// (carry_speed) and by what it does (attacking, blocking, reviving), or along its facing in a dash; a hero down is
// driven to a stop (action_drive). Heroes never jump.
move_heroes :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		input := sim.input(t, player)
		move, scale := action_drive(t, hero, dmath.stick(input.move_x, input.move_z))
		physics.character_update(t.world.phys, &hero.body, t.world.hero_defs[hero.class], move, false, scale)
	}
}

// After the physics step: each present hero's feet and velocity, from its body.
read_back_heroes :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero in sim.next(&heroes) {
		hero.pos = physics.body_position(t.world.phys, hero.body.body) - {0, HERO_CENTRE_ABOVE_FEET, 0}
		hero.vel = physics.body_linear_velocity(t.world.phys, hero.body.body)
	}
}
