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
	checkpoints   = {0x276f24fe698e41ba, 0x734904828c1c11ea, 0x3e824294ee14781d, 0x5820e42bb019941f},
	trace         = 0x91307cc6c4671843,
	snapshot      = 0x82d84d62530403e5,
	log           = 0x253daff00f2a4a66,
	compat        = 0xff3fbec479c8f122,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
