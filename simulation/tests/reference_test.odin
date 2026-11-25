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
	checkpoints   = {0x908da46d7215e8a9, 0xf24ee71829c3a186, 0x8cfa219405a2dc1f, 0x62310017034313e5},
	trace         = 0x607306f39e781564,
	snapshot      = 0x955a1e8b1cfd0e42,
	log           = 0x859db1fa9d6f8bf1,
	compat        = 0x440d14ae9e5586cb,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
