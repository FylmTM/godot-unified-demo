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
	checkpoints   = {0x460ee5d3a7162a59, 0xf740080c019bf378, 0x9fc54c8d45431e14, 0xe9d408b5f9c827e3},
	trace         = 0x05acf18c8ccd061a,
	snapshot      = 0xb89b5b0e3031242b,
	log           = 0xb05c466f87081645,
	compat        = 0xe0402c11913ea3e9,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
