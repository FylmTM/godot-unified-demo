// Crypt Crew's headless binary (`uni headless`): the sim without Godot, for sync-tests, offline runs, traces,
// replays, sessions on a virtual network and the net suite's processes; unified's modes do the work
// (unified/src/headless/README.md).
package main

import "unified:headless/modes"

import g "../crypt_crew"

main :: proc() {
	// No standard benchmark yet (`uni bench` runs only the game's sessions): the bench row (four heroes, a held surge,
	// the floor's props) comes with the skeletons (docs/plan.md, Milestone 2: the design).
	modes.run(&g.GAME)
}
