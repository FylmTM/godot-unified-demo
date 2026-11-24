// The bot: a player that reads the state, for the playthrough test (the_bot_plays_three_minutes: a copy of g.GAME
// with these as its scripted_input and scripted_commands). Not the game's own scripted player (g.scripted_input): a
// session samples another tick's state than an offline run, so their inputs would differ. It fights the nearest
// skeleton (walking up to a melee class's reach, standing off at a caster's range), and now and then picks up a prop
// beside it and throws it at the skeletons. It reads only the state it is given and, for the props' bodies, the
// test's World (bot_world), so it is a valid input source for any run of that World.
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
BOT_THROW_EVERY :: 4 // and Attack one tick in this many while it carries one with a skeleton near
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
	if !found do return
	toward := dmath.normalize(target - hero.pos.xz)
	input.aim = dmath.dir2(toward)
	if hero.held != {} {
		if distance < BOT_SIGHT && tick % BOT_THROW_EVERY == 0 do input.buttons += {.Attack}
		return
	}
	if prop, near := free_prop_near(state, hero.pos.xz); near {
		input.aim = dmath.dir2(prop - hero.pos.xz) // face it: a grab takes what is in front
		if tick % BOT_GRAB_EVERY == 0 do input.buttons += {.Interact}
		return
	}
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

// A prop nobody holds within BOT_GRAB_REACH, where it stands.
@(private = "file")
free_prop_near :: proc(state: ^g.State, from: [2]f32) -> (at: [2]f32, near: bool) {
	props := sim.iterate(&state.props)
	for prop in sim.next(&props) {
		if prop.held_by != {} do continue
		centre := physics.body_position(bot_world.phys, prop.body)
		if dmath.length(centre.xz - from) < BOT_GRAB_REACH do return centre.xz, true
	}
	return
}
