// The co-op pause (unified/src/sim/README.md, Game time): pausing is state set by a command, so every peer pauses on
// the same tick; tick returns early while paused, and the State's Clock (game time) stands still, so timers and stamps
// wait it out.
package crypt_crew

import "unified:sim"

// Someone paused or resumed the game for everyone.
Event_Paused :: struct {
	player: sim.Player,
	paused: bool,
}

// Each present player's `Command_Set_Paused` pauses or resumes, from the next tick (announced once per change). Read on
// every tick, paused ones too, and before tick returns early: a command arrives once, so a command the paused systems
// would skip is gone (a class change sent during a pause is dropped).
apply_pause :: proc(t: ^Tick) {
	players := sim.iterate_present(t)
	for _, player in sim.next(&players) {
		for sent in sim.commands(t, player) {
			pause := sent.(Command_Set_Paused) or_continue
			if t.state.clock.paused == pause.paused do continue
			sim.set_paused(t, pause.paused)
			sim.emit(t, Event_Paused{player = player, paused = pause.paused})
		}
	}
}
