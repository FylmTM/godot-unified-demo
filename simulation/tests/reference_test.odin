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
	checkpoints   = {0x08b60dcea247ceaa, 0xe85b46c73248e990, 0x2cb2697ca85918b5, 0x5856c334ec9e90cc},
	trace         = 0x98bfbe07ba9a583f,
	snapshot      = 0x2df8c3a2a38c6a5a,
	log           = 0x73342f0d72bd74b9,
	compat        = 0x80946353d7618760,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
