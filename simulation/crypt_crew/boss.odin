// The boss: the vault's `boss` marker, where the boss sleeps until the party comes for it (docs/plan.md, milestone 7:
// the boss). What the sim reads so far: where it stands and which way it faces. No rule makes it yet.
package crypt_crew

// The boss's place (a `boss` marker), one a floor at most.
Boss_Def :: struct {
	pos:    [3]f32,
	facing: [2]f32, // the marker's +Z on the floor plan, as an elite marker's: the way its model faces
	placed: bool, // the floor has one
	_pad:   [3]u8,
}
