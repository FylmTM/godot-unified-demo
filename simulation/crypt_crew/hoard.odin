// The hoard: the floor's gold chest (its `hoard` marker), hauled to the lift by its two handles. A dynamic Box3D body
// made when the party enters the floor (enter_level), weighing HOARD_MASS while a hand holds it.
//
// Interact beside a free handle (haul_target, which the "[E] Haul" prompt also asks) takes it, before any prop: the
// hero's hold (Hero.hold, the joint a prop hangs on) becomes a motor joint from its body to the handle, linear only, so
// the chest turns freely about the handles, lifting the handle to HOARD_HOLD_HEIGHT with a force capped at HOARD_LIFT
// of the hoard's weight. That cap is the whole rule of carrying: over half the weight, one hauler lifts its end and
// drags the other along the floor; under all of it, only two lift it clear. The hauler's speed asks physics which it is
// (haul_speed: the chest's lowest corner off the floor or not), so one hauler is slow (HOARD_DRAG_SPEED) and two are
// quicker (HOARD_CARRY_SPEED), from the same rule. The hold is set where the handle was when taken, on the hauler's
// side, and doesn't turn with its facing: a hauler walks any way and the chest comes along.
//
// A hauler does nothing else (Action.Haul: no attack, no ability, no revive) until it lets go: Interact again, going
// down, leaving, a level change (all through release_hold), or its hold stretched past HOARD_SLIP (the chest caught on
// something, its hauler gone on: hold_hauls). Unheld, the chest weighs HOARD_REST_MASS, so heroes can't shove it to the
// lift: it goes where it is hauled. The first grab on a floor wakes the crypt: the surges come every HAUL_SURGE_S
// from then on (surge_every). Minions are pushed out of it (obstacles_of).
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// A handle of the hoard (Hero.handle; None: a hero holds none): the one at its -X end or its +X end.
Haul_Handle :: enum u8 {
	None,
	Left,
	Right,
}

// The floor's hoard, in the State (zero on a floor without one).
Hoard :: struct {
	body:    physics.Body_Ref,
	shape:   physics.Shape_Ref, // its box: its density says what it weighs (held, or at rest)
	haulers: [2]sim.Player, // who holds each handle, Left then Right ({}: nobody)
	hauled:  bool, // a handle was taken on this floor: the haul's surges are on
	_pad:    [3]u8,
}

// A hoard's place (a `hoard` marker): where it stands and how it is turned (its handles along the marker's X).
Hoard_Def :: struct {
	pos:    [3]f32,
	rot:    [4]f32,
	placed: bool, // the floor has one
	_pad:   [3]u8,
}

// `player`'s hero took the hoard's `handle`.
Event_Hoard_Grabbed :: struct {
	player: sim.Player,
	handle: Haul_Handle,
}

// `player`'s hero let go of the hoard's `handle`: by Interact, going down, leaving, a level change, or its hold
// stretched past HOARD_SLIP (`slipped`).
Event_Hoard_Dropped :: struct {
	player:  sim.Player,
	handle:  Haul_Handle,
	slipped: bool,
}

// The hoard's body at its marker, resting, unheld (enter_level, after the props).
spawn_hoard :: proc(t: ^Tick) {
	def := &floor_of(t).places.hoard
	if !def.placed do return
	hoard := &t.state.hoard
	shape_def := physics.shape_def(CAT_HOARD)
	shape_def.base_material.friction = HOARD_FRICTION
	shape_def.density = physics.box_density(HOARD_REST_MASS, HOARD_HALF)
	shape_def.enable_sensor_events = true // the lift's sensor sees it aboard
	body_def := physics.body_def(.Dynamic, def.pos + {0, HOARD_HALF.y, 0}, def.rot)
	body_def.angular_damping = HOARD_ANGULAR_DAMPING
	hoard.body, hoard.shape = physics.create_box(t.world.phys, body_def, shape_def, HOARD_HALF)
}

// The hoard's body goes (enter_level, after every hold let go of it).
despawn_hoard :: proc(t: ^Tick) {
	physics.destroy_refs(t.world.phys, &t.state.hoard)
	t.state.hoard = {}
}

// Where `handle` of the hoard is in the world now.
handle_point :: proc(phys: ^physics.World, hoard: ^Hoard, handle: Haul_Handle) -> [3]f32 {
	side := f32(1) if handle == .Right else -1
	return physics.body_world_point(phys, hoard.body, {side * HOARD_HANDLE.x, HOARD_HANDLE.y, HOARD_HANDLE.z})
}

// The handle `hero` would take now (None: none): nothing unless the floor has a hoard, the lift still waits for it
// (not yet going down) and the hero's hands are free (can_grab); else the nearest handle nobody holds within GRAB_RANGE
// of its capsule on the floor plan, within GRAB_HEIGHT of its feet, no wall between its chest and the handle. Pure: what
// the press (use_hands) and the "[E] Haul" prompt both ask.
haul_target :: proc(phys: ^physics.World, hoard: ^Hoard, lift: ^Lift, hero: ^Hero) -> (target: Haul_Handle) {
	if hoard.body == {} || lift.phase > .Boarding || !can_grab(hero) do return
	chest := hero.pos + {0, HOLD_HEIGHT, 0}
	nearest := max(f32)
	for handle in Haul_Handle.Left ..= Haul_Handle.Right {
		if hoard.haulers[int(handle) - 1] != {} do continue
		point := handle_point(phys, hoard, handle)
		offset := point - hero.pos
		gap := dmath.length(offset.xz) - HERO_RADIUS
		if abs(offset.y) > GRAB_HEIGHT || gap > GRAB_RANGE || gap >= nearest do continue
		if _, walled := physics.world_cast_ray_closest(phys, chest, point - chest, REACH_FILTER); walled do continue
		target, nearest = handle, gap
	}
	return
}

// `player`'s hero takes the hoard's `handle` (haul_target's): its hold joint pulls the handle up to HOARD_HOLD_HEIGHT
// where it is, within the hold's reach (haul_frame), linear only and capped at HOARD_LIFT of the hoard's weight; the
// hoard weighs HOARD_MASS while held. The floor's first grab starts the haul's surges, the next within HAUL_SURGE_S.
grab_haul :: proc(t: ^Tick, player: sim.Player, handle: Haul_Handle) {
	hero := sim.player_data(t, player)
	hoard := &t.state.hoard
	side := f32(1) if handle == .Right else -1
	joint_def := physics.default_motor_joint_def()
	// the hauler still bumps the chest (a hauler free to walk into it would stand on it, wedged): the hold keeps its
	// handle out of the capsule (HOARD_HOLD_NEAR), so the two never press on each other
	joint_def.base.collide_connected = true
	joint_def.base.local_frame_a = haul_frame(t.world.phys, hoard, hero, handle)
	joint_def.base.local_frame_b = {{side * HOARD_HANDLE.x, HOARD_HANDLE.y, HOARD_HANDLE.z}, {0, 0, 0, 1}}
	joint_def.linear_hertz = HOLD_HERTZ
	joint_def.linear_damping_ratio = HOLD_DAMPING
	joint_def.max_spring_force = HOARD_LIFT * HOARD_MASS * GRAVITY // no angular spring: the chest turns on its handles
	hero.hold = physics.create_motor_joint(
		t.world.phys,
		physics.link(hero.body.body),
		physics.link(hoard.body),
		joint_def,
	)
	if hoard.haulers == {} do physics.shape_set_density(t.world.phys, hoard.shape, physics.box_density(HOARD_MASS, HOARD_HALF))
	hoard.haulers[int(handle) - 1] = player
	hero.handle = handle
	hero.action, hero.action_started = .Haul, t.time
	if !hoard.hauled {
		hoard.hauled = true
		surge := &t.state.surge
		if sim.timer_running(t, surge^) && u32(surge.target - t.time) > HAUL_SURGE_TICKS {
			sim.timer_start_ticks(t, surge, HAUL_SURGE_TICKS)
		}
	}
	sim.emit(t, Event_Hoard_Grabbed{player = player, handle = handle})
}

// `player`'s hero lets go of its handle, if it holds one (`slipped`: its hold stretched too far): the joint goes, the
// handle is free, the hero stands free (Action.None), and the hoard, unheld by anyone, weighs HOARD_REST_MASS again.
release_haul :: proc(t: ^Tick, player: sim.Player, slipped: bool) {
	hero := sim.player_data(t, player)
	handle := hero.handle
	if handle == .None do return
	hoard := &t.state.hoard
	physics.destroy_joint(t.world.phys, &hero.hold)
	hoard.haulers[int(handle) - 1] = {}
	if hoard.haulers == {} {
		physics.shape_set_density(t.world.phys, hoard.shape, physics.box_density(HOARD_REST_MASS, HOARD_HALF))
	}
	hero.handle = .None
	if hero.action == .Haul do hero.action, hero.action_started = .None, t.time
	sim.emit(t, Event_Hoard_Dropped{player = player, handle = handle, slipped = slipped})
}

// Where `hero`'s hold has its `handle`, in its body's frame (its rotation is locked: the world's axes): HOARD_HOLD_HEIGHT
// above its feet, and on the floor plan where the handle is, kept between HOARD_HOLD_NEAR and HOARD_HOLD_FAR off its
// capsule. So a hold lifts, and pulls only a handle that strays out of its reach: set before every step (update_holds).
haul_frame :: proc(phys: ^physics.World, hoard: ^Hoard, hero: ^Hero, handle: Haul_Handle) -> physics.Transform {
	offset := handle_point(phys, hoard, handle).xz - hero.pos.xz
	apart := dmath.length(offset)
	toward := offset / apart if apart > 0 else hero.facing
	reach := dmath.clamp(apart, HERO_RADIUS + HOARD_HOLD_NEAR, HERO_RADIUS + HOARD_HOLD_FAR)
	return {{toward.x * reach, HOARD_HOLD_HEIGHT - HERO_CENTRE_ABOVE_FEET, toward.y * reach}, {0, 0, 0, 1}}
}

// After the physics step: each hold on the hoard stretched past HOARD_SLIP (from where the hold would have the handle
// to where the handle is) lets go, Left first.
hold_hauls :: proc(t: ^Tick) {
	hoard := &t.state.hoard
	for player, i in hoard.haulers {
		if player == {} do continue
		hero := sim.player_data(t, player)
		held_at :=
			physics.body_position(t.world.phys, hero.body.body) +
			physics.joint_local_frame_a(t.world.phys, hero.hold).p
		if dmath.length(handle_point(t.world.phys, hoard, Haul_Handle(i + 1)) - held_at) > HOARD_SLIP {
			release_haul(t, player, slipped = true)
		}
	}
}

// What a hauler's speed is, as a fraction of its class's: HOARD_CARRY_SPEED while the hoard is carried clear (after
// the last step it touched nothing but heroes: two holds lift it), else HOARD_DRAG_SPEED (an end on the floor);
// Strong_Back takes off some of the slowdown (back_speed).
haul_speed :: proc(t: ^Tick, hero: ^Hero) -> f32 {
	physics.body_contact_data(t.world.phys, t.state.hoard.body, &t.world.contacts_of)
	carried := true
	for &contact in t.world.contacts_of {
		other := contact.b if contact.a.body == physics.link(t.state.hoard.body) else contact.a
		carried &&= other.category & CAT_HERO != 0
	}
	return back_speed(hero, HOARD_CARRY_SPEED if carried else HOARD_DRAG_SPEED)
}

// How long until the next surge, as raise_surges restarts its clock: HAUL_SURGE_TICKS once the haul has begun.
surge_every :: proc(t: ^Tick) -> u32 {
	return HAUL_SURGE_TICKS if t.state.hoard.hauled else SURGE_EVERY_TICKS
}
