// The heroes' abilities, the machinery every class shares; each class's own is in its file (knight: block and shield
// charge, rogue: dodge roll, mage: fireball, barbarian: the heave). Ability is read like Attack: a hero up, its hands
// free of a prop, doing nothing else or attacking (an ability cuts an attack short, so a held Attack never locks it
// out), starts its class's ability when the button says so and the hero's own cooldown (Hero.ability_ready) ran out.
// An ability is an action (Block, Charge, Roll, Cast, Heave, Hurl) with its start, so the view poses it from the state
// and a rollback re-poses it; each runs its course here, before the attacks start (an Attack pressed while blocking is
// a charge, and while heaving a throw, not a swing). What a blow does to a hero mid-ability is guarded_damage and
// rolled_clear, which damage_hero asks.
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// `player`'s hero began its class's ability (a block raised, a charge, a roll, a cast): for a sound.
Event_Ability :: struct {
	player: sim.Player,
	class:  Class,
}

// `player`'s hero's shield met a blow at `position` (its face, chest-high): a block's clang, or a charge's.
Event_Blocked :: struct {
	player:   sim.Player,
	position: sim.Position,
}

// The actions a class's attack or ability is: a class change ends them (dev.odin).
CLASS_ACTIONS :: bit_set[Action]{.Attack, .Block, .Charge, .Roll, .Cast, .Heave, .Hurl}

// Each present hero's ability: the one under way runs its course (a block lasts while Ability is held, a charge
// CHARGE_S, a roll ROLL_S, a cast its windup, at whose end the fireball leaves, a heave as heave_on says), then the
// hero's class may start one.
use_abilities :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		buttons := sim.buttons(t, player)
		age := u32(t.time - hero.action_started)
		#partial switch hero.action {
		case .Block:
			if .Ability not_in buttons.down do hero.action, hero.action_started = .None, t.time
		case .Charge:
			if age >= CHARGE_TICKS do hero.action, hero.action_started = .None, t.time
		case .Roll:
			if age >= ROLL_TICKS do hero.action, hero.action_started = .None, t.time
		case .Cast:
			if age >= FIREBALL_WINDUP_TICKS {
				cast_fireball(t, hero, player)
				hero.action, hero.action_started = .None, t.time
			}
		case .Heave, .Hurl:
			heave_on(t, hero, player)
		}
		switch hero.class {
		case .Knight:
			knight_ability(t, hero, player, buttons)
		case .Rogue:
			rogue_ability(t, hero, player, buttons)
		case .Mage:
			mage_ability(t, hero, player, buttons)
		case .Barbarian:
			barbarian_ability(t, hero, player, buttons)
		case .Any:
		}
	}
}

// Whether a hero is free to start an ability: up, hands free, doing nothing else or attacking (which it cuts short).
can_start_ability :: proc(hero: ^Hero) -> bool {
	return hero.held == {} && (hero.action == .None || hero.action == .Attack)
}

// Starts `action` (an ability of `player`'s hero) now, its cooldown `cooldown` ticks from now (0: none, a block;
// Quick_Hands shortens it: hands_cooldown), and tells the views.
start_ability :: proc(t: ^Tick, hero: ^Hero, player: sim.Player, action: Action, cooldown: u32) {
	hero.action, hero.action_started = action, t.time
	if cooldown > 0 do sim.timer_start_ticks(t, &hero.ability_ready, hands_cooldown(hero, cooldown))
	sim.emit(t, Event_Ability{player = player, class = hero.class})
}

// A dash along the hero's facing at `speed` metres per second: its body set going at once (the drive, which keeps it
// at that speed while the dash lasts, would take a quarter of a second to get there), its fall kept.
dash :: proc(t: ^Tick, hero: ^Hero, speed: f32) {
	velocity := [3]f32{hero.facing.x * speed, hero.vel.y, hero.facing.y * speed}
	physics.body_set_linear_velocity(t.world.phys, hero.body.body, velocity)
}

// What a hero's drive does during its action: its stick, and the share of its class's speed (with what it carries,
// carry_speed, or how it hauls the hoard, haul_speed), all of it Swift_Boots' faster (boots_scale); a hero down is held
// still (a heaved one hangs limp, its drive off), and a dash (a charge, a roll) runs along its facing at its own speed.
action_drive :: proc(t: ^Tick, hero: ^Hero, stick: [2]f32) -> (move: [2]f32, scale: f32) {
	max_speed := t.world.hero_defs[hero.class].max_speed
	#partial switch hero.action {
	case .Down:
		return {}, 1 // the drive holds it still
	case .Charge:
		return hero.facing, CHARGE_SPEED / max_speed
	case .Roll:
		return hero.facing, ROLL_SPEED / max_speed
	case .Attack, .Cast:
		return stick, carry_speed(t, hero) * ATTACK_SPEED * boots_scale(hero)
	case .Block:
		return stick, BLOCK_SPEED * boots_scale(hero)
	case .Revive:
		return stick, REVIVE_SPEED * boots_scale(hero)
	case .Heave, .Hurl:
		return stick, HEAVE_SPEED * boots_scale(hero)
	case .Haul:
		return stick, haul_speed(t, hero) * boots_scale(hero)
	}
	return stick, carry_speed(t, hero) * boots_scale(hero)
}

// What reaches `player`'s hero of a blow of `damage` from something at `from`: a blow from the front (within
// BLOCK_ARC_COS of the facing) meets a raised shield, which lets BLOCK_TAKE of it through, or a charging one, which lets
// nothing; either tells the views (Event_Blocked). A blow from anywhere else, or from right where the hero stands (a dev
// hurt), takes it all.
guarded_damage :: proc(t: ^Tick, hero: ^Hero, player: sim.Player, damage: i16, from: [3]f32) -> i16 {
	if hero.action != .Block && hero.action != .Charge do return damage
	toward := dmath.normalize(from.xz - hero.pos.xz)
	if toward == {} || dmath.dot(toward, hero.facing) < BLOCK_ARC_COS do return damage
	face := hero.pos + [3]f32{toward.x * HERO_RADIUS, CHEST_HEIGHT, toward.y * HERO_RADIUS}
	sim.emit(t, Event_Blocked{player = player, position = sim.Position(face)})
	if hero.action == .Charge do return 0
	return i16(dmath.to_i32_clamped(dmath.round(f32(damage) * BLOCK_TAKE), 0, i32(damage)))
}

// Whether a hero is in the safe start of a roll (its first ROLL_SAFE_TICKS): nothing hurts it.
rolled_clear :: proc(t: ^Tick, hero: ^Hero) -> bool {
	return hero.action == .Roll && u32(t.time - hero.action_started) < ROLL_SAFE_TICKS
}

// How far a hero's ability cooldown has run, 0 (just started) to 1 (ready): the HUD's pip.
ability_charge :: proc(time: sim.Game_Time, hero: ^Hero) -> f32 {
	timer := hero.ability_ready
	if !sim.timer_running(time, timer) do return 1
	return f32(time - timer.start) / f32(timer.target - timer.start)
}
