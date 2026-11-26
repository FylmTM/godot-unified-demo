// The input (main thread, once a frame per local player): the InputMap's actions on the player's device become an
// Input. Twin-stick: the left stick or the keys move, the right stick or the mouse aim. A couch player's device is its
// pad; the keyboard and mouse are one player's (play.gd says whose); local player 0 reads every device while it plays
// alone, and the one it last played with while a couch guest is in (couch.gd). Only scripts know where the mouse
// points on the floor (the camera's ray), so play.gd sets that as an input value.
package crypt_crew_extension

import "unified:dmath"
import "unified:godot"

import g "../crypt_crew"

// How far a pad's aim reaches with the right stick pushed all the way, in metres: a half push reaches half as far.
PAD_REACH :: f32(10)

// What game/play/play.gd sets, on the session's input_wanted, for the local player who holds the keyboard
// (Unified.local_input(local).aim): this frame's sample takes it.
Input_Values :: struct {
	aim: [2]f32, // (x, z): from the hero to where the mouse points on the floor; zero: the mouse doesn't aim
}

// The move from the move actions, the buttons held (a tap shorter than a frame still counts: action_down), and the
// aim with its reach: the right stick of the player's device, else, for the player who holds the keyboard (or every
// device), the mouse; none: the hero faces its move.
sample_input :: proc(local: int, input: ^g.Input) {
	move := godot.action_vector("move_left", "move_right", "move_up", "move_down") // y "back": +Z, down the screen
	input.move_x, input.move_z = dmath.axis_i8(move.x), dmath.axis_i8(move.y)
	input.buttons = godot.buttons(g.Buttons, {.Attack = "attack", .Interact = "interact", .Ability = "ability"})
	stick := godot.action_vector("aim_left", "aim_right", "aim_up", "aim_down")
	aim := stick * PAD_REACH
	device := godot.local_device(local)
	// the mouse's aim is play.gd's value: honour the dev UI holding the keyboard, as the actions above already do
	if stick == {} && (device == godot.DEVICE_ANY || device == godot.DEVICE_KEYBOARD) && !godot.input_blocked() {
		aim = godot.input_values(Input_Values).aim
	}
	input.aim = dmath.dir2(aim)
	input.reach = input.aim == 0 ? 0 : g.reach_steps(dmath.length(aim))
}
