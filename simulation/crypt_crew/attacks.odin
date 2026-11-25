// The heroes' attacks, the machinery every class shares; each class's blow is its own file (knight, barbarian, mage,
// rogue). Attack is read held: a hero up, with its hands free of a prop and doing nothing else, starts its class's
// attack once its cooldown ran out. The clip starts at once (the action and the game time it began) and the blow
// lands a windup later, after the physics step, reading the facing then; so an attack answers the button at once on
// screen and a misprediction of what it hit hides behind the swing. Every blow hurts through damage_minion; walls
// shield what is behind them from blows, bursts and shots, and bolts and shots fly over low cover (FLIGHT_HEIGHT).
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// `player`'s hero began its class's attack (the view's swing starts with the action; this is for a sound).
Event_Hero_Attacked :: struct {
	player: sim.Player,
	class:  Class,
}

// What a bolt and a shot stop at: walls, low cover and props, met where they stand above FLIGHT_HEIGHT (low cover
// and a resting light prop never do, so they are flown over).
SHOT_FILTER :: physics.Filter {
	category = CAT_HERO,
	mask     = CAT_WALL | CAT_LOW | CAT_PROP,
}

// Each present hero's attack that ran its class's duration ends; then each that holds Attack starts its class's attack
// when it is up, holds no prop, does nothing else and its cooldown ran out (CLASS_SPECS: the cooldown runs from the
// attack's start, so a held Attack repeats every cooldown).
start_attacks :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		if hero.action == .Attack && u32(t.time - hero.action_started) >= CLASS_SPECS[hero.class].duration {
			hero.action = .None
		}
		if .Attack not_in sim.buttons(t, player).down || hero.action != .None || hero.held != {} do continue
		if sim.timer_running(t, hero.attack_ready) do continue
		hero.action, hero.action_started = .Attack, t.time
		sim.timer_start_ticks(t, &hero.attack_ready, CLASS_SPECS[hero.class].cooldown)
		sim.emit(t, Event_Hero_Attacked{player = player, class = hero.class})
	}
}

// After the physics step, on the grid of minions rebuilt for the strikes: each attacking hero's blow lands at its
// class's windup (its class's strike).
resolve_strikes :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		if hero.action != .Attack || u32(t.time - hero.action_started) != CLASS_SPECS[hero.class].windup do continue
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
}

// A melee blow of `spec`: every live minion within `spec.reach` of the hero's centre (its circle's edge) and inside the
// arc either side of the hero's facing (or touching the hero), with no wall between their chests, takes the blow's
// damage and knock, away from the hero; every free prop in the arc, within the height a blow sweeps and with no wall
// between, is shoved likewise. Dot products, no trig; minions in the grid's order (minions_near).
strike_arc :: proc(t: ^Tick, hero: ^Hero, player: sim.Player, spec: ^Class_Spec) {
	walk := minions_near(&t.world.grid, hero.pos.xz, dmath.max(spec.reach, HERO_RADIUS + STRIKE_TOUCH) + MINION_RADIUS)
	for row in sim.grid_box_next(&walk) {
		for index in row {
			minion, handle, _ := sim.item_at(&t.state.minions, int(index))
			if minion.phase == .Dying do continue
			away, inside := in_arc(hero, minion.pos.xz, MINION_RADIUS, spec)
			if !inside || walled_off(t, hero, minion.pos.xz) do continue
			damage_minion(t, handle, spec.damage, away, spec.knock, player, .Blow)
		}
	}
	props := sim.iterate(&t.state.props)
	for prop in sim.next(&props) {
		if prop.held_by != {} do continue
		centre := physics.body_position(t.world.phys, prop.body)
		half := PROP_SPECS[prop.kind].half.y
		if centre.y + half < hero.pos.y || centre.y - half - hero.pos.y > MINION_HEIGHT do continue
		away, inside := in_arc(hero, centre.xz, PROP_SPECS[prop.kind].footprint, spec)
		if inside && !walled_off(t, hero, centre.xz) do shove_prop(t, prop, away, spec.prop_knock)
	}
}

// Whether something of `radius` at `at` is inside a blow's arc: its circle within `spec.reach` of the hero's centre,
// and its centre within the arc's half angle of the facing, or its circle touching the hero's (within STRIKE_TOUCH);
// and the direction away from the hero (the facing, for one on the hero's centre).
@(private = "file")
in_arc :: proc(hero: ^Hero, at: [2]f32, radius: f32, spec: ^Class_Spec) -> (away: [2]f32, inside: bool) {
	offset := at - hero.pos.xz
	distance := dmath.length(offset)
	if distance - radius > spec.reach do return
	away = offset / distance if distance > 0 else hero.facing
	touching := distance <= HERO_RADIUS + radius + STRIKE_TOUCH
	return away, touching || dmath.dot(away, hero.facing) >= spec.arc_cos
}

// Whether a wall stands between the hero's chest and the chest height above `at` (low cover is struck over).
@(private = "file")
walled_off :: proc(t: ^Tick, hero: ^Hero, at: [2]f32) -> bool {
	chest := hero.pos + {0, CHEST_HEIGHT, 0}
	target := [3]f32{at.x, chest.y, at.y}
	_, walled := physics.world_cast_ray_closest(t.world.phys, chest, target - chest, SIGHT_FILTER)
	return walled
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
