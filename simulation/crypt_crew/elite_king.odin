// The Bone King, the boss's elite (Elite_Kind.King; the fight round it is boss.odin): a skeleton Warrior BOSS_SCALE
// times as big, slow and shielded, never knocked, staggered or heaved. It walks its target's field straight at it and
// cleaves (its spec's windup, then its axe sweeps an arc: every hero up within BOSS_CLEAVE_REACH and BOSS_CLEAVE_COS of
// its facing, in sight, takes the blow, not only its target). From its second stage on, each time its slam's clock runs
// out it slams (Elite_Phase.Slam): BOSS_SLAM_WINDUP_S over a ring of BOSS_SLAM_RADIUS on the ground, which the view
// draws from the phase's start, then the floor shakes: every hero up inside the ring that no wall shields takes
// BOSS_SLAM_DAMAGE and is thrown back, and Box3D's explosion (physics.world_explode) blows the props and the downed
// heroes' ragdolls away. The slam's clock is a timer in the state (Boss.next_slam), started as the ward breaks and again
// as each slam starts, never the game clock's phase. Warded, it roars where it stands (BOSS_ROAR_S), then walks to the
// middle (its marker) and stands.
package crypt_crew

import "unified:dmath"
import "unified:nav"
import "unified:physics"
import "unified:sim"

// What the slam's explosion moves: the props and the ragdolls' bones (heroes up are thrown back by the rule, elites and
// the King's own body not at all).
SLAM_MASK :: CAT_PROP | CAT_RAGDOLL

// The King's way along its target's field, standing once BOSS_CLEAVE_SURE inside its cleave's reach, and its drive's
// speed scale (BOSS_STAGE_SPEED in its third stage).
king_heading :: proc(t: ^Tick, floor: ^Floor, elite: ^Elite, spot: Nav_Point) -> (heading: [2]f32, scale: f32) {
	scale = BOSS_STAGE_SPEED if t.state.boss.stage >= 3 else 1
	if king_in_reach(t, elite, BOSS_CLEAVE_SURE) do return
	return path_heading(t, floor, elite, spot), scale
}

// Warded, the King's way to the middle of its vault (its marker) along the floor, once its roar is over (BOSS_ROAR_S
// from its stage's start), until BOSS_MIDDLE_NEAR of it; zero before and there, or off the floor.
king_ward_heading :: proc(t: ^Tick, floor: ^Floor, elite: ^Elite, spot: Nav_Point) -> [2]f32 {
	if u32(t.time - elite.since) < BOSS_ROAR_TICKS do return {}
	middle, on_floor := floor_spot(floor, floor.places.boss.pos, HERO_NAV_REACH)
	if !on_floor || spot.poly == nav.NO_POLY do return {}
	if dmath.length_sq(middle.point.xz - elite.pos.xz) < BOSS_MIDDLE_NEAR * BOSS_MIDDLE_NEAR do return {}
	next := nav.steer(&floor.mesh, nav.field(&floor.fields, middle.poly), spot.poly, spot.point, middle.point)
	return dmath.normalize((next - spot.point).xz)
}

// Whether the King's target's capsule is within its cleave's reach of its centre (less `inside`).
king_in_reach :: proc(t: ^Tick, elite: ^Elite, inside: f32 = 0) -> bool {
	if elite.target == {} do return false
	reach := BOSS_CLEAVE_REACH + HERO_RADIUS - inside
	return dmath.length_sq(sim.player_data(t, elite.target).pos.xz - elite.pos.xz) <= reach * reach
}

// A chasing King, unwarded: slams once its slam's clock (from its second stage on) has run out, restarting it; else
// cleaves once its target is BOSS_CLEAVE_SURE inside its reach and in front of it (it turns to it first).
king_ready :: proc(t: ^Tick, elite: ^Elite) {
	boss := &t.state.boss
	if boss.warded do return
	if boss.stage >= 2 && boss.next_slam != {} && !sim.timer_running(t, boss.next_slam) {
		elite.phase, elite.since = .Slam, t.time
		sim.timer_start_ticks(t, &boss.next_slam, slam_every(boss))
		return
	}
	if king_in_reach(t, elite, BOSS_CLEAVE_SURE) && elite_faces_target(t, elite) do start_elite_attack(t, elite)
}

// The time from one slam's start to the next in the King's stage: BOSS_SLAM_EVERY_S, BOSS_SLAM_FAST_S in its third.
slam_every :: proc(boss: ^Boss) -> u32 {
	return BOSS_SLAM_FAST_TICKS if boss.stage >= 3 else BOSS_SLAM_EVERY_TICKS
}

// The cleave lands (its windup's end): every hero up whose capsule is within BOSS_CLEAVE_REACH of the King's centre,
// within BOSS_CLEAVE_COS of the facing the cleave locked and in sight, takes its spec's damage from the King.
king_cleave_lands :: proc(t: ^Tick, elite: ^Elite) {
	reach := BOSS_CLEAVE_REACH + HERO_RADIUS
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		offset := hero.pos.xz - elite.pos.xz
		if !hero_up(t, player) || dmath.length_sq(offset) > reach * reach do continue
		toward := dmath.normalize(offset)
		if toward != {} && dmath.dot(toward, elite.facing) < BOSS_CLEAVE_COS do continue
		if !elite_sees(t, elite, player, reach) do continue
		damage_hero(t, player, ELITE_SPECS[.King].damage, elite.pos)
	}
}

// The slam strikes the floor (its windup's end), announced: every hero up within BOSS_SLAM_RADIUS of the King's feet on
// the floor plan that no wall shields (a ray between their chests) takes BOSS_SLAM_DAMAGE from it and, still up, is
// thrown back (knock_hero); then Box3D's explosion at its feet blows the props and the ragdolls (a hero the blow
// downed among them) away.
king_slam_lands :: proc(t: ^Tick, elite: ^Elite) {
	sim.emit(t, Event_Boss_Slam{position = sim.Position(elite.pos)})
	chest := elite.pos + {0, CHEST_HEIGHT, 0}
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		offset := hero.pos.xz - elite.pos.xz
		if !hero_up(t, player) || dmath.length_sq(offset) > BOSS_SLAM_RADIUS * BOSS_SLAM_RADIUS do continue
		target := hero.pos + {0, CHEST_HEIGHT, 0}
		if _, walled := physics.world_cast_ray_closest(t.world.phys, chest, target - chest, SIGHT_FILTER); walled do continue
		damage_hero(t, player, BOSS_SLAM_DAMAGE, elite.pos)
		if hero_up(t, player) do knock_hero(t, hero, dmath.normalize(offset), BOSS_SLAM_KNOCK)
	}
	explosion := physics.default_explosion_def()
	explosion.mask_bits = SLAM_MASK
	explosion.position = elite.pos + {0, BOSS_SLAM_HEIGHT, 0}
	explosion.radius = BOSS_SLAM_RADIUS
	explosion.falloff = BOSS_SLAM_FALLOFF
	explosion.impulse_per_area = BOSS_SLAM_PUSH
	physics.world_explode(t.world.phys, explosion)
}

// A hero up thrown along `dir` (unit, on the floor plan; zero: straight back from where it faces) by `speed` metres per
// second: a velocity change on its capsule, which its drive then brakes.
knock_hero :: proc(t: ^Tick, hero: ^Hero, dir: [2]f32, speed: f32) {
	if hero.body == {} do return
	away := dir if dir != {} else -hero.facing
	velocity := physics.body_linear_velocity(t.world.phys, hero.body.body)
	physics.body_set_linear_velocity(t.world.phys, hero.body.body, velocity + [3]f32{away.x, 0, away.y} * speed)
}
