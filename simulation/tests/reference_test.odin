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
	checkpoints   = {0xbe8acddfb64f2abe, 0x17498b802d299762, 0xcbf8299aeb66bb09, 0x12cb5399fc8ebe48},
	trace         = 0xabd021a9b4c34651,
	snapshot      = 0x1589df7ee83089a3,
	log           = 0x4d6aed371bc8a121,
	compat        = 0xf81e7773559a72d8,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
