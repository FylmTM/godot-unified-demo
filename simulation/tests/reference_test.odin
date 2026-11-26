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
	checkpoints   = {0x4f8943649257e36e, 0x54cc7fb941f68291, 0xba89d8237821e4af, 0x08c45d332b32171e},
	trace         = 0x6fbf8023f315bf96,
	snapshot      = 0xdb3561f5bf465e91,
	log           = 0xb5a685a8ddeeed3d,
	compat        = 0x7f1795365d71a3b0,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
