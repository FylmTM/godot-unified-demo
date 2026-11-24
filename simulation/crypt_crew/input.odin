package crypt_crew

import "unified:sim"

// One player's input for one tick: the stick, each axis -127..127 (dmath.axis_i8). The controls' state, never a
// one-shot (prediction repeats an input, the relay replaces a late one: a tap is lost or repeats): a button is a
// held bit in a `buttons` bit_set (sim.buttons), a one-shot a command (unified/docs/gameplay.md).
Input :: struct {
	dx: i8, // right
	dy: i8, // down
}

// A tick's inputs and commands, by slot.
Inputs :: sim.Inputs(Game)

THROW_SPEED_MAX :: 8 // metres per second: a faster throw is thrown at this speed

// `throw_ball` (GDScript: CommandThrowBall): the sender throws a ball straight up at `speed` metres per second.
Command_Throw_Ball :: struct {
	speed: u8,
}

// `set_paused` (GDScript: CommandSetPaused): pauses or resumes the game for everyone. A value, not a toggle, so two
// players pausing at once agree.
Command_Set_Paused :: struct {
	paused: bool,
}

// Every command a player can send.
Command :: union {
	Command_Throw_Ball,
	Command_Set_Paused,
}
