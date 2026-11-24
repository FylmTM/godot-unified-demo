// The bot: a player that reads the state, for the playthrough test (the_bot_plays_three_minutes: a copy of g.GAME
// with these as its scripted_input and scripted_commands). Not the game's own scripted player (g.scripted_input): a
// session samples another tick's state than an offline run, so their inputs would differ. It fights the nearest
// skeleton (walking up to a melee class's reach, standing off at a caster's range), and in every other BOT_PROP_WINDOW
// picks up a prop beside it that no wall hides and throws it at the skeletons, or anywhere when none is near; out of
// that window it gives up on a prop it couldn't grab. It reads only the state it is given and, for the props' bodies,
// the test's World (bot_world), so it is a valid input source for any run of that World.
package test_crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

BOT_RANGED_STANDOFF :: f32(7) // a Mage or a Rogue attacks from this far (m)
BOT_MELEE_STANDOFF :: f32(1.4) // a Knight or a Barbarian walks this close (m)
BOT_SIGHT :: f32(14) // the bot fights skeletons this close; farther, it walks toward the nearest (m)
BOT_GRAB_REACH :: f32(1.6) // a free prop this close (its centre to the hero's) is worth picking up (m)
BOT_GRAB_EVERY :: 8 // the bot presses Interact one tick in this many while it wants a prop
BOT_THROW_EVERY :: 4 // and Attack one tick in this many while it carries one
BOT_PROP_WINDOW :: 128 // ticks: the bot wants props in every other window of this many, and fights in the others
BOT_SPAWN_EVERY :: 640 // ticks between slot 0's dev spawns that keep skeletons coming
BOT_SPAWN_COUNT :: 6

// The World whose props' bodies the bot looks at (the state holds only their refs): the test's sim's.
@(thread_local)
bot_world: ^g.World

// The input of the bot in `slot` (zero when nobody holds it or its hero is down), a sim.Game.scripted_input.
bot_input :: proc(seed: u64, slot: int, tick: u32, state: ^g.State) -> (input: g.Input) {
	hero := sim.slot_data(&state.players, slot)
	if hero == nil || hero.action == .Down || hero.body == {} do return
	target, distance, found := nearest_minion(state, hero.pos.xz)
	if found do input.aim = dmath.dir2(dmath.normalize(target - hero.pos.xz))
	if hero.held != {} { 	// at the nearest skeleton, or wherever it faces when none is in sight
		if tick % BOT_THROW_EVERY == 0 do input.buttons += {.Attack}
		return
	}
	if (tick / BOT_PROP_WINDOW) % 2 == 0 {
		if prop, near := free_prop_near(state, hero.pos); near {
			input.aim = dmath.dir2(prop - hero.pos.xz) // face it: a grab takes what is in front
			if tick % BOT_GRAB_EVERY == 0 do input.buttons += {.Interact}
			return
		}
	}
	if !found do return
	toward := dmath.normalize(target - hero.pos.xz)
	standoff := BOT_MELEE_STANDOFF
	if hero.class == .Mage || hero.class == .Rogue do standoff = BOT_RANGED_STANDOFF
	if distance > standoff {
		input.move_x, input.move_z = dmath.axis_i8(toward.x), dmath.axis_i8(toward.y)
	}
	if distance < dmath.max(standoff, BOT_SIGHT * 0.5) do input.buttons += {.Attack}
	return
}

// The bot's commands (a sim.Game.scripted_commands): slot 0 raises skeletons around its hero every BOT_SPAWN_EVERY.
bot_commands :: proc(seed: u64, slot: int, tick: u32, state: ^g.State, out: ^sim.Command_Out(g.Command)) {
	if slot == 0 && tick % BOT_SPAWN_EVERY == BOT_SPAWN_EVERY / 2 {
		sim.send_command(out, g.Command_Dev_Spawn_Minions{BOT_SPAWN_COUNT})
	}
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
