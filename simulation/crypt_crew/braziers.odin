// Braziers: a floor's `brazier` markers, each standing at a brazier part (its 3 m stand, a column holding an unlit
// bowl), which the party lights as a second way to open a gate beside its plates, and the vault's to break the boss's
// ward (boss.odin). Kindled like a revive (revive.odin): a hero up, hands free and doing nothing else or attacking, that
// presses Interact within BRAZIER_RANGE of an unlit brazier starts kindling it (Action.Kindle; the press grabs
// nothing), and keeps on while it holds Interact and stays in range, moving at KINDLE_SPEED; letting go, walking off or
// a blow taken (damage_hero) breaks it off, and only a new press starts it again. Each tick a brazier gains a tick of
// progress per hero kindling it (two light it twice as fast) and, with nobody kindling it, loses all of it; at
// BRAZIER_LIGHT_TICKS it lights. A Mage's fireball bursting within BRAZIER_BLAST lights it at once, unless a wall stands
// between. Lit, it stays lit until the party enters the floor again or the boss douses every brazier (a stage).
//
// A lit brazier counts toward its gate's need as a pressed plate does (gates.odin), and each lighting brings the next
// surge within BRAZIER_SURGE_S: the crypt answers the light. The table's rows are the floor's markers in order (made on
// entering), so a row's index is its marker's in the floor's Places, and a brazier has no body: its stand is the
// level's static part. kindle_target is both what the tick kindles and what the view's "[E] Light" prompt asks.
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// A brazier's place (a `brazier` marker, at its stand's foot).
Brazier_Def :: struct {
	pos:    [3]f32,
	target: i32, // the marker it works (level.prop_ref: -1 for none, as the vault's, which have no gate)
	gate:   i32, // its target among the floor's gates (link_braziers: -1 for none)
}

// A brazier, a row of the State's `braziers` (its index is its marker's in the floor's Places).
Brazier :: struct {
	lit_at:   sim.Game_Time, // when it last lit (0: never)
	by:       sim.Player, // who lit it: the first hero kindling it in slot order, or the fireball's caster
	progress: u16, // while unlit: the ticks of kindling it has had (BRAZIER_LIGHT_TICKS: it lights)
	lit:      bool,
	_pad:     u8,
}

// `brazier` lit (`lit`; `player` lit it) or went out (the boss doused it; `player` is nobody), at `position` (its
// stand's foot).
Event_Brazier :: struct {
	brazier:  sim.Handle(Brazier),
	position: sim.Position,
	player:   sim.Player,
	lit:      bool,
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

// A row for each of the floor's brazier markers, in marker order, unlit (entering a floor).
spawn_braziers :: proc(t: ^Tick) {
	for _ in sim.slice(&floor_of(t).places.braziers) {
		_, _, ok := sim.spawn(&t.state.braziers)
		assert(ok, "crypt_crew: more braziers than MAX_BRAZIERS") // world_create's list holds as many
	}
}

// The unlit brazier `player`'s hero would kindle now (the null handle: none). None unless that hero is present, up,
// its hands free and doing nothing else, attacking or kindling already; else the nearest unlit brazier within
// BRAZIER_RANGE of its feet on the floor plan, on a tie the lower index. Pure: what the tick (kindle_braziers) and the
// view's prompt both ask, on the active floor's brazier places (`defs`).
kindle_target :: proc(
	players: ^Heroes,
	braziers: ^sim.Table(Brazier, MAX_BRAZIERS),
	defs: []Brazier_Def,
	player: sim.Player,
) -> (
	target: sim.Handle(Brazier),
) {
	if !sim.player_present(players, player) do return
	hero := sim.player_data(players, player)
	if hero.held != {} || (hero.action != .None && hero.action != .Attack && hero.action != .Kindle) do return
	nearest := BRAZIER_RANGE * BRAZIER_RANGE
	walk := sim.iterate(braziers)
	for brazier, handle in sim.next(&walk) {
		if brazier.lit do continue
		apart := dmath.length_sq(defs[handle.index].pos.xz - hero.pos.xz)
		if apart <= nearest && (target == {} || apart < nearest) do target, nearest = handle, apart
	}
	return
}

// Each present hero's kindling, then each brazier's progress. A hero doing nothing or attacking that presses Interact
// with a kindle_target starts kindling it (an attack cut short); one kindling keeps on while it holds Interact and still
// has a target, and stops otherwise. Then each unlit brazier gains a tick for each hero kindling it and lights at
// BRAZIER_LIGHT_TICKS (the first of them, in slot order, its lighter), or loses its progress with nobody kindling it.
// After revive_heroes (a press beside a downed ally revives, and kindles nothing) and before use_hands (the press that
// starts a kindling grabs nothing).
kindle_braziers :: proc(t: ^Tick) {
	if t.state.braziers.count == 0 do return
	defs := sim.slice(&floor_of(t).places.braziers)
	kindling: [MAX_BRAZIERS]u16 // by the brazier's index: the heroes kindling it this tick ...
	first: [MAX_BRAZIERS]sim.Player // ... and the first of them (in slot order)
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		if hero.action != .None && hero.action != .Attack && hero.action != .Kindle do continue
		buttons := sim.buttons(t, player)
		target := kindle_target(&t.state.players, &t.state.braziers, defs, player)
		kindles := target != {} && .Interact in buttons.down
		if hero.action != .Kindle do kindles &&= .Interact in buttons.pressed // a kindling starts with a press
		if !kindles {
			if hero.action == .Kindle do hero.action, hero.action_started = .None, t.time
			continue // an attack goes on
		}
		if hero.action != .Kindle do hero.action, hero.action_started = .Kindle, t.time
		if kindling[target.index] == 0 do first[target.index] = player
		kindling[target.index] += 1
	}
	walk := sim.iterate(&t.state.braziers)
	for brazier, handle in sim.next(&walk) {
		if brazier.lit do continue
		if kindling[handle.index] == 0 {
			brazier.progress = 0
			continue
		}
		brazier.progress += kindling[handle.index]
		if brazier.progress >= BRAZIER_LIGHT_TICKS do light_brazier(t, handle, first[handle.index])
	}
}

// `brazier` lights, lit by `player`: it stays lit, its gate counts it (gates.odin), and on a crypt floor the next surge
// comes within BRAZIER_SURGE_S (a boss floor's wards keep their own pace: boss.odin). Whoever was kindling it stops (it
// is no longer a target), unless another unlit brazier is in range: they carry on there, Interact still held.
light_brazier :: proc(t: ^Tick, handle: sim.Handle(Brazier), player: sim.Player) {
	brazier := sim.get(&t.state.braziers, handle)
	brazier^ = {
		lit_at = t.time,
		by     = player,
		lit    = true,
	}
	soon := t.time + sim.Game_Time(BRAZIER_SURGE_TICKS)
	if !boss_floor(t) && t.state.surge.target > soon do t.state.surge.target = soon // a timer already done stays done
	defs := sim.slice(&floor_of(t).places.braziers)
	at := sim.Position(defs[handle.index].pos)
	sim.emit(t, Event_Brazier{brazier = handle, position = at, player = player, lit = true})
	heroes := sim.iterate_present(t)
	for hero, other in sim.next(&heroes) {
		if hero.action == .Kindle && kindle_target(&t.state.players, &t.state.braziers, defs, other) == {} {
			hero.action, hero.action_started = .None, t.time
		}
	}
}

// A fireball, `caster`'s, burst at `at` (on the floor): every unlit brazier within BRAZIER_BLAST of it on the floor
// plan lights, unless a wall stands between, met by a ray from the blast's `heart` toward the brazier at the same
// height that stops BRAZIER_STAND short of its foot (the stand itself is a wall to rays).
fireball_lights :: proc(t: ^Tick, at, heart: [3]f32, caster: sim.Player) {
	if t.state.braziers.count == 0 do return
	defs := sim.slice(&floor_of(t).places.braziers)
	walk := sim.iterate(&t.state.braziers)
	for brazier, handle in sim.next(&walk) {
		pos := defs[handle.index].pos
		apart := dmath.length(pos.xz - at.xz)
		if brazier.lit || apart > BRAZIER_BLAST do continue
		if apart > BRAZIER_STAND {
			toward := [3]f32{pos.x, heart.y, pos.z} - heart
			ray := toward * ((apart - BRAZIER_STAND) / apart)
			if _, walled := physics.world_cast_ray_closest(t.world.phys, heart, ray, SIGHT_FILTER); walled do continue
		}
		light_brazier(t, handle, caster)
	}
}

// Every lit brazier goes out, each announced, and every one's progress is lost (the boss's stage: boss.odin).
douse_braziers :: proc(t: ^Tick) {
	defs := sim.slice(&floor_of(t).places.braziers)
	walk := sim.iterate(&t.state.braziers)
	for brazier, handle in sim.next(&walk) {
		was_lit := brazier.lit
		brazier^ = {}
		if !was_lit do continue
		at := sim.Position(defs[handle.index].pos)
		sim.emit(t, Event_Brazier{brazier = handle, position = at, lit = false})
	}
}

// How many braziers are lit; with a `gate` (its index among the floor's gates, >= 0), how many of those that work it.
braziers_lit :: proc(t: ^Tick, gate: i32 = -1) -> (lit: i32) {
	defs := sim.slice(&floor_of(t).places.braziers)
	walk := sim.iterate(&t.state.braziers)
	for brazier, handle in sim.next(&walk) {
		if gate < 0 || defs[handle.index].gate == gate do lit += i32(brazier.lit)
	}
	return
}
