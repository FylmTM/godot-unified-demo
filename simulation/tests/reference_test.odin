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
	checkpoints   = {0x6605397d3204672e, 0x4632c92670b9d3c6, 0xe30f2b3d720b2b6d, 0xc95754170f493e5c},
	trace         = 0x4b7e329f662ddb86,
	snapshot      = 0x7e9e32e87bb0422c,
	log           = 0x6eb4d2dce651b901,
	compat        = 0x16eb0bb96805c88a,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
