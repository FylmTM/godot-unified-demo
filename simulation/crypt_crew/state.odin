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
}

// What a hero is doing, for the view to pose (a one-shot clip at its age). The attacks append theirs (docs/plan.md,
// Milestone 2: the design).
Action :: enum u8 {
	None, // walking or standing: the view picks its gait from the velocity
}

// A player's hero (the State's sim.Players, by member): zeroed for someone new, kept while they are away. A leave
// destroys its body and keeps only its class (presence.odin), so whoever comes back plays what they played.
Hero :: struct {
	body:           physics.Character, // zero while absent
	pos:            [3]f32, // its feet, read back after the physics step (read_back_heroes)
	vel:            [3]f32, // its body's velocity, read back with `pos`
	facing:         [2]f32, // unit (x, z): where it looks
	action_started: sim.Game_Time, // when `action` began (t.time): the view's clip time
	hp:             i16,
	class:          Class, // Any only before its first arrival
	action:         Action,
	warp:           u8, // bumped where the hero is placed rather than moved (an arrival), so its view snaps there
	_pad:           [7]u8,
}
