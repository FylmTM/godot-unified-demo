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
	checkpoints   = {0x431cc0d40559fbfa, 0xf252a519e3ec8274, 0x42a58bd95dd8bcdc, 0xd809270da2509ad5},
	trace         = 0xb68477be63610020,
	snapshot      = 0xa2b4ef57e22f3895,
	log           = 0xcc4dbe221d1a0d76,
	compat        = 0xfc8d9ad8bde99b38,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
