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
	checkpoints   = {0xa9b5fe2a2537d736, 0xc00c65d7c9c05f50, 0x3c7879d009a76e92, 0x1cc574c4d49d8e43},
	trace         = 0x065dbff76cb913f2,
	snapshot      = 0x5a0f36a09244ef71,
	log           = 0x2abbf129f132982e,
	compat        = 0xe3fd0e09fa8ec6cf,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
