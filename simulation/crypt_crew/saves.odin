// The save (unified/src/sim/README.md, Saves): the Setup that continues a crypt in a new session. The party's progress
// today is its tally: the floor it is on, the surges it has faced, the skeletons it has felled and the gold in its
// purse, taken when each surge rises (the floor's beat), and the depth the lift has taken it to, taken as it descends
// (a new floor's start), so a Continue starts that floor from its start with the tally carried on (the coins left lying
// go with the floor; boons aren't kept yet: a Continue starts without them, until the run's save moves to the lift). The
// app keeps it as JSON (UnifiedSetup.to_json) in one slot, written by the host or the single player.
//
// Seam for the run (milestone 7): the Setup grows the run's floor, layout picks, boons and difficulty; a save reads over
// the build's default by field name, so an added field needs nothing, and SAVE_VERSION moves only when an old save
// can't be read as it is (its members gone, a list shrunk).
package crypt_crew

// A save's Setup.version: the save this build writes and continues (the app tells the player about any other).
SAVE_VERSION :: u8(1)

// The session's Setup: a new game (version 0: Floor 1 and no crowd unless set) or the save it continues (Game.save).
Setup :: struct {
	version: u8, // SAVE_VERSION for a save; 0: a new game
	floor:   Level_Id, // the floor the party starts on: a new game's (Floor 1 unless set), the one a save continues on
	// A held crowd instead of the director's packs and surges (director.odin, Crowd): the benchmark rows', the scale
	// tests', a look at a crowd (`--setup floor=arena,crowd=fight`). Never in a save.
	crowd:   Crowd,
	_pad:    [1]u8,
	surges:  u32, // the surges it had faced by the save
	kills:   u32, // the skeletons it had felled when the last surge rose
	gold:    u32, // the gold in its purse when the last surge rose (loot.odin; added by name: an older save reads 0)
	depth:   u32, // the floors it had gone down (lift.odin; added by name: an older save reads 0)
}

// The save from a tick's state (sim.Game.save): the floor and the tally as they stood at the last save point (a surge's
// rise, or the lift's descent). Nothing while no surge has risen and the party hasn't gone down this session (the surges
// and depth a save it continues held, else none): the Setup it started from is still the save. So a save is made at
// each surge and each descent and never between (unified keeps a save only when its bytes change), whatever happens on
// the floor between them.
save :: proc(state: ^State, setup: ^Setup) -> bool {
	continued := setup.version == SAVE_VERSION
	if state.surges == (setup.surges if continued else 0) && state.depth == (setup.depth if continued else 0) {
		return false
	}
	setup^ = {
		version = SAVE_VERSION,
		floor   = state.saved_floor,
		surges  = state.surges,
		kills   = state.saved_kills,
		gold    = state.saved_gold,
		depth   = state.depth,
	}
	return true
}

// The floor a session starts on, with its tally (init): a save's, or a new game's with none.
start_from_setup :: proc(t: ^Tick) -> Level_Id {
	t.state.saved_floor = t.setup.floor
	if t.setup.version != SAVE_VERSION do return t.setup.floor
	t.state.surges = t.setup.surges
	t.state.kills = t.setup.kills
	t.state.saved_kills = t.setup.kills
	t.state.gold = t.setup.gold
	t.state.saved_gold = t.setup.gold
	t.state.depth = t.setup.depth
	return t.setup.floor
}

// A surge rose (raise_surges), or the party went down to a new floor (lift.odin): the floor and the tally the next save
// holds are this tick's.
mark_save_point :: proc(t: ^Tick) {
	t.state.saved_kills = t.state.kills
	t.state.saved_floor = t.state.level.id
	t.state.saved_gold = t.state.gold
}
