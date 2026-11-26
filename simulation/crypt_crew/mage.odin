// The Mage: its attack a bolt cast along its facing at the windup, which flies on its own (bolts.odin); its ability a
// fireball. Ability's press winds up a cast (Action.Cast) for FIREBALL_WINDUP_S, during which the Mage may still aim;
// at its end the fireball leaves for where the aim then points (fireball_target), lobbed over everything, and bursts
// there (fireballs.odin).
package crypt_crew

import "unified:sim"

// The Mage's spell lands: a bolt leaves its chest along its facing.
mage_strike :: proc(t: ^Tick, hero: ^Hero, player: sim.Player) {
	cast_bolt(t, hero, player)
}

// The Mage's ability: Ability pressed while free (can_start_ability) and its cooldown ran out begins a cast.
mage_ability :: proc(t: ^Tick, hero: ^Hero, player: sim.Player, buttons: sim.Button_State(Buttons)) {
	if .Ability not_in buttons.pressed || !can_start_ability(hero) || sim.timer_running(t, hero.ability_ready) do return
	start_ability(t, hero, player, .Cast, FIREBALL_COOLDOWN_TICKS)
}
