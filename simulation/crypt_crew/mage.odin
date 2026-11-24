// The Mage's attack: a bolt cast along its facing at the windup, which flies on its own (bolts.odin).
package crypt_crew

import "unified:sim"

// The Mage's spell lands: a bolt leaves its chest along its facing.
mage_strike :: proc(t: ^Tick, hero: ^Hero, player: sim.Player) {
	cast_bolt(t, hero, player)
}
