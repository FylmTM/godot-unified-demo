// The Barbarian: its attack a slow, wide cleave with a big knock (CLASS_SPECS[.Barbarian], strike_arc), its prop
// throws BARBARIAN_THROW faster (hands.odin, throw_prop), and its ability the heave. Ability's press, its cooldown run,
// grabs the nearest elite or downed ally in the grab cone (heave_target: a prop's cone and reach, and never an ally
// who is up, so no hero is thrown against their will). An elite goes limp (physics.character_set_limp: no drive, no
// pogo) and hangs on the hold's joint as a prop does, weighing HEAVE_MASS while it hangs; a downed ally's ragdoll hangs
// on the hold by its chest bone (it weighs RAGDOLL_MASS, which is HEAVE_MASS), its limbs swinging under it. The
// Barbarian heaves it (Action.Heave), slowed to HEAVE_SPEED. Attack's press throws it (Action.Hurl, timed as a prop's
// throw): it leaves at THROW_SPEED until it lands (land_heaves), an elite with its own weight back, limp and passing
// through every hero (pass_heroes: a 300 kg skeleton at 11 m/s would bowl its thrower or an ally over), a ragdoll set
// moving whole (physics.ragdoll_set_velocity; it meets no hero anyway). Its landing knocks every skeleton round it
// (knock_area, breaking a Warrior's guard as a thrown prop does); a thrown elite takes the landing's blow too and
// staggers. Held HEAVE_MAX_S unthrown, the body is let down where it hangs. Either way an elite then stands on its own
// again (its drive and pogo back) and chases on, and a downed ally's ragdoll lies where it came down, still down (a
// throw toward revivers is a rescue). The cooldown runs from then (the landing or the letting down), so the thrower
// can't take the same body up again before it is back on its feet.
//
// A held elite's rules stand still (Elite_Phase.Held, Thrown: no steering, no attack); a held ally is down, which
// reads no input already, and nobody tends it until it is let down (revive_target). Whatever ends a heave early lets
// go first, through release_heave: the Barbarian going down or leaving (release_hold), the held body dying, leaving or
// being revived (end_hero_heave), a level change.
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// Where a downed hero a Barbarian heaves is (Hero.heave; an elite's is its phase, Elite_Phase.Held and Thrown): limp in
// its hands, then flying from the throw until it lands.
Heave_Phase :: enum u8 {
	None,
	Held, // limp on its carrier's hold (Hero.heaved_by), weighing HEAVE_MASS
	Thrown, // limp and flying at its own weight, until it lands (land_heaves)
}

// What a Barbarian holds up (Hero.heaved): an elite, or a downed ally; zero: nothing.
Heaved :: struct {
	elite: sim.Handle(Elite),
	hero:  sim.Player,
}

// `player`'s hero heaved up `elite` or the downed `hero` (the other zero).
Event_Heaved :: struct {
	player: sim.Player,
	elite:  sim.Handle(Elite),
	hero:   sim.Player,
}

// A body `player` threw landed at `position` (its feet): the landing's blast.
Event_Heave_Landed :: struct {
	player:   sim.Player,
	position: sim.Position,
}

// What a thrown body lands on: the floor, walls, low cover, props, mechanisms, the hoard and the lift's deck (never
// another body: it rolls off a hero's head).
LAND_FILTER :: physics.Filter {
	category = CAT_HERO,
	mask     = CAT_FLOOR | CAT_WALL | CAT_LOW | CAT_PROP | CAT_PIECE | CAT_HOARD | CAT_LIFT,
}

// The Barbarian's blow lands: its axe's cleave.
barbarian_strike :: proc(t: ^Tick, hero: ^Hero, player: sim.Player) {
	strike_arc(t, hero, player, &CLASS_SPECS[.Barbarian])
}

// The Barbarian's ability: Attack pressed while heaving throws (Action.Hurl); Ability pressed while free
// (can_start_ability), its cooldown run, heaves heave_target's body, if any (a press with nothing in reach spends
// nothing).
barbarian_ability :: proc(t: ^Tick, hero: ^Hero, player: sim.Player, buttons: sim.Button_State(Buttons)) {
	if hero.action == .Heave {
		if .Attack in buttons.pressed do hero.action, hero.action_started = .Hurl, t.time
		return
	}
	if .Ability not_in buttons.pressed || !can_start_ability(hero) || sim.timer_running(t, hero.ability_ready) do return
	if target := heave_target(t, hero, player); target != {} do heave(t, hero, player, target)
}

// The body `player`'s hero would heave now (zero: none): the nearest live elite, awake or asleep but neither rising nor
// heaved already, or the nearest ally down and not heaved (its ragdoll, where its pelvis lies), within
// GRAB_RANGE of the hero's capsule, in its grab cone (GRAB_CONE_COS; or right against it, GRAB_ANYWHERE), within
// GRAB_HEIGHT of its feet and no wall between their chests, as hands_target picks a prop; on a tie the elites first,
// in table order, then the heroes in slot order.
heave_target :: proc(t: ^Tick, hero: ^Hero, player: sim.Player) -> (target: Heaved) {
	nearest := max(f32)
	elites := sim.iterate(&t.state.elites)
	for elite, handle in sim.next(&elites) {
		if elite.phase == .Rise || elite.phase == .Held || elite.phase == .Thrown || elite.phase == .Dying do continue
		if gap, ok := in_grab(t, hero, elite.pos, ELITE_RADIUS); ok && gap < nearest do target, nearest = {
				elite = handle,
			}, gap
	}
	heroes := sim.iterate_present(t)
	for other, other_player in sim.next(&heroes) {
		if other_player == player || other.action != .Down || other.heave != .None do continue
		if gap, ok := in_grab(t, hero, other.pos, HERO_RADIUS); ok && gap < nearest do target, nearest = {
				hero = other_player,
			}, gap
	}
	return
}

// Whether a body of `radius` standing at `feet` is in `hero`'s grab, and its gap to the hero's capsule.
@(private = "file")
in_grab :: proc(t: ^Tick, hero: ^Hero, feet: [3]f32, radius: f32) -> (gap: f32, ok: bool) {
	offset := feet - hero.pos
	if abs(offset.y) > GRAB_HEIGHT do return
	distance := dmath.length(offset.xz)
	gap = distance - HERO_RADIUS - radius
	if gap > GRAB_RANGE do return
	if gap > GRAB_ANYWHERE && dmath.dot(offset.xz / distance, hero.facing) < GRAB_CONE_COS do return
	chest := hero.pos + {0, CHEST_HEIGHT, 0}
	_, walled := physics.world_cast_ray_closest(t.world.phys, chest, feet + {0, CHEST_HEIGHT, 0} - chest, REACH_FILTER)
	return gap, !walled
}

// `player`'s hero heaves up `target` with a hold (create_hold, at heave_frame, capped by HEAVE_MASS). An elite's body
// goes limp, weighs HEAVE_MASS and feels no gravity (the hold bears it: its spring's capped force all goes to carrying
// it round with the hero, which a 900 N weight would otherwise drag to the floor on a quick turn), and the elite stops
// what it was doing (a sleeper wakes first: rouse_elite makes its dormant character a body a hold can carry). A downed
// ally is Held: the hold takes its ragdoll's chest bone, woken, and the rest of the ragdoll hangs from it (its bones
// keep their gravity: the hold's cap, HOLD_LIFT times the body's weight, carries it round a turn). The hero heaves
// (Action.Heave).
@(private = "file")
heave :: proc(t: ^Tick, hero: ^Hero, player: sim.Player, target: Heaved) {
	phys := t.world.phys
	held_body: physics.Body_Ref
	if elite := sim.get(&t.state.elites, target.elite); elite != nil {
		if elite.phase == .Idle do rouse_elite(phys, elite, t.time)
		elite.phase, elite.since, elite.target, elite.heaved_by = .Held, t.time, {}, player
		physics.character_set_limp(phys, &elite.body, true)
		mass := physics.body_mass_data(phys, elite.body.body)
		mass.mass = HEAVE_MASS // a character's rotation is locked: its inertia is left as it is
		physics.body_set_mass_data(phys, elite.body.body, mass)
		physics.body_set_gravity_scale(phys, elite.body.body, 0)
		held_body = elite.body.body
	} else {
		held := sim.player_data(t, target.hero)
		held.heave, held.heave_since, held.heaved_by = .Held, t.time, player
		held.still = 0
		held_body = held.ragdoll.bones[.Chest]
		physics.body_set_awake(phys, held_body, true) // a ragdoll asleep on the floor wakes, its island with it
	}
	hero.hold = create_hold(t, hero, held_body, heave_frame(hero), HEAVE_MASS)
	hero.heaved = target
	start_ability(t, hero, player, .Heave, 0) // its cooldown starts as it ends (release_heave, land_heaves)
	sim.emit(t, Event_Heaved{player = player, elite = target.elite, hero = target.hero})
}

// Where a heaved body hangs, in the hero's body frame: in front along the facing, just clear of the capsule (both
// capsules have the same radius), its centre (an elite's capsule's, a ragdoll's chest bone's) at HEAVE_HOLD_HEIGHT
// above the feet.
heave_frame :: proc(hero: ^Hero) -> physics.Transform {
	#assert(ELITE_RADIUS == HERO_RADIUS)
	reach := 2 * HERO_RADIUS + HOLD_GAP
	return {
		{hero.facing.x * reach, HEAVE_HOLD_HEIGHT - HERO_CENTRE_ABOVE_FEET, hero.facing.y * reach},
		dmath.quat_yaw(hero.facing),
	}
}

// `player`'s heave under way, before any ability starts (use_abilities): held HEAVE_MAX_S, its body is let down; a
// throw lets go THROW_WINDUP_S into it and ends at THROW_S.
heave_on :: proc(t: ^Tick, hero: ^Hero, player: sim.Player) {
	age := u32(t.time - hero.action_started)
	#partial switch hero.action {
	case .Heave:
		if age >= HEAVE_MAX_TICKS do release_heave(t, player, thrown = false)
	case .Hurl:
		if age == THROW_WINDUP_TICKS do release_heave(t, player, thrown = true)
		if age >= THROW_TICKS do hero.action, hero.action_started = .None, t.time
	}
}

// `player`'s hero lets go of the body it heaves, if any: the hold's joint goes, and an elite has its own weight again
// (its mass, and its gravity: every character's def keeps CHARACTER_DEFAULT's).
// Thrown, it flies at THROW_SPEED along the hero's facing and THROW_LIFT up (an elite limp, a ragdoll every bone at
// that velocity) until it lands (land_heaves); else it is let down where it hangs (let_down), and the heave's cooldown
// starts (a throw's starts as it lands). A hero still heaving stands free (a throw runs its course). The one way a
// heave's hold ends.
release_heave :: proc(t: ^Tick, player: sim.Player, thrown: bool) {
	hero := sim.player_data(t, player)
	target := hero.heaved
	if target == {} do return
	phys := t.world.phys
	physics.destroy_joint(phys, &hero.hold)
	hero.heaved = {}
	if hero.action == .Heave do hero.action, hero.action_started = .None, t.time
	elite := sim.get(&t.state.elites, target.elite)
	if elite != nil {
		physics.body_apply_mass_from_shapes(phys, elite.body.body)
		physics.body_set_gravity_scale(phys, elite.body.body, physics.CHARACTER_DEFAULT.gravity_scale)
	}
	if !thrown {
		sim.timer_start_ticks(t, &hero.ability_ready, hands_cooldown(hero, HEAVE_COOLDOWN_TICKS))
		let_down(t, target)
		return
	}
	// The cooldown runs from the landing (land_heaves); until then, as long as the longest flight and the cooldown.
	sim.timer_start_ticks(t, &hero.ability_ready, HEAVE_FLIGHT_MAX_TICKS + hands_cooldown(hero, HEAVE_COOLDOWN_TICKS))
	velocity := [3]f32{hero.facing.x * THROW_SPEED, THROW_LIFT, hero.facing.y * THROW_SPEED}
	if elite != nil {
		pass_heroes(t, elite.body.body, true)
		physics.body_set_linear_velocity(phys, elite.body.body, velocity)
		elite.phase, elite.since = .Thrown, t.time
		return
	}
	held := sim.player_data(t, target.hero)
	physics.ragdoll_set_velocity(phys, &held.ragdoll, velocity)
	held.heave, held.heave_since = .Thrown, t.time
}

// A heaved body, let go of (let down or landed), is nobody's heave. An elite stands on its own again: its drive and
// pogo come back (it settles onto the floor through the pogo), heroes meet it again, and it chases (one heaved asleep
// woke as it was grabbed). A downed ally's ragdoll lies where it is, still down.
@(private = "file")
let_down :: proc(t: ^Tick, target: Heaved) {
	if elite := sim.get(&t.state.elites, target.elite); elite != nil {
		physics.character_set_limp(t.world.phys, &elite.body, false)
		pass_heroes(t, elite.body.body, false)
		elite.heaved_by = {}
		elite.phase, elite.since = .Chase, t.time
		return
	}
	held := sim.player_data(t, target.hero)
	held.heave, held.heaved_by = .None, {}
}

// `player`'s hero, down, stops being heaved, if it is: let go of by its carrier, or, thrown, let down where it flies.
// Before it rises (revive_hero) or its body goes (a leave).
end_hero_heave :: proc(t: ^Tick, player: sim.Player) {
	hero := sim.player_data(t, player)
	switch hero.heave {
	case .Held:
		release_heave(t, hero.heaved_by, thrown = false)
	case .Thrown:
		let_down(t, {hero = player})
	case .None:
	}
}

// Whether a heaved elite's capsule (its one shape) passes through every hero (`through`) or meets them again: its
// filter's mask leaves CAT_HERO out while it flies from a throw, so neither its thrower nor anyone in its path is
// struck (a downed hero included). It still meets the walls, the props and the elites. (A ragdoll never meets a hero.)
@(private = "file")
pass_heroes :: proc(t: ^Tick, body: physics.Body_Ref, through: bool) {
	clear(&t.world.shapes)
	physics.body_shapes(t.world.phys, body, &t.world.shapes)
	for shape in t.world.shapes {
		filter := physics.shape_filter(t.world.phys, shape)
		filter.mask = filter.mask &~ CAT_HERO if through else filter.mask | CAT_HERO
		physics.shape_set_filter(t.world.phys, shape, filter)
	}
}

// After the physics step: each thrown body that has landed (heave_landed, ragdoll_landed) is let down, its thrower's
// cooldown starts (thrower_lands), and its landing is a blast at its feet, its thrower's (land_blast). A thrown elite takes the
// landing's blow itself as well, from no side (no shield takes it), and staggers.
land_heaves :: proc(t: ^Tick) {
	elites := sim.iterate(&t.state.elites)
	for elite, handle in sim.next(&elites) {
		if elite.phase != .Thrown || !heave_landed(t, &elite.body, ELITE_HALF_HEIGHT, elite.since) do continue
		thrower := elite.heaved_by
		let_down(t, {elite = handle})
		thrower_lands(t, thrower)
		land_blast(t, elite.pos, thrower, handle)
		damage_elite(t, handle, HEAVE_LAND_DAMAGE, {}, 0, thrower, .Heave, elite.pos.xz)
		if elite.phase != .Dying do sim.timer_start_ticks(t, &elite.stagger, ELITE_STAGGER_TICKS)
	}
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		if hero.heave != .Thrown || !ragdoll_landed(t, hero) do continue
		thrower := hero.heaved_by
		let_down(t, {hero = player})
		thrower_lands(t, thrower)
		land_blast(t, hero.pos, thrower, {})
	}
}

// What `thrower` threw has landed: its heave's cooldown starts now, if it is still here.
@(private = "file")
thrower_lands :: proc(t: ^Tick, thrower: sim.Player) {
	if sim.player_present(t, thrower) {
		hero := sim.player_data(t, thrower)
		sim.timer_start_ticks(t, &hero.ability_ready, hands_cooldown(hero, HEAVE_COOLDOWN_TICKS))
	}
}

// Whether a thrown elite (a capsule of `half_height`, thrown at `since`) has landed: falling, with the floor, a wall's
// top, low cover or a prop within HEAVE_LAND_GAP under its capsule; or HEAVE_FLIGHT_MAX_S after the throw, wherever it
// is.
@(private = "file")
heave_landed :: proc(t: ^Tick, body: ^physics.Character, half_height: f32, since: sim.Game_Time) -> bool {
	if u32(t.time - since) >= HEAVE_FLIGHT_MAX_TICKS do return true
	if physics.body_linear_velocity(t.world.phys, body.body).y > 0 do return false
	#assert(ELITE_RADIUS == HERO_RADIUS)
	foot := physics.body_position(t.world.phys, body.body) - {0, half_height, 0} // its lower sphere's centre
	_, ground := physics.world_cast_ray_closest(t.world.phys, foot, {0, -HERO_RADIUS - HEAVE_LAND_GAP, 0}, LAND_FILTER)
	return ground
}

// Whether a thrown downed hero's ragdoll has landed: its pelvis (the hero's `pos` and `vel`) falling, with what a thrown
// body lands on within RAGDOLL_LAND_REACH under it; or HEAVE_FLIGHT_MAX_S after the throw, wherever it is.
@(private = "file")
ragdoll_landed :: proc(t: ^Tick, hero: ^Hero) -> bool {
	if u32(t.time - hero.heave_since) >= HEAVE_FLIGHT_MAX_TICKS do return true
	if hero.vel.y > 0 do return false
	_, ground := physics.world_cast_ray_closest(t.world.phys, hero.pos, {0, -RAGDOLL_LAND_REACH, 0}, LAND_FILTER)
	return ground
}

// A landing's blast at `feet`, `thrower`'s, sparing the thrown elite `skip` (its own blow is land_heaves'): every
// skeleton within HEAVE_LAND_RADIUS of its heart that no wall shields takes HEAVE_LAND_DAMAGE and a knock away from it
// (knock_area), a Warrior's guard broken first, as a thrown prop breaks it.
@(private = "file")
land_blast :: proc(t: ^Tick, feet: [3]f32, thrower: sim.Player, skip: sim.Handle(Elite)) {
	heart := feet + {0, CHEST_HEIGHT, 0}
	knock_area(
		t,
		heart,
		HEAVE_LAND_RADIUS,
		HEAVE_LAND_DAMAGE,
		HEAVE_LAND_KNOCK,
		thrower,
		.Heave,
		skip_elite = skip,
		breaks_guard = true,
	)
	sim.emit(t, Event_Heave_Landed{player = thrower, position = sim.Position(feet)})
}
