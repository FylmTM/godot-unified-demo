// A hero's health: damage_hero is the only way a hero takes damage and goes down (a spawn and a rise set its hit
// points whole). A hero at 0 HP goes down: it lets go of what it carries, stops where it is (its drive holds it there,
// so it neither slides nor sinks), and minions stop chasing it, for RESPAWN_TICKS; then it rises beside the party
// (arrival_spot) with SPAWN_GRACE_TICKS in which nothing hurts it. When every hero present is down at once, the floor
// starts over (restart_floor).
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// `player`'s hero took `damage` from something at `position`, leaving `hp`.
Event_Hero_Hurt :: struct {
	player:   sim.Player,
	position: sim.Position,
	damage:   i16,
	hp:       i16,
}

// `player`'s hero went down at `position`.
Event_Hero_Downed :: struct {
	player:   sim.Player,
	position: sim.Position,
}

// The whole party was down: the floor started over.
Event_Floor_Restarted :: struct {}

// Whether `player` is present with a hero that is up (not down).
hero_up :: proc(t: ^Tick, player: sim.Player) -> bool {
	if !sim.player_present(t, player) do return false
	return sim.player_data(t, player).action != .Down
}

// `player`'s hero takes `damage` from something at `from`, unless it is down or in its grace, or a crowd is held (a
// wipe would restart the floor and empty it: director.odin, Crowd); at 0 HP it goes down.
damage_hero :: proc(t: ^Tick, player: sim.Player, damage: i16, from: [3]f32) {
	if damage <= 0 || !hero_up(t, player) || t.setup.crowd != .None do return
	hero := sim.player_data(t, player)
	if sim.timer_running(t, hero.grace) do return
	hero.hp = dmath.max(hero.hp - damage, 0)
	sim.emit(t, Event_Hero_Hurt{player = player, position = sim.Position(from), damage = damage, hp = hero.hp})
	if hero.hp > 0 do return
	drop_prop(t, player)
	physics.body_set_linear_velocity(t.world.phys, hero.body.body, {})
	hero.vel = {}
	hero.action, hero.action_started = .Down, t.time
	sim.timer_start_ticks(t, &hero.respawn, RESPAWN_TICKS)
	sim.emit(t, Event_Hero_Downed{player = player, position = sim.Position(hero.pos)})
}

// Each hero down whose RESPAWN_TICKS ran out rises beside the party (arrival_spot): its body moved there (its view
// snaps), up again at full health, in its grace.
rise_heroes :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		if hero.action != .Down || sim.timer_running(t, hero.respawn) do continue
		feet, beside := arrival_spot(t, player)
		physics.character_teleport(t.world.phys, &hero.body, feet + {0, HERO_CENTRE_ABOVE_FEET, 0})
		hero.pos, hero.vel = feet, {}
		hero.hp = HERO_HP
		hero.action, hero.action_started = .None, t.time
		sim.timer_stop(&hero.respawn)
		sim.timer_start_ticks(t, &hero.grace, SPAWN_GRACE_TICKS)
		sim.emit(t, Event_Hero_Spawned{player = player, position = sim.Position(feet), beside = beside})
	}
}

// Every hero present down at once: the floor starts over.
check_wipe :: proc(t: ^Tick) {
	if sim.present_count(t) == 0 do return
	heroes := sim.iterate_present(t)
	for _, player in sim.next(&heroes) {
		if hero_up(t, player) do return
	}
	restart_floor(t)
}
