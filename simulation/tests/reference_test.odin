// crypt_crew's reference run (unified/src/headless/README.md, Reference runs). A new game starts from it unpinned
// (`uni init` leaves the results out): its run warns with the literal to paste until it is pinned, once the game's
// rules settle.
package test_crypt_crew

import "core:testing"
import "unified:headless/scenarios"

import g "../crypt_crew"

REFERENCE :: scenarios.Reference {
	seed          = 7,
	players       = 4,
	ticks         = 1200,
	snapshot_tick = 600,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
