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
	checkpoints   = {0xd44018e86e05e8b4, 0x77140c06b20ba784, 0xb3a2e163ad0a8683, 0xa5bbd15fe8ca38b9},
	trace         = 0x2fc901a2ad09ed13,
	snapshot      = 0x3c7a3dc4b1565641,
	log           = 0x077aa7c92df5ff4b,
	compat        = 0x70302a06f3bf9bbb,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
