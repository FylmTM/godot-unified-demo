// The Mage's bolts: rows of the State with no body, each flying straight at BOLT_SPEED from its cast. Every tick, after
// the physics step, a bolt sweeps the segment it flies: against the live minions near it (circles on the floor plan,
// over the grid) and against walls and props (a ray: it flies over low cover). It bursts at the first thing it meets:
// the minion it struck takes the Mage's damage, every other minion within BURST_RADIUS a little and a knock, a prop
// is shoved. A bolt that meets nothing fizzles after BOLT_LIFE_S.
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

// A bolt leaves `player`'s hero's chest, just clear of its capsule, along its facing.
cast_bolt :: proc(t: ^Tick, hero: ^Hero, player: sim.Player) {
	bolt, _, spawned := sim.spawn(&t.state.bolts)
	if !spawned do return // a full table: the spell fizzles
	dir := [3]f32{hero.facing.x, 0, hero.facing.y}
	bolt^ = {
		pos     = hero.pos + {0, CHEST_HEIGHT, 0} + dir * (HERO_RADIUS + BOLT_RADIUS),
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
		for row in sim.grid_near(&t.world.grid, bolt.pos.xz) {
			for index in row {
				minion, minion_handle, _ := sim.item_at(&t.state.minions, int(index))
				if minion.phase == .Dying do continue
				fraction, meets := segment_meets_circle(
					bolt.pos.xz,
					step.xz,
					minion.pos.xz,
					MINION_RADIUS + BOLT_RADIUS,
				)
				if meets && fraction < reach do victim, reach = minion_handle, fraction
			}
		}
		if victim == {} && !struck {
			bolt.pos += step
			continue
		}
		at := bolt.pos + step * reach - dmath.normalize(bolt.vel) * BOLT_RADIUS // on its side of what it met
		if victim == {} && hit.category & CAT_PROP != 0 {
			if prop := sim.get(&t.state.props, sim.handle_of_key(Prop, hit.tag)); prop != nil {
				shove_prop(t, prop, dmath.normalize(bolt.vel.xz), CLASS_SPECS[.Mage].prop_knock)
			}
		}
		burst(t, bolt, at, victim)
		sim.despawn(&t.state.bolts, handle)
	}
}

// A bolt bursts at `at`: `victim` (if any) takes the Mage's damage along the bolt's flight, every other live minion
// within BURST_RADIUS that no wall shields takes BURST_DAMAGE, knocked away from the burst.
@(private = "file")
burst :: proc(t: ^Tick, bolt: ^Bolt, at: [3]f32, victim: sim.Handle(Minion)) {
	spec := &CLASS_SPECS[.Mage]
	if victim != {} do damage_minion(t, victim, spec.damage, dmath.normalize(bolt.vel.xz), spec.knock, bolt.caster, .Bolt)
	for row in sim.grid_near(&t.world.grid, at.xz) {
		for index in row {
			minion, handle, _ := sim.item_at(&t.state.minions, int(index))
			if handle == victim || minion.phase == .Dying do continue
			offset := minion.pos.xz - at.xz
			if dmath.length_sq(offset) > BURST_RADIUS * BURST_RADIUS do continue
			target := minion.pos + {0, CHEST_HEIGHT, 0}
			if _, walled := physics.world_cast_ray_closest(t.world.phys, at, target - at, SIGHT_FILTER); walled do continue
			away := dmath.normalize(offset)
			damage_minion(t, handle, BURST_DAMAGE, away, BURST_KNOCK, bolt.caster, .Bolt)
		}
	}
	sim.emit(t, Event_Bolt_Burst{position = sim.Position(at)})
}
