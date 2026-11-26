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
	checkpoints   = {0x5ad746846aedf31d, 0x922443679068648f, 0x3c5a5645e006bf2a, 0x6228d34beb66af0e},
	trace         = 0x273bfc3e1baba5fc,
	snapshot      = 0x585b5fb192adbdb5,
	log           = 0xb92b03ed2c349ad0,
	compat        = 0x54c53e6cf9c4087f,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
