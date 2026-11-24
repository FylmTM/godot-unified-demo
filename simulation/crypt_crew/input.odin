// What a player sends: the Input (the controls held, read again on every repeat) and the commands (each a one-shot,
// delivered once). Prediction repeats an input and the relay replaces a late one, so a tap never goes in the Input:
// a press is a `buttons` edge (sim.buttons), anything else a command (unified/docs/gameplay.md).
package crypt_crew

import "unified:dmath"
import "unified:sim"

REACH_STEP :: f32(0.25) // metres per step of Input.reach

// A button a player holds.
Button :: enum u8 {
	Attack, // held: the hero's class attacks; its press throws what the hero carries instead
	Interact, // its press grabs a prop, or drops the one carried
}

// The buttons a player holds (sim.buttons derives the presses from the tick before).
Buttons :: bit_set[Button;u8]

// One player's input for one tick, 8 bytes. Directions are the world's XZ plane, which needs no camera: the camera
// never turns.
Input :: struct {
	move_x:  i8, // the stick toward +X, -127..127 (dmath.axis_i8)
	move_z:  i8, // toward +Z (down the screen)
	buttons: Buttons,
	seen:    sim.Seen, // how late the picture the player acted on was (the host stamps it): where a crossbow looks back to
	aim:     dmath.Dir2, // where the hero looks, (x, z); none: it faces its move
	// How far from the hero the aim points, in REACH_STEPs (reach_steps; 0: no point): where a throw or a ground-targeted
	// cast lands. No rule reads it yet; it is in the Input now so the layout stays put when one does.
	reach:   u8,
	_pad:    u8,
}
#assert(size_of(Input) == 8)

// A distance from the hero as Input.reach: whole REACH_STEPs, at least one for any distance (0 is no point), at most
// 255. Client side (the sampler, the script).
reach_steps :: proc(metres: f32) -> u8 {
	if !(metres > 0) do return 0
	return u8(dmath.to_i32_clamped(dmath.round(metres / REACH_STEP), 1, 255))
}

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

// `dev_spawn_minions` (dev builds): `count` minions rise around the sender's hero (at most up to MINION_CAP alive).
Command_Dev_Spawn_Minions :: struct {
	count: u8,
}

// `dev_hurt` (dev builds): `player`'s hero (0: the sender's own) takes `damage`, as from a minion's swing.
Command_Dev_Hurt :: struct {
	player: sim.Player,
	damage: i16,
}

// `dev_kill_minions` (dev builds): every live minion takes MINION_HP (a killing blow) from the sender, knocked away
// from its hero.
Command_Dev_Kill_Minions :: struct {}

// Every command a player can send.
Command :: union {
	Command_Set_Paused,
	Command_Dev_Set_Class,
	Command_Dev_Spawn_Minions,
	Command_Dev_Hurt,
	Command_Dev_Kill_Minions,
}
