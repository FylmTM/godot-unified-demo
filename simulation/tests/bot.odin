// The bot: a player that reads the state, for the playthrough test (the_bot_plays_three_minutes: a copy of g.GAME
// with these as its scripted_input and scripted_commands). Not the game's own scripted player (g.scripted_input): a
// session samples another tick's state than an offline run, so their inputs would differ. In order of what it cares
// about: it throws what it carries (a prop, or the body a Barbarian heaves) at the skeletons; it goes to a downed
// ally within BOT_RESCUE_REACH and revives it; it does its part of the floor's way out (bot_duty: two stand on the
// vault's plates until its gate is open, the Mage fireballs the barricade, the Knight drags the hoard to the lift, and
// once the hoard is aboard everyone walks onto the deck; at the bottom each picks a boon, bot_commands); a Barbarian
// walks up to an elite within BOT_HEAVE_REACH and heaves it;
// in every other BOT_PROP_WINDOW it picks up a prop beside it that no wall hides; with no skeleton near, it picks up
// the coins within BOT_COIN_REACH; and it fights the nearest skeleton (walking up to a melee class's reach, standing
// off at a caster's range), using its class's ability now and then: the Knight blocks and charges, the Rogue rolls
// back from a skeleton at hand, the Mage lobs its fireball at the nearest whenever it is ready. It reads only the
// state it is given and, for the props' bodies, the test's World (bot_world), so it is a valid input source for any
// run of that World.
package test_crypt_crew

import "unified:dmath"
import "unified:nav"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

BOT_RANGED_STANDOFF :: f32(7) // a Mage or a Rogue attacks from this far (m)
BOT_MELEE_STANDOFF :: f32(1.4) // a Knight or a Barbarian walks this close (m)
BOT_SIGHT :: f32(14) // the bot fights skeletons this close; farther, it walks toward the nearest (m)
BOT_GRAB_REACH :: f32(1.6) // a free prop this close (its centre to the hero's) is worth picking up (m)
BOT_GRAB_EVERY :: 8 // the bot presses Interact (or a Barbarian Ability) one tick in this many while it wants to grab
BOT_THROW_EVERY :: 4 // and Attack one tick in this many while it carries something
BOT_PROP_WINDOW :: 128 // ticks: the bot wants props in every other window of this many, and fights in the others
BOT_RESCUE_REACH :: f32(16) // a downed ally this close is revived before anything but a throw (m)
BOT_HEAVE_REACH :: f32(8) // a Barbarian heaves an elite this close (m)
BOT_COIN_REACH :: f32(12) // with no skeleton within half its sight, the bot picks up the coins this close (m)
BOT_ABILITY_NEAR :: f32(2.5) // the Knight blocks and charges, and the Rogue rolls, at a skeleton this close (m)
BOT_ABILITY_WINDOW :: 64 // ticks: the Knight blocks in one window of this many in three, and swings in the others
BOT_ROLL_EVERY :: 16 // the Rogue presses Ability one tick in this many while a skeleton is at hand
BOT_SPAWN_EVERY :: 640 // ticks between slot 0's dev spawns that keep skeletons coming
BOT_SPAWN_COUNT :: 6
BOT_ELITE_EVERY :: 960 // ticks between slot 1's dev elites (the kinds in turn), ahead of the Barbarian it plays
BOT_ELITE_AT :: 200
BOT_DOWN_EVERY :: 1280 // ticks between slot 3's dev downing of its own hero, for the others to revive
BOT_DOWN_AT :: 900
BOT_PLATE_SLOTS :: [2]int{1, 2} // the Barbarian and the Mage stand on the vault gate's plates, in plate order ...
BOT_BLAST_SLOT :: 2 // ... the Mage, once off its plate, fireballs the barricade ...
BOT_HAUL_SLOT :: 0 // ... and the Knight drags the hoard to the lift
BOT_BLAST_STAND :: f32(2.5) // the Mage casts at the barricade from this far in front of it (m)
BOT_ON_SPOT :: f32(0.3) // a bot this close to where it is going stands still there (m)
BOT_LIFT_WAIT :: f32(2.8) // with the hoard on its way, a bot waits this far out from the deck's middle, by its corner
BOT_THROUGH :: f32(2) // a hauler goes this far straight out of the vault's gate before it heads for the lift (m)
BOT_STUCK_SPEED :: f32(0.3) // a hauler walking slower than this is caught on something (m/s) ...
BOT_UNSTICK :: u32(48) // ... and works round it to each side in turn, this many ticks each
BOT_TRAP_STEP :: f32(0.9) // a bot looks this far ahead along its way for a trap (m) ...
BOT_SPIKES_AHEAD :: u32(48) // ... and waits for spikes that rise within this many ticks (a crossing's time and more)
BOT_ROLLER_BERTH :: f32(0.3) // ... and for a roller whose sides are this near (m)
BOT_FENCE_BERTH :: f32(1.5) // a standing barricade is in the way of a line crossing this far past its ends too (m)

// The World whose props' bodies the bot looks at (the state holds only their refs): the test's sim's.
@(thread_local)
bot_world: ^g.World

// The input of the bot in `slot` (zero when nobody holds it or its hero is down), a sim.Game.scripted_input.
bot_input :: proc(seed: u64, slot: int, tick: u32, state: ^g.State, _: g.Setup) -> (input: g.Input) {
	hero := sim.slot_data(&state.players, slot)
	if hero == nil || hero.action == .Down || hero.body == {} do return
	target, distance, found := nearest_minion(state, hero.pos.xz)
	if found {
		input.aim = dmath.dir2(dmath.normalize(target - hero.pos.xz))
		input.reach = g.reach_steps(distance) // where a Mage's fireball lands: on it
	}
	if hero.held != {} || hero.action == .Heave { 	// at the nearest skeleton, or wherever it faces when none is in sight
		if tick % BOT_THROW_EVERY == 0 do input.buttons += {.Attack}
		return
	}
	if state.lift.phase == .Choosing do return // its boon is a command (bot_commands)
	if ally, near := downed_ally(state, slot, hero.pos.xz); near {
		offset := ally.xz - hero.pos.xz
		input.aim = {}
		// into its reach, then tend it: the first tick in reach is the press that starts the revive
		if dmath.length(offset) > 0.7 * g.REVIVE_RANGE {
			walk(&input, way(state, hero.pos, ally))
		} else {
			input.buttons += {.Interact}
		}
		return
	}
	if bot_duty(&input, state, slot, hero, tick) do return
	if hero.class == .Barbarian {
		if elite, near := nearest_elite(state, hero.pos.xz, BOT_HEAVE_REACH); near {
			offset := elite - hero.pos
			input.aim = dmath.dir2(dmath.normalize(offset.xz)) // face it: a heave takes what is in front
			if dmath.length(offset.xz) > 1.2 do walk(&input, way(state, hero.pos, elite))
			if tick % BOT_GRAB_EVERY == 0 && !sim.timer_running(state.clock.time, hero.ability_ready) {
				input.buttons += {.Ability}
			}
			return
		}
	}
	if (tick / BOT_PROP_WINDOW) % 2 == 0 {
		if prop, near := free_prop_near(state, hero.pos); near {
			input.aim = dmath.dir2(prop - hero.pos.xz) // face it: a grab takes what is in front
			if tick % BOT_GRAB_EVERY == 0 do input.buttons += {.Interact}
			return
		}
	}
	if !found || distance > BOT_SIGHT * 0.5 {
		if coin, near := nearest_coin(state, hero.pos.xz); near {
			walk(&input, way(state, hero.pos, coin))
			return
		}
	}
	if !found do return
	toward := dmath.normalize(target - hero.pos.xz)
	standoff := BOT_MELEE_STANDOFF
	if hero.class == .Mage || hero.class == .Rogue do standoff = BOT_RANGED_STANDOFF
	if distance > standoff do walk(&input, toward)
	if distance < dmath.max(standoff, BOT_SIGHT * 0.5) do input.buttons += {.Attack}
	ready := !sim.timer_running(state.clock.time, hero.ability_ready)
	switch hero.class {
	case .Knight:
		// behind the shield in one window in three; Attack's presses there charge
		if distance < BOT_ABILITY_NEAR && (tick / BOT_ABILITY_WINDOW) % 3 == 0 {
			input.buttons += {.Ability}
			input.buttons -= {.Attack}
			if hero.action == .Block && tick % BOT_THROW_EVERY == 0 do input.buttons += {.Attack}
		}
	case .Rogue:
		// rolls back, away from a skeleton at hand
		if distance < BOT_ABILITY_NEAR && ready && tick % BOT_ROLL_EVERY == 0 {
			input.buttons += {.Ability}
			walk(&input, -toward)
		}
	case .Mage:
		if ready && distance < g.FIREBALL_RANGE do input.buttons += {.Ability}
	case .Barbarian, .Any:
	}
	return
}

// The bot's commands (a sim.Game.scripted_commands): slot 0 raises skeletons around its hero every BOT_SPAWN_EVERY,
// slot 1 an elite ahead of its hero (the kinds in turn) every BOT_ELITE_EVERY, and slot 3 downs its own hero every
// BOT_DOWN_EVERY, for the others to revive; at the lift's bottom each picks its first boon.
bot_commands :: proc(seed: u64, slot: int, tick: u32, state: ^g.State, _: g.Setup, out: ^sim.Command_Out(g.Command)) {
	if hero := sim.slot_data(&state.players, slot); hero != nil && state.lift.phase == .Choosing {
		if !g.has_picked(hero, state.depth) do sim.send_command(out, g.Command_Pick_Boon{0})
		return
	}
	if slot == 0 && tick % BOT_SPAWN_EVERY == BOT_SPAWN_EVERY / 2 {
		sim.send_command(out, g.Command_Dev_Spawn_Minions{BOT_SPAWN_COUNT})
	}
	if slot == 1 && tick % BOT_ELITE_EVERY == BOT_ELITE_AT {
		sim.send_command(out, g.Command_Dev_Spawn_Elite{g.Elite_Kind(tick / BOT_ELITE_EVERY % len(g.Elite_Kind))})
	}
	if slot == 3 && tick % BOT_DOWN_EVERY == BOT_DOWN_AT do sim.send_command(out, g.Command_Dev_Hurt{damage = g.HERO_HP})
}

// The bot's part of the floor's way out, if it has one now (true: `input` is set for it): with the hoard resting on
// the waiting deck, everyone walks to its corner of the deck and stands there; while the vault's gate is shut, the
// BOT_PLATE_SLOTS stand on its plates; while the barricade stands, the BOT_BLAST_SLOT Mage walks up to it and casts at
// it; once the gate is open, the BOT_HAUL_SLOT takes the hoard's Left handle and drags it to the lift (bot_haul),
// and once the gate is open every other bot with no skeleton to fight waits by the lift, off the deck and out of the
// hauler's way.
@(private = "file")
bot_duty :: proc(input: ^g.Input, state: ^g.State, slot: int, hero: ^g.Hero, tick: u32) -> bool {
	phys := bot_world.phys
	places := &bot_world.floors[state.level.id].places
	lift, hoard := &state.lift, &state.hoard
	if lift.body != {} && hoard.body != {} && lift.phase <= .Boarding && hoard.haulers == {} {
		if _, wholly := g.hoard_on_deck(phys, hoard, lift, &bot_world.overlaps); wholly {
			corner := [3]f32{f32(slot & 1) * 2 - 1, 0, f32(slot >> 1) * 2 - 1} * g.LIFT_SLOT_SPREAD
			if go(input, state, hero, physics.body_world_point(phys, lift.body, corner)) do fight_in_place(input, state, hero)
			return true
		}
	}
	if gate, _, found := sim.item_at(&state.gates, 0); found && !gate.open {
		for plate_slot, k in BOT_PLATE_SLOTS {
			if slot == plate_slot && k < int(places.plates.count) {
				if go(input, state, hero, sim.slice(&places.plates)[k].pos) do fight_in_place(input, state, hero)
				return true
			}
		}
	}
	if barricade, _, found := sim.item_at(&state.barricades, 0); found && !barricade.broken && slot == BOT_BLAST_SLOT {
		def := sim.slice(&places.barricades)[0]
		normal := dmath.quat_rotate(def.rot, {0, 0, 1})
		side := f32(1) if dmath.dot(hero.pos - def.pos, normal) >= 0 else -1 // the side it comes from
		stand := def.pos + normal * (side * BOT_BLAST_STAND)
		if !go(input, state, hero, stand) do return true
		input.aim = dmath.dir2(dmath.normalize(def.pos.xz - hero.pos.xz))
		input.reach = g.reach_steps(dmath.length(def.pos.xz - hero.pos.xz))
		if !sim.timer_running(state.clock.time, hero.ability_ready) && tick % BOT_GRAB_EVERY == 0 {
			input.buttons += {.Ability}
		}
		return true
	}
	if gate, _, found := sim.item_at(&state.gates, 0); found && gate.open && slot == BOT_HAUL_SLOT {
		return bot_haul(input, state, hero, tick)
	}
	vault, _, gated := sim.item_at(&state.gates, 0)
	if lift.phase == .Waiting && (hoard.haulers != {} || !gated || vault.open) {
		if _, _, near := nearest_minion(state, hero.pos.xz); !near {
			// the hoard free to go and nothing to fight: wait by the lift, out of the hauler's way (never standing
			// where its duty left it, which may be the doorway the haul comes through)
			corner := [3]f32{f32(slot & 1) * 2 - 1, 0, f32(slot >> 1) * 2 - 1} * BOT_LIFT_WAIT
			go(input, state, hero, physics.body_world_point(phys, lift.body, corner))
			return true
		}
	}
	return false
}

// The hauler's part: the lift waiting and the hoard not yet wholly on its deck, it walks to the hoard's Left handle and
// takes it, then drags the hoard along the floor's way to the deck, onto it and across it toward the far side (the
// chest trailing behind), and lets go once the hoard is wholly aboard. Whether it had anything to do.
@(private = "file")
bot_haul :: proc(input: ^g.Input, state: ^g.State, hero: ^g.Hero, tick: u32) -> bool {
	phys := bot_world.phys
	lift, hoard := &state.lift, &state.hoard
	if lift.body == {} || hoard.body == {} || lift.phase != .Waiting do return false
	_, wholly := g.hoard_on_deck(phys, hoard, lift, &bot_world.overlaps)
	deck := physics.body_position(phys, lift.body)
	chest := physics.body_position(phys, hoard.body)
	if hero.handle == .None {
		if wholly do return false
		handle := g.handle_point(phys, hoard, .Left)
		out := dmath.normalize(handle.xz - chest.xz)
		go(input, state, hero, handle + {out.x, 0, out.y} * 0.7)
		if tick % BOT_GRAB_EVERY == 0 && g.haul_target(phys, hoard, lift, hero) == .Left do input.buttons += {.Interact}
		return true
	}
	if wholly {
		if tick % BOT_GRAB_EVERY == 0 do input.buttons += {.Interact}
		return true
	}
	if g.on_deck(phys, lift, hero.pos) {
		ahead := dmath.normalize(deck.xz - chest.xz) * (g.LIFT_HALF.x - g.HERO_RADIUS)
		go(input, state, hero, deck + {ahead.x, 0, ahead.y})
	} else {
		// along the chest's own way, not the hauler's: a hauler cutting a doorway's corner drags the chest onto it
		toward := way(state, chest, haul_waypoint(state, hero.pos, deck))
		// caught on something (a prop, the fence's debris, a wall's end) and not waiting on a trap: work round it, to
		// one side then the other, a window of BOT_UNSTICK ticks each
		if toward != {} && dmath.length(hero.vel.xz) < BOT_STUCK_SPEED {
			side := f32(1) if (tick / BOT_UNSTICK) % 2 == 0 else -1
			toward = toward + [2]f32{-toward.y, toward.x} * (side * 2)
		}
		walk(input, toward)
	}
	return true
}

// The point BOT_THROUGH in front of the floor's vault gate on `from`'s side of it, and whether the floor has one.
@(private = "file")
gate_front :: proc(state: ^g.State, from: [3]f32) -> (front: [3]f32, ok: bool) {
	places := &bot_world.floors[state.level.id].places
	if places.gates.count == 0 do return
	gate := sim.slice(&places.gates)[0]
	normal := dmath.quat_rotate(gate.rot, {0, 0, 1})
	if dmath.dot(from - gate.pos, normal) < 0 do normal = -normal
	return gate.pos + normal * BOT_THROUGH, true
}

// Where a hauler at `from` bound for the deck at `to` heads now: out through the vault's gate to BOT_THROUGH in front
// of it (straight, so the chest trailing behind never catches on the gate's walls), then the deck along the floor's
// way (through the spikes, waiting for them: trap_ahead). Not by the barricade's shortcut: its fence, broken, lies
// across its gap, and a dragged chest catches on it (docs/review.md).
@(private = "file")
haul_waypoint :: proc(state: ^g.State, from, to: [3]f32) -> [3]f32 {
	places := &bot_world.floors[state.level.id].places
	if places.gates.count == 0 do return to
	gate := sim.slice(&places.gates)[0]
	normal := dmath.quat_rotate(gate.rot, {0, 0, 1})
	toward := f32(1) if dmath.dot(to - gate.pos, normal) > 0 else -1
	if dmath.dot(from - gate.pos, normal) * toward < BOT_THROUGH - BOT_ON_SPOT do return gate.pos + normal * (toward * BOT_THROUGH)
	return to
}

// A bot doing its part where it stands (on a plate, on the deck) swings at, or shoots, the nearest skeleton in its
// reach without stepping off: Attack, aimed at it, and a Mage's fireball whenever it is ready.
@(private = "file")
fight_in_place :: proc(input: ^g.Input, state: ^g.State, hero: ^g.Hero) {
	target, distance, found := nearest_minion(state, hero.pos.xz)
	if !found do return
	reach := BOT_MELEE_STANDOFF
	if hero.class == .Mage || hero.class == .Rogue do reach = BOT_RANGED_STANDOFF
	if distance > reach do return
	input.aim = dmath.dir2(dmath.normalize(target - hero.pos.xz))
	input.reach = g.reach_steps(distance)
	input.buttons += {.Attack}
	if hero.class == .Mage && !sim.timer_running(state.clock.time, hero.ability_ready) do input.buttons += {.Ability}
}

// Walks the bot toward `to` along the floor's way, or stands still once within BOT_ON_SPOT of it: whether it is there.
// While the floor's barricade stands across the straight line there, by way of the vault gate's front on the bot's
// side (gate_front): the navigation knows nothing of a standing barricade, and would walk the bot into it.
@(private = "file")
go :: proc(input: ^g.Input, state: ^g.State, hero: ^g.Hero, to: [3]f32) -> bool {
	if dmath.length(to.xz - hero.pos.xz) < BOT_ON_SPOT do return true
	target := to
	if barricade_between(state, hero.pos, to) {
		if front, gated := gate_front(state, hero.pos); gated do target = front
	}
	walk(input, way(state, hero.pos, target))
	return false
}

// Whether the floor's barricade stands across the straight line from `from` to `to`: the line crosses its fence's line
// within the fence's length and BOT_FENCE_BERTH past either end (the navigation's way there runs through the gap, so
// a line crossing just past the fence's end is in its way too).
@(private = "file")
barricade_between :: proc(state: ^g.State, from, to: [3]f32) -> bool {
	barricade, _, found := sim.item_at(&state.barricades, 0)
	if !found || barricade.broken do return false
	def := sim.slice(&bot_world.floors[state.level.id].places.barricades)[0]
	normal := dmath.quat_rotate(def.rot, {0, 0, 1})
	along := dmath.quat_rotate(def.rot, {1, 0, 0})
	here, there := dmath.dot(from - def.pos, normal), dmath.dot(to - def.pos, normal)
	if here * there >= 0 do return false
	crossing := from + (to - from) * (here / (here - there))
	return abs(dmath.dot(crossing - def.pos, along)) < g.BARRICADE_HALF.x + BOT_FENCE_BERTH
}

// The way along the floor from `from` to `to` (on the floor plan, unit): the floor's navigation steered toward `to`
// (the World's memoized field of its polygon, as a minion steers), or straight at it off the mesh. It walks round
// walls, which a straight line to an ally in the next room would press into. It waits (no way: zero) where its next
// step would take it into a trap's reach (trap_ahead), unless it stands in one already: then it goes on through.
@(private = "file")
way :: proc(state: ^g.State, from, to: [3]f32) -> [2]f32 {
	floor := &bot_world.floors[state.level.id]
	start, on := g.floor_spot(floor, from, g.HERO_NAV_REACH)
	goal, there := g.floor_spot(floor, to, g.HERO_NAV_REACH)
	if !on || !there do return to.xz - from.xz
	next := nav.steer(&floor.mesh, nav.field(&floor.fields, goal.poly), start.poly, start.point, goal.point)
	toward := dmath.normalize((next - start.point).xz)
	if !trap_ahead(state, from) && trap_ahead(state, from + {toward.x, 0, toward.y} * BOT_TRAP_STEP) do return {}
	return toward
}

// Whether a hero at `point` is in a trap's reach now or about to be: over spikes that are up or rise within
// BOT_SPIKES_AHEAD (on the clock: their plates aren't looked at), or within BOT_ROLLER_BERTH of a roller's sides.
@(private = "file")
trap_ahead :: proc(state: ^g.State, point: [3]f32) -> bool {
	defs := sim.slice(&bot_world.floors[state.level.id].places.traps)
	traps := sim.iterate(&state.traps)
	for trap, handle in sim.next(&traps) {
		def := &defs[handle.index]
		switch trap.kind {
		case .Spikes:
			if !g.within_square(def.pos, def.rot, g.SPIKES_HALF + g.HERO_RADIUS, point) do continue
			cycle := (u32(state.clock.time) + def.phase) % g.SPIKES_PERIOD_TICKS
			if trap.up || cycle < g.SPIKES_UP_TICKS || cycle + BOT_SPIKES_AHEAD >= g.SPIKES_PERIOD_TICKS do return true
		case .Roller:
			centre := physics.body_position(bot_world.phys, trap.body)
			if g.within_square(centre, def.rot, g.ROLLER_HALF.x + g.HERO_RADIUS + BOT_ROLLER_BERTH, point) do return true
		}
	}
	return false
}

// The stick toward `offset` (on the floor plan), full.
@(private = "file")
walk :: proc(input: ^g.Input, offset: [2]f32) {
	toward := dmath.normalize(offset)
	input.move_x, input.move_z = dmath.axis_i8(toward.x), dmath.axis_i8(toward.y)
}

// The nearest skeleton alive, asleep ones included, and how far it is.
@(private = "file")
nearest_minion :: proc(state: ^g.State, from: [2]f32) -> (at: [2]f32, distance: f32, found: bool) {
	distance = max(f32)
	minions := sim.iterate(&state.minions)
	for minion in sim.next(&minions) {
		if minion.phase == .Dying do continue
		if apart := dmath.length(minion.pos.xz - from); apart < distance do at, distance, found = minion.pos.xz, apart, true
	}
	return
}

// The nearest ally down within BOT_RESCUE_REACH of `from` that nobody heaves (the bot in `slot` is not its own ally).
@(private = "file")
downed_ally :: proc(state: ^g.State, slot: int, from: [2]f32) -> (at: [3]f32, near: bool) {
	nearest := BOT_RESCUE_REACH
	heroes := sim.iterate_present(&state.players)
	for hero, player in sim.next(&heroes) {
		if player == sim.player_in_slot(&state.players, slot) || hero.action != .Down || hero.heave != .None do continue
		if apart := dmath.length(hero.pos.xz - from); apart < nearest do at, nearest, near = hero.pos, apart, true
	}
	return
}

// The nearest live elite on its feet (awake or asleep, not rising or heaved) within `reach` of `from`.
@(private = "file")
nearest_elite :: proc(state: ^g.State, from: [2]f32, reach: f32) -> (at: [3]f32, near: bool) {
	nearest := reach
	elites := sim.iterate(&state.elites)
	for elite in sim.next(&elites) {
		if elite.phase != .Idle && elite.phase != .Chase && elite.phase != .Attack && elite.phase != .Retreat do continue
		if apart := dmath.length(elite.pos.xz - from); apart < nearest do at, nearest, near = elite.pos, apart, true
	}
	return
}

// The nearest coin within BOT_COIN_REACH of `from`.
@(private = "file")
nearest_coin :: proc(state: ^g.State, from: [2]f32) -> (at: [3]f32, near: bool) {
	nearest := BOT_COIN_REACH
	coins := sim.iterate(&state.loot)
	for coin in sim.next(&coins) {
		if apart := dmath.length(coin.pos.xz - from); apart < nearest do at, nearest, near = coin.pos, apart, true
	}
	return
}

// A prop nobody holds within BOT_GRAB_REACH of a hero at `from`, with no wall between them, where it stands.
@(private = "file")
free_prop_near :: proc(state: ^g.State, from: [3]f32) -> (at: [2]f32, near: bool) {
	props := sim.iterate(&state.props)
	for prop in sim.next(&props) {
		if prop.held_by != {} do continue
		centre := physics.body_position(bot_world.phys, prop.body)
		if dmath.length(centre.xz - from.xz) >= BOT_GRAB_REACH do continue
		chest := from + {0, g.CHEST_HEIGHT, 0}
		if _, walled := physics.world_cast_ray_closest(bot_world.phys, chest, centre - chest, g.REACH_FILTER); walled {
			continue
		}
		return centre.xz, true
	}
	return
}
