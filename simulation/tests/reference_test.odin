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
	checkpoints   = {0x908da46d7215e8a9, 0xf24ee71829c3a186, 0x8cfa219405a2dc1f, 0xd26ff8344c65c684},
	trace         = 0x3b099ea73f62704f,
	snapshot      = 0x4ac9384be2e12059,
	log           = 0x43bc39f0dd1ab69f,
	compat        = 0x167ee8ca52ce98bb,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
