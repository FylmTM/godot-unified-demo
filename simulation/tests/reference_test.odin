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
	checkpoints   = {0xaac9daf2edd9f463, 0x2a79bcad00ab4d74, 0x1f930bab9d561644, 0x9bb5b738ea4012e0},
	trace         = 0xf25717f1494bdc1b,
	snapshot      = 0x0cc18488ba5dd8b2,
	log           = 0xf1d081a5ee0fbcff,
	compat        = 0xa2a13335f109877f,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
