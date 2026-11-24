// The heroes' movement: each turns to its aim (else its move), walks through physics.Character (a dynamic capsule
// driven toward the stick's velocity, held above the floor by a spring), and after the physics step has its feet and
// velocity read back into the block, where the rules and the views read them without asking Box3D.
package crypt_crew

import "unified:dmath"
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

// Each present hero faces its input (hero_facing).
face_heroes :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) do hero.facing = hero_facing(sim.input(t, player), hero.facing)
}

// Each present hero's controller is driven toward its stick at its class's max_speed. Heroes never jump.
move_heroes :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		input := sim.input(t, player)
		move := dmath.stick(input.move_x, input.move_z)
		physics.character_update(t.world.phys, &hero.body, t.world.hero_defs[hero.class], move, false, 1)
	}
}

// After the physics step: each present hero's feet and velocity, from its body.
read_back_heroes :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero in sim.next(&heroes) {
		hero.pos = physics.body_position(t.world.phys, hero.body.body) - {0, HERO_FEET, 0}
		hero.vel = physics.body_linear_velocity(t.world.phys, hero.body.body)
	}
}
