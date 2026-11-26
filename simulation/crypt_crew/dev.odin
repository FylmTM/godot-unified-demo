// The dev commands (`Command_Dev_*`): cheats and test shortcuts, offered as forms in the dev UI and left out by a
// public build, which then computes differently and refuses a dev build (unified/src/sim/README.md, Commands).
// Otherwise ordinary commands: relayed, logged and replayed, the same tick on every peer.
package crypt_crew

import "unified:dmath"
import "unified:sim"

// Each present player's dev commands: `Command_Dev_Set_Class` turns their hero into another class (ending an attack
// or an ability of the old one, and that ability's cooldown), `Command_Dev_Spawn_Minions` raises minions around it,
// `Command_Dev_Hurt` hurts a hero, `Command_Dev_Kill_Minions` kills every minion (through damage_minion, as the
// attacks do), `Command_Dev_Revive` revives a hero down (through revive_hero, as an ally's revive does), or every one.
// The elites' (elites.odin): `Command_Dev_Spawn_Elite` raises one ahead of the hero, `Command_Dev_Hurt_Elites` hurts
// every one (damage_elite), `Command_Dev_Break_Guards` breaks every Warrior's guard (break_guard).
apply_dev_commands :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		for sent in sim.commands(t, player) {
			#partial switch command in sent {
			case Command_Dev_Set_Class:
				if command.class == .Any || command.class == hero.class do break
				hero.class = command.class
				if hero.action in CLASS_ACTIONS do hero.action = .None // the old class's ends with it ...
				sim.timer_stop(&hero.ability_ready) // ... and so does its ability's cooldown
			case Command_Dev_Spawn_Minions:
				spawn_around(t, hero.pos, int(command.count))
			case Command_Dev_Hurt:
				victim := command.player if command.player != {} else player
				if target := sim.player_data(t, victim); target != nil do damage_hero(t, victim, command.damage, target.pos)
			case Command_Dev_Kill_Minions:
				minions := sim.iterate(&t.state.minions)
				for minion, handle in sim.next(&minions) {
					away := dmath.normalize(minion.pos.xz - hero.pos.xz)
					damage_minion(t, handle, MINION_HP, away, DEV_KILL_KNOCK, player, .Dev)
				}
			case Command_Dev_Revive:
				downed := sim.iterate_present(t)
				for other, other_player in sim.next(&downed) {
					if other.action != .Down do continue
					if command.player == {} || command.player == other_player do revive_hero(t, other_player, player)
				}
			// Elites
			case Command_Dev_Spawn_Elite:
				ahead := hero.pos + [3]f32{hero.facing.x, 0, hero.facing.y} * DEV_SPAWN_RING
				raise_elite(t, command.kind, ahead, -hero.facing)
			case Command_Dev_Hurt_Elites:
				elites := sim.iterate(&t.state.elites)
				for elite, handle in sim.next(&elites) {
					damage_elite(t, handle, command.damage, {}, 0, player, .Dev, elite.pos.xz)
				}
			case Command_Dev_Break_Guards:
				elites := sim.iterate(&t.state.elites)
				for _, handle in sim.next(&elites) do break_guard(t, handle, player)
			}
		}
	}
}

// `count` minions rising on a ring DEV_SPAWN_RING around `centre`, evenly spaced, each on the walkable floor, while
// fewer than the floor's cap are alive and the table has a row free; none while a population is held (State.held:
// it is exactly what was asked, so a benchmark's row compares across builds).
@(private = "file")
spawn_around :: proc(t: ^Tick, centre: [3]f32, count: int) {
	if t.state.held > 0 do return
	floor := floor_of(t)
	for i in 0 ..< count {
		if minions_alive(&t.state.minions) >= floor.minion_cap || free_rows(&t.state.minions) == 0 do return
		dir := dmath.angle_vec(f32(i) / f32(count))
		spot := floor_spot(floor, centre + {dir.x, 0, dir.y} * DEV_SPAWN_RING, DEV_SPAWN_RING) or_continue
		spawn_minion(t.state, spot.point, spot.poly, -dir, .Rise, t.time)
	}
}
