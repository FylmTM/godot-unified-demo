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
	checkpoints   = {0xaddcec27198a1a9a, 0xf52649f854fec126, 0xc8fef05f65f7ad94, 0xff960c5c290ee9fb},
	trace         = 0x07a87b12ac9d77dd,
	snapshot      = 0xfbec1a745e77b70e,
	log           = 0xc0afaada7443c2ac,
	compat        = 0xc9b490c79c6fa9c8,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
