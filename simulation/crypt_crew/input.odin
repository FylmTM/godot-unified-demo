// What a player sends: the Input (the controls held, read again on every repeat) and the commands (each a one-shot,
// delivered once). Prediction repeats an input and the relay replaces a late one, so a tap never goes in the Input:
// a press is a `buttons` edge (sim.buttons), anything else a command (unified/docs/gameplay.md).
package crypt_crew

import "unified:dmath"
import "unified:sim"

// A button a player holds.
Button :: enum u8 {
	Attack, // read held: an attack repeats on the class's cooldown
	Interact, // read by its press: grab, drop, revive
}

// The buttons a player holds (sim.buttons derives the presses from the tick before).
Buttons :: bit_set[Button;u8]

// One player's input for one tick, 6 bytes. Directions are the world's XZ plane, which needs no camera: the camera
// never turns.
Input :: struct {
	move_x:  i8, // the stick toward +X, -127..127 (dmath.axis_i8)
	move_z:  i8, // toward +Z (down the screen)
	buttons: Buttons,
	seen:    sim.Seen, // how late the picture the player acted on was (the host stamps it): where a crossbow looks back to
	aim:     dmath.Dir2, // where the hero looks, (x, z); none: it faces its move
}
#assert(size_of(Input) == 6)

// A tick's inputs and commands, by slot.
Inputs :: sim.Inputs(Game)

// What a player chose before joining (sim's Profile): their hero's class. `--profile class=mage` picks one.
Profile :: struct {
	class: Class,
}

// A hero's class. `Any` (the zero, what a Profile asks for by default) resolves on arrival to a class nobody plays.
Class :: enum u8 {
	Any,
	Knight,
	Barbarian,
	Mage,
	Rogue,
}

// `set_paused` (GDScript: CommandSetPaused): pauses or resumes the game for everyone. A value, not a toggle, so two
// players pausing at once agree.
Command_Set_Paused :: struct {
	paused: bool,
}

// `dev_set_class` (dev builds): the sender's hero becomes `class` (`Any`: it stays as it is).
Command_Dev_Set_Class :: struct {
	class: Class,
}

// Every command a player can send.
Command :: union {
	Command_Set_Paused,
	Command_Dev_Set_Class,
}
