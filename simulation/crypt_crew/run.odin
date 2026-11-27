// The run: the hub between runs, where the party sets the next run's mode and difficulty at its shrines and boards the
// crypt's lift (docs/plan.md, milestone 7). What the sim reads so far: the hub's `shrine` markers, where each stands and
// which setting it sets. No rule uses them yet.
package crypt_crew

// What a shrine sets (game/levels/markers/shrine.gd's `sets`, by name).
Shrine_Setting :: enum u8 {
	Mode, // the crypt's floors or the endless arena
	Difficulty,
}

// A shrine's place (a `shrine` marker): a floor's Places keep one for each setting at most.
Shrine_Def :: struct {
	pos:    [3]f32,
	placed: bool, // the floor has one for this setting
	_pad:   [3]u8,
}
