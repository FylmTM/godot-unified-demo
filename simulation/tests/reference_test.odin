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
	checkpoints   = {0xebfbf9f62cff6854, 0x1db3f5d6cb7fd414, 0x53aae096296e6bf5, 0x04ddcce0156b162b},
	trace         = 0xace72eaf8f0b2ae8,
	snapshot      = 0x65e820d8f5dd2b05,
	log           = 0xf7ccfc71fec3a6cc,
	compat        = 0x07314a8eb778a566,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
