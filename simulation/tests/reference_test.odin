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
	checkpoints   = {0x048ed4b306c5f8fe, 0x0a4392614c3d9047, 0x1ab93eac4fe07c8c, 0x51fe1c9c3b895984},
	trace         = 0x328f8e7b521e7012,
	snapshot      = 0x91ebeb08d9a449da,
	log           = 0xb0032ecabf3a6e58,
	compat        = 0xf69f001b6904c0a9,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
