// What the sim tells the views happened, as opposed to what is (the state, which fill_frame reads). Each event is
// declared beside the system that emits it.
package crypt_crew

import "unified:sim"

// Every event the sim emits: the library's joins and leaves, and the game's own.
Event :: union {
	sim.Event_Player_Joined,
	sim.Event_Player_Left,
	Event_Paused,
	Event_Prop_Grabbed,
	Event_Prop_Dropped,
	Event_Prop_Thrown,
	Event_Prop_Impact,
}
