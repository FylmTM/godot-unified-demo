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
	checkpoints   = {0x4aa3876cf018e275, 0x22310db8878e5f8c, 0x60cb816c9bcc9c2c, 0xe6fbd5fc8012b1c5},
	trace         = 0x086b18e66a43dee7,
	snapshot      = 0x81184b751f657cf7,
	log           = 0x61ec3058d30070bd,
	compat        = 0x14d717081d4245aa,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
