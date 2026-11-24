// Crypt Crew's headless binary (`uni headless`): the sim without Godot, for sync-tests, offline runs, traces,
// replays, sessions on a virtual network, the net suite's processes and the standard benchmark (GAME.benches: four
// heroes against a held population of minions, director.odin's bench_prepare); unified's modes do the work
// (unified/src/headless/README.md).
package main

import "unified:headless/modes"

import g "../crypt_crew"

main :: proc() {
	modes.run(&g.GAME)
}
