// The bot: a player that reads the state, for the playthrough test (the_bot_plays_three_minutes: a copy of g.GAME
// with these as its scripted_input and scripted_commands). Not the game's own scripted player (g.scripted_input): a
// session samples another tick's state than an offline run, so their inputs would differ. In order of what it cares
// about: it throws what it carries (a prop, or the body a Barbarian heaves) at the skeletons; it goes to a downed ally
// within BOT_RESCUE_REACH and revives it; a Barbarian walks up to an elite within BOT_HEAVE_REACH and heaves it; in every
// other BOT_PROP_WINDOW it picks up a prop beside it that no wall hides; with no skeleton near, it picks up the coins
// within BOT_COIN_REACH; and it fights the nearest skeleton (walking up to a melee class's reach, standing off at a
// caster's range), using its class's ability now and then: the Knight blocks and charges, the Rogue rolls back from a
// skeleton at hand, the Mage lobs its fireball at the nearest whenever it is ready. It reads only the state it is given
// and, for the props' bodies, the test's World (bot_world), so it is a valid input source for any run of that World.
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
// BOT_DOWN_EVERY, for the others to revive.
bot_commands :: proc(seed: u64, slot: int, tick: u32, state: ^g.State, _: g.Setup, out: ^sim.Command_Out(g.Command)) {
	if slot == 0 && tick % BOT_SPAWN_EVERY == BOT_SPAWN_EVERY / 2 {
		sim.send_command(out, g.Command_Dev_Spawn_Minions{BOT_SPAWN_COUNT})
	}
	if slot == 1 && tick % BOT_ELITE_EVERY == BOT_ELITE_AT {
		sim.send_command(out, g.Command_Dev_Spawn_Elite{g.Elite_Kind(tick / BOT_ELITE_EVERY % len(g.Elite_Kind))})
	}
	if slot == 3 && tick % BOT_DOWN_EVERY == BOT_DOWN_AT do sim.send_command(out, g.Command_Dev_Hurt{damage = g.HERO_HP})
}

// The way along the floor from `from` to `to` (on the floor plan, unit): the floor's navigation steered toward `to`
// (the World's memoized field of its polygon, as a minion steers), or straight at it off the mesh. It walks round
// walls, which a straight line to an ally in the next room would press into.
@(private = "file")
way :: proc(state: ^g.State, from, to: [3]f32) -> [2]f32 {
	floor := &bot_world.floors[state.level.id]
	start, on := g.floor_spot(floor, from, g.HERO_NAV_REACH)
	goal, there := g.floor_spot(floor, to, g.HERO_NAV_REACH)
	if !on || !there do return to.xz - from.xz
	next := nav.steer(&floor.mesh, nav.field(&floor.fields, goal.poly), start.poly, start.point, goal.point)
	return (next - start.point).xz
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
