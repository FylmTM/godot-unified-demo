// Crypt Crew's headless binary (`uni headless`): the sim without Godot, for sync-tests, offline runs, traces,
// replays, sessions on a virtual network, the net suite's processes and the standard benchmark (GAME.benches: four
// heroes against a held population of minions, director.odin's bench_prepare); unified's modes do the work
// (unified/src/headless/README.md), with EOS lobbies (eos-host, eos-client: two processes over EOS,
// unified/src/eos/README.md).
package main

import "unified:eos"
import "unified:headless/modes"

import g "../crypt_crew"

main :: proc() {
	// Test runs: no keychain dialog, and no device ID left behind for the next build to trip on (macOS).
	modes.run(&g.GAME, lobbies = {eos.lobby({no_keychain_prompts = true, forget_device = true})})
}
