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
	checkpoints   = {0x6605397d3204672e, 0x1e240f4263d54a2f, 0xe30f2b3d720b2b6d, 0x09a430c7c41b93b5},
	trace         = 0x8fc4340df3dea143,
	snapshot      = 0x669505f77855b9e0,
	log           = 0xbd6ac31c3d3757c1,
	compat        = 0x3d3f79e81198b0a5,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
