package crypt_crew_extension

import "unified:dmath"
import "unified:godot"

import g "../crypt_crew"

sample_input :: proc(_: int, input: ^g.Input) {
	move := godot.action_vector("ui_left", "ui_right", "ui_up", "ui_down")
	input.dx = dmath.axis_i8(move.x)
	input.dy = dmath.axis_i8(move.y)
}
