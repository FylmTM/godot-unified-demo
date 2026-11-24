// Every hero carries: Interact's press grabs the nearest free prop in front (hands_target, which the view also calls
// to highlight it) or drops the one held; Attack's press while holding throws it. A motor joint holds the prop's centre
// in front of the hero at chest height, its force capped by the prop's weight, turned with the hero's facing; the
// carrier slows by the prop's carry_speed. A throw is an action: the hands let go THROW_WINDUP_S into it, at a fixed
// velocity along the facing, so every mass flies alike, and the prop then passes through its thrower until it is clear
// of them (props.odin, age_throws). Every path that lets go (a drop, a throw, a leave, going down, a level change) goes
// through release_hold.
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// `player`'s hero picked up `prop`.
Event_Prop_Grabbed :: struct {
	prop:   sim.Handle(Prop),
	player: sim.Player,
}

// `player`'s hero let go of `prop` without throwing it: Interact, its player left, or it went down.
Event_Prop_Dropped :: struct {
	prop:   sim.Handle(Prop),
	player: sim.Player,
}

// `player`'s hero threw `prop` at `velocity`.
Event_Prop_Thrown :: struct {
	prop:     sim.Handle(Prop),
	player:   sim.Player,
	velocity: [3]f32,
}

// What blocks a hero's reach for a prop: walls (a prop behind one is out of reach, however near).
REACH_FILTER :: physics.Filter {
	category = CAT_HERO,
	mask     = CAT_WALL,
}

// Whether a hero's hands are free to grab: up, not throwing, holding nothing.
can_grab :: proc(hero: ^Hero) -> bool {
	return hero.action != .Down && hero.action != .Throw && hero.held == {}
}

// The prop `hero`, facing `facing`, would grab now (the null handle: none): nothing unless its hands are free
// (can_grab); else the nearest free prop within GRAB_RANGE of its capsule, in a cone in front (or right against it),
// its centre within GRAB_HEIGHT of the feet and no wall between it and the hero's chest; on a tie the first in the
// table. Pure, and what both the press (use_hands) and the view's highlight ask.
hands_target :: proc(
	phys: ^physics.World,
	props: ^sim.Table(Prop, MAX_PROPS),
	hero: ^Hero,
	facing: [2]f32,
) -> (
	target: sim.Handle(Prop),
) {
	if !can_grab(hero) do return
	chest := hero.pos + {0, HOLD_HEIGHT, 0}
	nearest := max(f32)
	walk := sim.iterate(props)
	for prop, handle in sim.next(&walk) {
		if prop.held_by != {} do continue
		centre := physics.body_position(phys, prop.body)
		offset := centre - hero.pos
		if abs(offset.y) > GRAB_HEIGHT do continue
		distance := dmath.length(offset.xz)
		gap := distance - HERO_RADIUS - PROP_SPECS[prop.kind].half.x
		if gap > GRAB_RANGE || gap >= nearest do continue
		if gap > GRAB_ANYWHERE && dmath.dot(offset.xz / distance, facing) < GRAB_CONE_COS do continue
		if _, walled := physics.world_cast_ray_closest(phys, chest, centre - chest, REACH_FILTER); walled do continue
		target, nearest = handle, gap
	}
	return
}

// Per present hero, in slot order: a throw winding up lets go at THROW_WINDUP_S and ends at THROW_S, reading no other
// input meanwhile; a pick-up ends at PICK_UP_S; a hero down reads none. Interact's press drops the prop held (ending a
// pick-up), or grabs hands_target's; Attack's press while holding starts a throw.
use_hands :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		age := u32(t.time - hero.action_started)
		switch hero.action {
		case .Throw:
			if age >= THROW_WINDUP_TICKS && hero.held != {} do throw_prop(t, player)
			if age >= THROW_TICKS do hero.action = .None
			continue
		case .Pick_Up:
			if age >= PICK_UP_TICKS do hero.action = .None
		case .Down:
			continue
		case .None:
		}
		pressed := sim.buttons(t, player).pressed
		if .Interact in pressed {
			if hero.held != {} {
				drop_prop(t, player)
				hero.action = .None
			} else if target := hands_target(t.world.phys, &t.state.props, hero, hero.facing); target != {} {
				grab_prop(t, player, target)
			}
		} else if .Attack in pressed && hero.held != {} {
			hero.action, hero.action_started = .Throw, t.time
		}
	}
}

// Every hero holding a prop holds it where its facing now puts the hold (hold_frame).
update_holds :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero in sim.next(&heroes) {
		if hero.held == {} do continue
		physics.joint_set_local_frame_a(
			t.world.phys,
			hero.hold,
			hold_frame(hero, sim.get(&t.state.props, hero.held).kind),
		)
	}
}

// What a hero's carrying leaves of its speed (1: carrying nothing).
carry_speed :: proc(t: ^Tick, hero: ^Hero) -> f32 {
	if hero.held == {} do return 1
	return PROP_SPECS[sim.get(&t.state.props, hero.held).kind].carry_speed
}

// Where a prop of `kind` is held, in the hero's body frame (its rotation is locked: the world's axes): in front along
// the facing, just clear of the capsule, its centre at HOLD_HEIGHT above the feet, turned with the facing.
hold_frame :: proc(hero: ^Hero, kind: Prop_Kind) -> physics.Transform {
	reach := HERO_RADIUS + HOLD_GAP + PROP_SPECS[kind].half.z
	return {
		{hero.facing.x * reach, HOLD_HEIGHT - HERO_CENTRE_ABOVE_FEET, hero.facing.y * reach},
		dmath.quat_yaw(hero.facing),
	}
}

// `player`'s hero takes the free prop `handle`: a motor joint holds it (hold_frame), the hero and the prop no longer
// touch, the prop is nobody's throw any more, and the hero picks it up (Action.Pick_Up).
grab_prop :: proc(t: ^Tick, player: sim.Player, handle: sim.Handle(Prop)) {
	hero := sim.player_data(t, player)
	prop := sim.get(&t.state.props, handle)
	mass := PROP_SPECS[prop.kind].mass
	joint_def := physics.default_motor_joint_def()
	joint_def.base.collide_connected = false
	joint_def.base.local_frame_a = hold_frame(hero, prop.kind)
	joint_def.linear_hertz = HOLD_HERTZ
	joint_def.linear_damping_ratio = HOLD_DAMPING
	joint_def.angular_hertz = HOLD_HERTZ
	joint_def.angular_damping_ratio = HOLD_DAMPING
	joint_def.max_spring_force = HOLD_LIFT * mass * GRAVITY
	joint_def.max_spring_torque = HOLD_TORQUE_PER_KG * mass
	hero.hold = physics.create_motor_joint(
		t.world.phys,
		physics.link(hero.body.body),
		physics.link(prop.body),
		joint_def,
	)
	hero.held = handle
	prop.held_by = player
	sim.timer_stop(&prop.thrown)
	prop.thrown_by = {}
	physics.stop_ignoring(t.world.phys, &prop.thrower_ignore)
	hero.action, hero.action_started = .Pick_Up, t.time
	sim.emit(t, Event_Prop_Grabbed{prop = handle, player = player})
}

// `player`'s hero lets go of what it holds, if anything: the hold's joint goes and the prop is nobody's. The one way
// a hold ends; returns the prop it held (the null handle: none).
release_hold :: proc(t: ^Tick, player: sim.Player) -> sim.Handle(Prop) {
	hero := sim.player_data(t, player)
	held := hero.held
	if held == {} do return {}
	physics.destroy_joint(t.world.phys, &hero.hold)
	sim.get(&t.state.props, held).held_by = {}
	hero.held = {}
	return held
}

// `player`'s hero drops what it holds, if anything (it falls where it is).
drop_prop :: proc(t: ^Tick, player: sim.Player) {
	if prop := release_hold(t, player); prop != {} do sim.emit(t, Event_Prop_Dropped{prop = prop, player = player})
}

// `player`'s hero throws what it holds: THROW_SPEED along its facing and THROW_LIFT up, set as the prop's velocity;
// the prop is the hero's throw for THROWN_TICKS and ignores the hero's body until it is clear (age_throws).
throw_prop :: proc(t: ^Tick, player: sim.Player) {
	handle := release_hold(t, player) // use_hands throws only while holding
	prop := sim.get(&t.state.props, handle)
	hero := sim.player_data(t, player)
	velocity := [3]f32{hero.facing.x * THROW_SPEED, THROW_LIFT, hero.facing.y * THROW_SPEED}
	prop.thrown_by = player
	sim.timer_start_ticks(t, &prop.thrown, THROWN_TICKS)
	physics.stop_ignoring(t.world.phys, &prop.thrower_ignore) // a throw of a prop still clearing its last thrower
	prop.thrower_ignore = physics.ignore_contacts(t.world.phys, physics.link(hero.body.body), physics.link(prop.body))
	physics.body_set_linear_velocity(t.world.phys, prop.body, velocity)
	sim.emit(t, Event_Prop_Thrown{prop = handle, player = player, velocity = velocity})
}
