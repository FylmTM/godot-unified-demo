// The Mage's bolts: rows of the State with no body, each flying straight at BOLT_SPEED from its cast. Every tick, after
// the physics step, a bolt sweeps the segment it flies: against the live minions near it (circles on the floor plan,
// over the grid) and against walls and props (a ray at FLIGHT_HEIGHT: it flies over low cover and resting light props).
// It bursts at the first thing it meets: the minion it struck takes the Mage's damage, every other minion within
// BURST_RADIUS that no wall shields a little and a knock; a prop it met is shoved. A bolt that meets nothing fizzles
// after BOLT_LIFE_S.
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// A bolt in flight, a row of the State's `bolts`.
Bolt :: struct {
	pos:     [3]f32,
	vel:     [3]f32, // metres per second, level
	cast_at: sim.Game_Time, // when it left the Mage's hands
	caster:  sim.Player, // whose it is (the damage's), whether still here or not
}

// A bolt burst at `position`.
Event_Bolt_Burst :: struct {
	position: sim.Position,
}

// A bolt leaves `player`'s hero at FLIGHT_HEIGHT, just clear of its capsule, along its facing.
cast_bolt :: proc(t: ^Tick, hero: ^Hero, player: sim.Player) {
	bolt, _, spawned := sim.spawn(&t.state.bolts)
	if !spawned do return // a full table: the spell fizzles
	dir := [3]f32{hero.facing.x, 0, hero.facing.y}
	bolt^ = {
		pos     = hero.pos + {0, FLIGHT_HEIGHT, 0} + dir * (HERO_RADIUS + BOLT_RADIUS),
		vel     = dir * BOLT_SPEED,
		cast_at = t.time,
		caster  = player,
	}
}

// Every bolt flies its tick's segment and bursts at the first minion, wall or prop on it, or fizzles at BOLT_LIFE_S.
fly_bolts :: proc(t: ^Tick) {
	bolts := sim.iterate(&t.state.bolts)
	for bolt, handle in sim.next(&bolts) {
		if u32(t.time - bolt.cast_at) >= BOLT_LIFE_TICKS {
			sim.despawn(&t.state.bolts, handle)
			continue
		}
		step := bolt.vel * t.dt
		reach: f32 = 1
		hit, struck := physics.world_cast_ray_closest(t.world.phys, bolt.pos, step, SHOT_FILTER)
		if struck do reach = hit.fraction
		victim: sim.Handle(Minion)
		middle := bolt.pos.xz + step.xz / 2 // the segment's minions: within half its length and the sweep of its middle
		walk := minions_within(t, middle, dmath.length(step.xz) / 2 + MINION_RADIUS + BOLT_RADIUS)
		for minion, minion_handle in next_within(&walk) {
			fraction, meets := segment_meets_circle(bolt.pos.xz, step.xz, minion.pos.xz, MINION_RADIUS + BOLT_RADIUS)
			if meets && fraction < reach do victim, reach = minion_handle, fraction
		}
		if victim == {} && !struck {
			bolt.pos += step
			continue
		}
		// the orb's centre where it met it: the minion sweep counts the orb's radius, the ray met the world with its centre
		at := bolt.pos + step * reach
		flight := dmath.normalize(bolt.vel.xz)
		if victim == {} {
			at -= dmath.normalize(bolt.vel) * BOLT_RADIUS
			if hit.category & CAT_PROP != 0 {
				if prop := sim.get(&t.state.props, sim.handle_of_key(Prop, hit.tag)); prop != nil {
					shove_prop(t, prop, flight, CLASS_SPECS[.Mage].prop_knock)
				}
			}
		}
		burst(t, at, flight, bolt.caster, victim)
		sim.despawn(&t.state.bolts, handle)
	}
}

// `caster`'s bolt bursts at `at`: `victim` (if any) takes the Mage's damage along the bolt's `flight` (unit, on the
// floor plan), and the burst is a blast (knock_area): every other live minion within BURST_RADIUS that no wall shields
// takes BURST_DAMAGE, knocked away from the burst at BURST_KNOCK falling off to the rim.
@(private = "file")
burst :: proc(t: ^Tick, at: [3]f32, flight: [2]f32, caster: sim.Player, victim: sim.Handle(Minion)) {
	spec := &CLASS_SPECS[.Mage]
	if victim != {} do damage_minion(t, victim, spec.damage, flight, spec.knock, caster, .Bolt)
	knock_area(t, at, BURST_RADIUS, BURST_DAMAGE, BURST_KNOCK, caster, .Bolt, victim)
	sim.emit(t, Event_Bolt_Burst{position = sim.Position(at)})
}
