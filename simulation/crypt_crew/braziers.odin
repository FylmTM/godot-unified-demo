// Braziers: a floor's `brazier` markers, each standing beside a brazier part (its 3 m stand), lit by the party as a
// second way to open a gate (docs/plan.md, milestone 7: A floor). What the sim reads of them so far: where each stands
// and the gate it works, resolved once every marker is read. No rule lights one yet.
package crypt_crew

import "unified:sim"

// A brazier's place (a `brazier` marker).
Brazier_Def :: struct {
	pos:    [3]f32,
	target: i32, // the marker it works (level.prop_ref: -1 for none, as the vault's, which have no gate)
	gate:   i32, // its target among the floor's gates (link_braziers: -1 for none)
}

// Resolves each brazier's target marker to the gate it works (world_create, after every marker is read). A brazier may
// work none; one naming anything but a gate fails the level.
link_braziers :: proc(places: ^Places) {
	for &brazier in sim.slice(&places.braziers) {
		brazier.gate = -1
		for gate, i in sim.slice(&places.gates) {
			if gate.marker == brazier.target do brazier.gate = i32(i)
		}
		assert(brazier.target < 0 || brazier.gate >= 0, "crypt_crew: a brazier's target is no gate marker")
	}
}
