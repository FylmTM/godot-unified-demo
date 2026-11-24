// The state block: everything tick reads across ticks, one pointer-free, padding-free struct (checked by sim.create)
// that a snapshot copies and the checksum hashes. Kept anywhere else (the World, a package variable), it would desync
// after a rollback (unified/docs/gameplay.md).
package crypt_crew

import "unified:physics"
import "unified:sim"

// The whole simulation state.
State :: struct {
	clock:   sim.Clock, // game time and the co-op pause (pause.odin): the harness advances it unless paused
	level:   sim.Active_Level(Level_Id), // the floor the party is on (world.odin)
	players: sim.Players(Hero, Profile, Input, PLAYERS),
	props:   sim.Table(Prop, MAX_PROPS), // made from the floor's prop markers, in marker order (props.odin)
	minions: sim.Table(Minion, MAX_MINIONS), // the skeletons, rows with no body (minions.odin)
	surge:   sim.Timer, // the next surge rises when it runs out (director.odin)
	surges:  u32, // the surges risen on this floor: what a surge's rolls are named by
	kills:   u32, // minions killed this session
	// The minions the standard benchmark holds alive (bench_prepare; 0: the director's surges, as in play).
	held:    u32,
	_pad:    u32,
}

// What a hero is doing, for the view to pose (a one-shot clip at its age). The attacks append theirs (docs/plan.md,
// Milestone 2: the design).
Action :: enum u8 {
	None, // walking or standing: the view picks its gait from the velocity
	Pick_Up, // a grab, for PICK_UP_S
	Throw, // a throw, for THROW_S: the prop leaves the hands THROW_WINDUP_S into it
	Down, // at 0 HP, limp, until it rises (health.odin)
}

// A player's hero (the State's sim.Players, by member): zeroed for someone new, kept while they are away. A leave
// destroys its body and keeps only its class and its warp epoch (presence.odin), so whoever comes back plays what they
// played, and their view snaps to where they arrive.
Hero :: struct {
	body:           physics.Character, // zero while absent
	pos:            [3]f32, // its feet, read back after the physics step (read_back_heroes)
	vel:            [3]f32, // its body's velocity, read back with `pos`
	facing:         [2]f32, // unit (x, z): where it looks
	hold:           physics.Motor_Joint_Ref, // the joint holding `held` in front of it (hands.odin)
	held:           sim.Handle(Prop), // the prop it carries (the null handle: none)
	respawn:        sim.Timer, // while down: it rises beside the party when this runs out
	grace:          sim.Timer, // after rising: no damage while it runs
	action_started: sim.Game_Time, // when `action` began (t.time): the view's clip time
	hp:             i16,
	class:          Class, // Any only before its first arrival
	action:         Action,
	// The hero's own warp epoch, which outlives its bodies: a body's (physics.body_warp) starts at 0 when it is made
	// again, so this one takes the old body's count and one more for each new body. The view's epoch is the two added
	// (hero_warp): a teleport of the body bumps the body's, a new body this one.
	warp:           u8,
	_pad:           [7]u8,
}
