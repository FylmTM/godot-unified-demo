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
	checkpoints   = {0x6898403a984ba6fa, 0x6c847d822f5ee62d, 0xbb4546d752e2c0c5, 0x1a76d82fc5f9478c},
	trace         = 0x1b6ac0b8c4a928ae,
	snapshot      = 0x65d5ecb69c90a438,
	log           = 0x96d09c0f4113687a,
	compat        = 0x7bdb2085da59d8f2,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
