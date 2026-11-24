// The heroes' attacks, the machinery every class shares; each class's blow is its own file (knight, barbarian, mage,
// rogue). Attack is read held: a hero up, with its hands free of a prop and doing nothing else, starts its class's
// attack once its cooldown ran out. The clip starts at once (the action and the game time it began) and the blow
// lands a windup later, after the physics step, reading the facing then; so an attack answers the button at once on
// screen and a misprediction of what it hit hides behind the swing. Every blow hurts through damage_minion.
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// `player`'s hero began its class's attack (the view's swing starts with the action; this is for a sound).
Event_Hero_Attacked :: struct {
	player: sim.Player,
	class:  Class,
}

// Each present hero that holds Attack starts its class's attack when it is up, holds no prop, does nothing else and its
// cooldown ran out (CLASS_SPECS: the cooldown runs from the attack's start).
start_attacks :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		if .Attack not_in sim.buttons(t, player).down || hero.action != .None || hero.held != {} do continue
		if sim.timer_running(t, hero.attack_ready) do continue
		hero.action, hero.action_started = .Attack, t.time
		sim.timer_start_ticks(t, &hero.attack_ready, CLASS_SPECS[hero.class].cooldown)
		sim.emit(t, Event_Hero_Attacked{player = player, class = hero.class})
	}
}

// After the physics step: each attacking hero's blow lands at its class's windup (its class's strike, on the grid of
// minions rebuilt here), and its attack ends at the class's duration.
resolve_strikes :: proc(t: ^Tick) {
	build_grid(t)
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		if hero.action != .Attack do continue
		spec := &CLASS_SPECS[hero.class]
		age := u32(t.time - hero.action_started)
		if age == spec.windup {
			switch hero.class {
			case .Knight:
				knight_strike(t, hero, player)
			case .Barbarian:
				barbarian_strike(t, hero, player)
			case .Mage:
				mage_strike(t, hero, player)
			case .Rogue:
				rogue_strike(t, hero, player)
			case .Any:
			}
		}
		if age >= spec.duration do hero.action = .None
	}
}

// A melee blow of `spec`: every live minion within `spec.reach` of the hero's centre (its circle's edge) and inside the
// arc either side of the hero's facing (or right against the hero), with no wall between their chests, takes the
// blow's damage and knock, away from the hero; every free prop in the arc is shoved likewise. Dot products, no trig;
// minions in the grid's order (by cell, then index).
strike_arc :: proc(t: ^Tick, hero: ^Hero, player: sim.Player, spec: ^Class_Spec) {
	chest := hero.pos + {0, CHEST_HEIGHT, 0}
	for row in sim.grid_near(&t.world.grid, hero.pos.xz) {
		for index in row {
			minion, handle, _ := sim.item_at(&t.state.minions, int(index))
			if minion.phase == .Dying do continue
			away, in_arc := in_arc(hero, minion.pos.xz, MINION_RADIUS, spec)
			if !in_arc do continue
			target := minion.pos + {0, CHEST_HEIGHT, 0}
			if _, walled := physics.world_cast_ray_closest(t.world.phys, chest, target - chest, SIGHT_FILTER); walled {
				continue
			}
			damage_minion(t, handle, spec.damage, away, spec.knock, player, .Blow)
		}
	}
	props := sim.iterate(&t.state.props)
	for prop in sim.next(&props) {
		if prop.held_by != {} do continue
		centre := physics.body_position(t.world.phys, prop.body)
		if away, in_arc := in_arc(hero, centre.xz, PROP_SPECS[prop.kind].footprint, spec); in_arc {
			shove_prop(t, prop, away, spec.prop_knock)
		}
	}
}

// Whether something of `radius` at `at` is inside a blow's arc: its circle within `spec.reach` of the hero's centre,
// and its centre within the arc's half angle of the facing (or within STRIKE_BACK, against the hero); and the
// direction away from the hero (the facing, for one on the hero's centre).
@(private = "file")
in_arc :: proc(hero: ^Hero, at: [2]f32, radius: f32, spec: ^Class_Spec) -> (away: [2]f32, inside: bool) {
	offset := at - hero.pos.xz
	distance := dmath.length(offset)
	if distance - radius > spec.reach do return
	away = offset / distance if distance > 0 else hero.facing
	return away, distance <= STRIKE_BACK || dmath.dot(away, hero.facing) >= spec.arc_cos
}

// A prop shoved along `dir` (unit, x and z): `speed` metres per second added to its velocity, whatever its mass.
shove_prop :: proc(t: ^Tick, prop: ^Prop, dir: [2]f32, speed: f32) {
	impulse := [3]f32{dir.x, 0, dir.y} * (speed * PROP_SPECS[prop.kind].mass)
	physics.body_apply_linear_impulse_to_center(t.world.phys, prop.body, impulse)
}

// Where along a segment from `origin` by `step` (on the floor plan) it first meets a circle of `radius` at `centre`:
// the fraction of the step (0 when the origin is inside it); false when it misses within the step.
segment_meets_circle :: proc(origin, step, centre: [2]f32, radius: f32) -> (fraction: f32, meets: bool) {
	from := origin - centre
	inside := dmath.dot(from, from) - radius * radius
	if inside <= 0 do return 0, true
	a := dmath.dot(step, step)
	if a <= 0 do return 0, false
	b := 2 * dmath.dot(from, step)
	discriminant := b * b - 4 * a * inside
	if discriminant < 0 do return 0, false
	fraction = (-b - dmath.sqrt(discriminant)) / (2 * a)
	return fraction, fraction >= 0 && fraction <= 1
}
