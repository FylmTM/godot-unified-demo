package crypt_crew

import "unified:dmath"
import "unified:sim"

MOVE_SPEED :: f32(4) // metres per second at full input

// Someone new starts at x = their slot; someone who comes back keeps their position. Everything a player owns is
// keyed by their sim.Player, never the slot: who comes back may hold another slot (unified/docs/gameplay.md).
place_new_players :: proc(t: ^Tick) {
	for player in t.player_changes.joined {
		slot := sim.player_slot(t, player)
		player_data := sim.player_data(t, player)
		player_data.position = {f32(slot), 0}
	}
}

// Each present player moves at up to MOVE_SPEED in its stick's direction.
move_players :: proc(t: ^Tick) {
	players := sim.iterate_present(t)
	for data, player in sim.next(&players) {
		input := sim.input(t, player)

		move := dmath.stick(input.dx, input.dy) // each axis -1..1, at most 1 long
		data.position += move * (MOVE_SPEED * t.dt)
	}
}
