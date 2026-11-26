// The scripted player, for the headless modes, the tests and Godot's `--scripted` sessions: pure functions of (seed,
// slot, tick) and the session's Setup (it reads no state), so any tick can be asked for in any order and every client
// of a session, every offline run and a Godot scripted session play the same players. It exercises every control the
// rules read. Under a held crowd (Setup.crowd) it plays the crowd's part instead (director.odin, Crowd).
package crypt_crew

import "unified:dmath"
import "unified:sim"

SCRIPT_PERIOD :: 32 // ticks a scripted move and aim hold
SCRIPT_ATTACK_EVERY :: 96 // ticks from the start of one attack burst to the next
SCRIPT_ATTACK_TICKS :: 24 // how long a burst holds Attack
SCRIPT_INTERACT_EVERY :: 160 // ticks between Interact presses
SCRIPT_INTERACT_TICKS :: 4 // how long one is held
SCRIPT_SLOT_OFFSET :: 16 // ticks each slot's bursts and presses come after the slot before's
SCRIPT_REACH_MIN :: 4 // the nearest a scripted aim points, in REACH_STEPs
SCRIPT_REACH_RANGE :: 40 // and how many steps further it may
SCRIPT_CLASS_EVERY :: 384 // ticks between a slot's dev class changes
SCRIPT_CLASS_AT :: 200 // the tick in each SCRIPT_CLASS_EVERY (plus the slot's offset) one is sent
SCRIPT_SPAWN_EVERY :: 448 // ticks between slot 1's dev minion spawns ...
SCRIPT_SPAWN_AT :: 120 // ... the tick in each a spawn is sent ...
SCRIPT_SPAWN_COUNT :: 4 // ... and how many it raises
SCRIPT_KILL_EVERY :: 576 // ticks between slot 2's dev kills of every minion ...
SCRIPT_KILL_AT :: 450 // ... the tick in each one is sent
SCRIPT_HURT_EVERY :: 704 // ticks between rounds of the dev downing: one slot's hero, every third round all four ...
SCRIPT_HURT_AT :: 360 // ... the tick in each round it is sent
SCRIPT_PAUSE_EVERY :: 512 // ticks between the scripted co-op pauses (slot 0's)
SCRIPT_PAUSE_AT :: 300 // the tick in each SCRIPT_PAUSE_EVERY a pause starts
SCRIPT_PAUSE_TICKS :: 40 // how long one lasts
SCRIPT_DROP_EVERY :: 320 // ticks between slot 1's dev coin drops round its hero ...
SCRIPT_DROP_AT :: 40 // ... the tick in each a drop is sent ...
SCRIPT_DROP_COUNT :: 6 // ... and how many coins it lays: on DEV_DROP_RING, so any walk out of it picks one up

// The player in `slot` walks one of 8 directions or stands (a draw every SCRIPT_PERIOD ticks), aims one of 8
// directions at a reach, or none (other draws), holds Attack in bursts and presses Interact now and then.
// Under a held crowd: standing still (Idle), walking and aiming only (Chase), or holding Attack, let go one tick in
// each SCRIPT_PERIOD so the next is a press (a throw), with Interact's presses (grabs) as in play (Fight).
scripted_input :: proc(seed: u64, slot: int, tick: u32, _: ^State, setup: Setup) -> Input {
	if setup.crowd == .Idle do return {}
	bits := sim.script_bits(seed, slot, tick, SCRIPT_PERIOD)
	input: Input
	if step := bits % 9; step < 8 { 	// the ninth: stand still
		input.move_x, input.move_z = dmath.axis_i8(dmath.DIR8[step].x), dmath.axis_i8(dmath.DIR8[step].y)
	}
	if (bits >> 8) % 3 != 0 { 	// a third of the time: no aim
		input.aim = dmath.dir2(dmath.DIR8[(bits >> 12) % 8])
		input.reach = u8(SCRIPT_REACH_MIN + (bits >> 16) % SCRIPT_REACH_RANGE)
	}
	phase := tick + u32(slot) * SCRIPT_SLOT_OFFSET
	switch setup.crowd {
	case .None:
		if phase % SCRIPT_ATTACK_EVERY < SCRIPT_ATTACK_TICKS do input.buttons += {.Attack}
	case .Idle, .Chase:
		return input
	case .Fight:
		if phase % SCRIPT_PERIOD != 0 do input.buttons += {.Attack}
	}
	if phase % SCRIPT_INTERACT_EVERY < SCRIPT_INTERACT_TICKS do input.buttons += {.Interact}
	return input
}

// Every slot changes its hero's class once every SCRIPT_CLASS_EVERY ticks (`Any` among the classes, which leaves it),
// slot 1 raises minions around its hero and slot 2 kills every minion now and then (so the scenarios cross spawns and
// mass deaths whatever the attacks reach), one slot downs its own hero every SCRIPT_HURT_EVERY (every slot every third time: a wipe and the floor's
// restart), slot 0 pauses the game for SCRIPT_PAUSE_TICKS of every SCRIPT_PAUSE_EVERY, and slot 1 drops coins round its
// hero now and then (so the scenarios cross pickups whatever the kills drop), so the standard scenarios roll back over
// all of it. Under a held crowd, nothing: the population stays what was asked.
scripted_commands :: proc(seed: u64, slot: int, tick: u32, _: ^State, setup: Setup, out: ^sim.Command_Out(Command)) {
	if setup.crowd != .None do return
	if (tick + u32(slot) * SCRIPT_SLOT_OFFSET) % SCRIPT_CLASS_EVERY == SCRIPT_CLASS_AT {
		sim.send_command(out, Command_Dev_Set_Class{Class((tick / SCRIPT_CLASS_EVERY + u32(slot)) % len(Class))})
	}
	if slot == 1 && tick % SCRIPT_SPAWN_EVERY == SCRIPT_SPAWN_AT {
		sim.send_command(out, Command_Dev_Spawn_Minions{SCRIPT_SPAWN_COUNT})
	}
	if slot == 2 && tick % SCRIPT_KILL_EVERY == SCRIPT_KILL_AT do sim.send_command(out, Command_Dev_Kill_Minions{})
	if round := tick / SCRIPT_HURT_EVERY; tick % SCRIPT_HURT_EVERY == SCRIPT_HURT_AT {
		if round % 3 == 2 || int(round) % PLAYERS == slot do sim.send_command(out, Command_Dev_Hurt{damage = HERO_HP})
	}
	if slot == 1 && tick % SCRIPT_DROP_EVERY == SCRIPT_DROP_AT {
		sim.send_command(out, Command_Dev_Drop_Loot{SCRIPT_DROP_COUNT})
	}
	if slot != 0 do return
	switch tick % SCRIPT_PAUSE_EVERY {
	case SCRIPT_PAUSE_AT:
		sim.send_command(out, Command_Set_Paused{true})
	case SCRIPT_PAUSE_AT + SCRIPT_PAUSE_TICKS:
		sim.send_command(out, Command_Set_Paused{false})
	}
}

// The scripted player in slot k plays class k + 1, so the reference run and the scenarios cover every class.
scripted_profile :: proc(seed: u64, slot: int) -> Profile {
	return {class = Class(slot % (len(Class) - 1) + 1)}
}
