// crypt_crew's reference run (unified/src/headless/README.md, Reference runs): four scripted heroes for 2400 ticks, long
// enough to cross several surges and a wipe (the script downs all four every third round), snapshotted midway.
package test_crypt_crew

import "core:testing"
import "unified:headless/scenarios"

import g "../crypt_crew"

REFERENCE :: scenarios.Reference {
	seed          = 7,
	players       = 4,
	ticks         = 2400,
	snapshot_tick = 1200,
	checkpoints   = {0x5b676008158e7475, 0x6f462d331131cc52, 0x2cb2697ca85918b5, 0x8bdd8d1b27c7de89},
	trace         = 0x24aa31145d7ca06c,
	snapshot      = 0x0c90eac33c8133cf,
	log           = 0x983e1c4eba11a1b9,
	compat        = 0x8ad5b0b338556942,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
