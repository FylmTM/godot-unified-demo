// The Mage's fireballs: rows of the State with no body, each lobbed from the Mage's hands to the point fireball_target
// gave as its cast left (Fireball.to), over anything between, bursting there FIREBALL_FLIGHT_S after the cast. Its
// flight is the view's (a parabola from `from` to `to` at its age): the rules only wait it out, so where it lands is
// known from the cast on. The burst is a blast twice over: on the minions through knock_area (FIREBALL_DAMAGE and a
// knock away from it), and on the props' Box3D bodies as an impulse (blast_props), which rolls back with the rest of
// the physics; walls shield both, by the same ray from the blast's heart. (Box3D's own explosion, world_explode, sees
// through walls: docs/plan.md, Needed from unified.) fireball_target is both what the cast reads and what the view's
// landing ring shows, on the newest local input, so the ring is where the fireball will land.
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// A fireball in flight, a row of the State's `fireballs`.
Fireball :: struct {
	from:    [3]f32, // where it left the Mage's hands
	to:      [3]f32, // where it lands and bursts, on the floor
	cast_at: sim.Game_Time, // when it left
	caster:  sim.Player, // whose it is (the damage's), whether still here or not
}

// A fireball burst at `position` (on the floor).
Event_Fireball_Burst :: struct {
	position: sim.Position,
}

// Where a fireball cast by `hero` on `input` lands: along where the input turns the hero (hero_facing: its aim, else its
// move, else its facing), as far as the aim reaches (Input.reach) up to FIREBALL_RANGE, or FIREBALL_NO_AIM without a
// reach; a wall on the way, met by a ray at FLIGHT_HEIGHT, brings it down FIREBALL_WALL_GAP short of the wall. On the
// floor beneath the hero's feet. Pure: what the cast (cast_fireball) and the view's ring both ask.
fireball_target :: proc(phys: ^physics.World, hero: ^Hero, input: Input) -> [3]f32 {
	dir := hero_facing(input, hero.facing)
	reach := FIREBALL_NO_AIM
	if input.reach > 0 && dmath.dir2_vec(input.aim) != {} do reach = dmath.min(f32(input.reach) * REACH_STEP, FIREBALL_RANGE)
	flight := [3]f32{dir.x, 0, dir.y} * reach
	if hit, walled := physics.world_cast_ray_closest(phys, hero.pos + {0, FLIGHT_HEIGHT, 0}, flight, SIGHT_FILTER);
	   walled {
		reach = dmath.max(reach * hit.fraction - FIREBALL_WALL_GAP, 0)
	}
	return hero.pos + [3]f32{dir.x, 0, dir.y} * reach
}

// The cast's windup ended: a fireball leaves `player`'s hero's hands (chest-high, just clear of its capsule) for
// fireball_target on this tick's input. A full table: the spell fizzles.
cast_fireball :: proc(t: ^Tick, hero: ^Hero, player: sim.Player) {
	fireball, _, spawned := sim.spawn(&t.state.fireballs)
	if !spawned do return
	hands := [3]f32{hero.facing.x * HERO_RADIUS, FLIGHT_HEIGHT, hero.facing.y * HERO_RADIUS}
	fireball^ = {
		from    = hero.pos + hands,
		to      = fireball_target(t.world.phys, hero, sim.input(t, player)),
		cast_at = t.time,
		caster  = player,
	}
}

// After the physics step: every fireball whose flight is over bursts where it lands (burst_fireball) and is gone.
fly_fireballs :: proc(t: ^Tick) {
	fireballs := sim.iterate(&t.state.fireballs)
	for fireball, handle in sim.next(&fireballs) {
		if u32(t.time - fireball.cast_at) < FIREBALL_FLIGHT_TICKS do continue
		burst_fireball(t, fireball)
		sim.despawn(&t.state.fireballs, handle)
	}
}

// A fireball bursts at its landing: every live minion within FIREBALL_RADIUS that no wall shields from the blast's
// heart (chest-high above the landing) takes FIREBALL_DAMAGE, knocked away from it (knock_area), and every prop no
// wall shields is blown away (blast_props). Heroes feel neither: heroes never hurt or shove each other.
@(private = "file")
burst_fireball :: proc(t: ^Tick, fireball: ^Fireball) {
	heart := fireball.to + {0, CHEST_HEIGHT, 0}
	knock_area(t, heart, FIREBALL_RADIUS, FIREBALL_DAMAGE, FIREBALL_KNOCK, fireball.caster, .Fireball)
	blast_props(t, heart)
	sim.emit(t, Event_Fireball_Burst{position = sim.Position(fireball.to)})
}

// The blast on the props, in table order: each prop free of a hold, its centre within FIREBALL_RADIUS +
// FIREBALL_FALLOFF of the blast's `heart` on the floor plan, and no wall between them (the ray knock_area casts), takes
// an impulse of FIREBALL_IMPULSE (fading to none over FIREBALL_FALLOFF past FIREBALL_RADIUS) away from the heart along
// the floor, FIREBALL_LIFT of it upward: a light prop skids and hops, and none is thrown over a wall.
@(private = "file")
blast_props :: proc(t: ^Tick, heart: [3]f32) {
	props := sim.iterate(&t.state.props)
	for prop in sim.next(&props) {
		if prop.held_by != {} do continue
		centre := physics.body_position(t.world.phys, prop.body)
		offset := centre.xz - heart.xz
		distance := dmath.length(offset)
		if distance >= FIREBALL_RADIUS + FIREBALL_FALLOFF do continue
		if _, walled := physics.world_cast_ray_closest(t.world.phys, heart, centre - heart, SIGHT_FILTER); walled {
			continue
		}
		strength := FIREBALL_IMPULSE * dmath.min(1, (FIREBALL_RADIUS + FIREBALL_FALLOFF - distance) / FIREBALL_FALLOFF)
		away := offset / distance if distance > 0 else [2]f32{1, 0}
		impulse := [3]f32{away.x, FIREBALL_LIFT, away.y} * strength
		physics.body_apply_linear_impulse_to_center(t.world.phys, prop.body, impulse)
	}
}
