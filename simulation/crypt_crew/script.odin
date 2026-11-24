// The scripted player, for the headless modes, the tests and Godot's `--scripted` sessions: pure functions of (seed,
// slot, tick), so any tick can be asked for in any order and every client of a session, every offline run and a Godot
// scripted session play the same players. It exercises every control the rules read.
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
SCRIPT_PAUSE_EVERY :: 512 // ticks between the scripted co-op pauses (slot 0's)
SCRIPT_PAUSE_AT :: 300 // the tick in each SCRIPT_PAUSE_EVERY a pause starts
SCRIPT_PAUSE_TICKS :: 40 // how long one lasts

// The player in `slot` walks one of 8 directions or stands (a draw every SCRIPT_PERIOD ticks), aims one of 8
// directions at a reach, or none (other draws), holds Attack in bursts and presses Interact now and then.
scripted_input :: proc(seed: u64, slot: int, tick: u32, state: ^State) -> Input {
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
	if phase % SCRIPT_ATTACK_EVERY < SCRIPT_ATTACK_TICKS do input.buttons += {.Attack}
	if phase % SCRIPT_INTERACT_EVERY < SCRIPT_INTERACT_TICKS do input.buttons += {.Interact}
	return input
}

// Every slot changes its hero's class once every SCRIPT_CLASS_EVERY ticks (`Any` among the classes, which leaves it),
// slot 1 raises minions around its hero and slot 2 kills every minion now and then (the attacks' stand-ins until
// they land), and slot 0 pauses the game for SCRIPT_PAUSE_TICKS of every SCRIPT_PAUSE_EVERY, so the standard scenarios
// roll back over all of it.
scripted_commands :: proc(seed: u64, slot: int, tick: u32, state: ^State, out: ^sim.Command_Out(Command)) {
	if (tick + u32(slot) * SCRIPT_SLOT_OFFSET) % SCRIPT_CLASS_EVERY == SCRIPT_CLASS_AT {
		sim.send_command(out, Command_Dev_Set_Class{Class((tick / SCRIPT_CLASS_EVERY + u32(slot)) % len(Class))})
	}
	if slot == 1 && tick % SCRIPT_SPAWN_EVERY == SCRIPT_SPAWN_AT {
		sim.send_command(out, Command_Dev_Spawn_Minions{SCRIPT_SPAWN_COUNT})
	}
	if slot == 2 && tick % SCRIPT_KILL_EVERY == SCRIPT_KILL_AT do sim.send_command(out, Command_Dev_Kill_Minions{})
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
