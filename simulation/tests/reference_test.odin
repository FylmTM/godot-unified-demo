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
	checkpoints   = {0xefa257c8a226b09a, 0x73a909be89b6de29, 0xbced8a7dba35a8eb, 0xd04605458482a24f},
	trace         = 0x02799484e4204e73,
	snapshot      = 0xb320484ac0d44e4e,
	log           = 0x4526d9bb648cbfa4,
	compat        = 0x6121db39a910c988,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
