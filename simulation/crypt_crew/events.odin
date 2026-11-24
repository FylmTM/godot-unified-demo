package crypt_crew

import "unified:sim"

// Every event the sim emits: the library's joins and leaves, and the game's own.
Event :: union {
	sim.Event_Player_Joined,
	sim.Event_Player_Left,
	Event_Ball_Thrown,
	Event_Paused,
}

// A ball left `player`'s hand at `speed` metres per second.
Event_Ball_Thrown :: struct {
	player: sim.Player,
	speed:  u8,
}
