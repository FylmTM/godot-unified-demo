// The save (unified/src/sim/README.md, Saves): the Setup that continues a crypt in a new session. The party's progress
// today is its tally: the floor it is on, the surges it has faced and the skeletons it has felled, taken when each
// surge rises (the floor's one beat), so a Continue starts that floor from its start with the tally carried on. The
// app keeps it as JSON (UnifiedSetup.to_json) in one slot, written by the host or the single player.
//
// Seam for the run (milestone 7): the Setup grows the run's floor, layout picks, boons and difficulty; a save reads over
// the build's default by field name, so an added field needs nothing, and SAVE_VERSION moves only when an old save
// can't be read as it is (its members gone, a list shrunk).
package crypt_crew

// A save's Setup.version: the save this build writes and continues (the app tells the player about any other).
SAVE_VERSION :: u8(1)

// The session's Setup: a new game (version 0, the zero Setup) or the save it continues (Game.save).
Setup :: struct {
	version: u8, // SAVE_VERSION for a save; 0: a new game
	floor:   Level_Id, // the floor the party continues on
	_pad:    [2]u8,
	surges:  u32, // the surges it had faced by the save
	kills:   u32, // the skeletons it had felled when the last surge rose
}

// The save from a tick's state (sim.Game.save): the floor and the tally as they stood at the last surge's rise.
// Nothing while no surge has risen this session (the surges a save it continues held, else none): the Setup it started
// from is still the save. So a save is made at each surge and never between (unified keeps a save only when its bytes
// change), whatever happens on the floor between two surges.
save :: proc(state: ^State, setup: ^Setup) -> bool {
	if state.surges == (setup.surges if setup.version == SAVE_VERSION else 0) do return false
	setup^ = {
		version = SAVE_VERSION,
		floor   = state.saved_floor,
		surges  = state.surges,
		kills   = state.saved_kills,
	}
	return true
}

// The floor a session starts on, with its tally (init): a save's, or Floor 1 and none for a new game.
start_from_setup :: proc(t: ^Tick) -> Level_Id {
	if t.setup.version != SAVE_VERSION {
		t.state.saved_floor = .Floor_1
		return .Floor_1
	}
	t.state.surges = t.setup.surges
	t.state.kills = t.setup.kills
	t.state.saved_kills = t.setup.kills
	t.state.saved_floor = t.setup.floor
	return t.setup.floor
}

// A surge rose: the floor and the tally the next save holds are this tick's (raise_surges).
mark_save_point :: proc(t: ^Tick) {
	t.state.saved_kills = t.state.kills
	t.state.saved_floor = t.state.level.id
}
