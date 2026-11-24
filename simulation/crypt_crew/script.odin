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
SCRIPT_PAUSE_EVERY :: 512 // ticks between the scripted co-op pauses (slot 0's)
SCRIPT_PAUSE_AT :: 300 // the tick in each SCRIPT_PAUSE_EVERY a pause starts
SCRIPT_PAUSE_TICKS :: 40 // how long one lasts

// The player in `slot` walks one of 8 directions or stands (a draw every SCRIPT_PERIOD ticks), aims one of 8
// directions or none (another draw), holds Attack in bursts and presses Interact now and then.
scripted_input :: proc(seed: u64, slot: int, tick: u32, state: ^State) -> Input {
	bits := sim.script_bits(seed, slot, tick, SCRIPT_PERIOD)
	input: Input
	if step := bits % 9; step < 8 { 	// the ninth: stand still
		input.move_x, input.move_z = dmath.axis_i8(dmath.DIR8[step].x), dmath.axis_i8(dmath.DIR8[step].y)
	}
	if (bits >> 8) % 3 != 0 do input.aim = dmath.dir2(dmath.DIR8[(bits >> 12) % 8]) // a third of the time: no aim
	phase := tick + u32(slot) * SCRIPT_SLOT_OFFSET
	if phase % SCRIPT_ATTACK_EVERY < SCRIPT_ATTACK_TICKS do input.buttons += {.Attack}
	if phase % SCRIPT_INTERACT_EVERY < SCRIPT_INTERACT_TICKS do input.buttons += {.Interact}
	return input
}

// Slot 0 pauses the game for SCRIPT_PAUSE_TICKS of every SCRIPT_PAUSE_EVERY, so the standard scenarios cover the
// co-op pause.
scripted_commands :: proc(seed: u64, slot: int, tick: u32, state: ^State, out: ^sim.Command_Out(Command)) {
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
