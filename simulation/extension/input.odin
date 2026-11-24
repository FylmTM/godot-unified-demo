// The input (main thread, once a frame per local player): the InputMap's actions on the player's own device (a couch
// player's pad, or the keyboard and mouse) become an Input. Twin-stick: the left stick or the keys move, the right
// stick or the mouse aim. Only scripts know where the mouse points on the floor (the camera's ray), so play.gd sets
// that as an input value.
package crypt_crew_extension

import "unified:dmath"
import "unified:godot"

import g "../crypt_crew"

// What game/play/play.gd sets for the local player on the keyboard, on the session's input_wanted
// (Unified.input.aim): this frame's sample takes it.
Input_Values :: struct {
	aim: [2]f32, // (x, z): from the hero toward the mouse on the floor; zero: the mouse doesn't aim
}

// The move from the move actions, the buttons held (a tap shorter than a frame still counts: action_down), and the
// aim: the right stick of the player's device, else for the keyboard's player the mouse; none: the hero faces its move.
sample_input :: proc(local: int, input: ^g.Input) {
	move := godot.action_vector("move_left", "move_right", "move_up", "move_down") // y "back": +Z, down the screen
	input.move_x, input.move_z = dmath.axis_i8(move.x), dmath.axis_i8(move.y)
	input.buttons = godot.buttons(g.Buttons, {.Attack = "attack", .Interact = "interact"})
	aim := godot.action_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if aim == {} && godot.local_device(local) < 0 do aim = godot.input_values(Input_Values).aim // no pad of its own
	input.aim = dmath.dir2(aim)
}
