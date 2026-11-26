// The Knight: a quick, narrow sword arc (CLASS_SPECS[.Knight], strike_arc), and a shield. Ability held raises it
// (Action.Block: a blow from the front lets BLOCK_TAKE through, guarded_damage; the Knight slows to BLOCK_SPEED), and
// Attack pressed behind it is a shield charge (Action.Charge): a dash at CHARGE_SPEED for CHARGE_S, every blow from the
// front taken by the shield, and every CHARGE_HIT_TICKS a blast from the shield's face (knock_area) that knocks the
// skeletons in front aside and breaks a Warrior's guard. The charge has the Knight's ability cooldown; the block has
// none.
package crypt_crew

import "unified:sim"

// The Knight's blow lands: its sword's arc.
knight_strike :: proc(t: ^Tick, hero: ^Hero, player: sim.Player) {
	strike_arc(t, hero, player, &CLASS_SPECS[.Knight])
}

// The Knight's ability: Attack pressed while blocking charges (once the cooldown ran out), and Ability held while free
// (can_start_ability) blocks.
knight_ability :: proc(t: ^Tick, hero: ^Hero, player: sim.Player, buttons: sim.Button_State(Buttons)) {
	if hero.action == .Block {
		if .Attack not_in buttons.pressed || sim.timer_running(t, hero.ability_ready) do return
		start_ability(t, hero, player, .Charge, CHARGE_COOLDOWN_TICKS)
		dash(t, hero, CHARGE_SPEED)
	} else if .Ability in buttons.down && can_start_ability(hero) {
		start_ability(t, hero, player, .Block, 0)
	}
}

// After the physics step: each charging Knight's shield knocks aside what is in front, every CHARGE_HIT_TICKS from the
// charge's start: a blast of CHARGE_RADIUS from the shield's face, chest-high (knock_area: walls shield, its knock
// falls off to BLAST_RIM at the rim, and a Warrior's guard breaks before the blow, which then lands whole).
charge_strikes :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		if hero.action != .Charge || u32(t.time - hero.action_started) % CHARGE_HIT_TICKS != 0 do continue
		face := hero.pos + [3]f32{hero.facing.x * HERO_RADIUS, CHEST_HEIGHT, hero.facing.y * HERO_RADIUS}
		knock_area(t, face, CHARGE_RADIUS, CHARGE_DAMAGE, CHARGE_KNOCK, player, .Charge, breaks_guard = true)
	}
}
