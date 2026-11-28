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
	checkpoints   = {0x60aff3a945af80ba, 0x0fa097acb9c57b43, 0xff3086fbb604365d, 0x382f1d2b7a0b00ba},
	trace         = 0x9a6184c7c2a6a820,
	snapshot      = 0xa220c2bf46500ef0,
	log           = 0x000bdbae0b789a77,
	compat        = 0xf786f547007783c1,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
