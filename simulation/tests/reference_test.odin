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
	checkpoints   = {0x908da46d7215e8a9, 0xf24ee71829c3a186, 0x8cfa219405a2dc1f, 0x61e036c5e9f9c59e},
	trace         = 0xaba72a543c937e37,
	snapshot      = 0x46cdd65411ed5302,
	log           = 0x470699165b58e1af,
	compat        = 0x41202eb1f790a0fb,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
