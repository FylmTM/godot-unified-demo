package crypt_crew

import "unified:sim"

MAX_BALLS :: 16 // two players throwing at once fill the table: a throw is lost then
GRAVITY :: f32(9.8) // metres per second squared, down
HAND_HEIGHT :: f32(1.8) // where a ball leaves the player, metres above the ground
BALL_RADIUS :: f32(0.2) // metres: a ball is gone when its centre is this low

THROW_COOLDOWN_S :: f32(0.25) // seconds of game time between a player's throws

// Each present player's `Command_Throw_Ball` throws a ball.
throw_balls :: proc(t: ^Tick) {
	players := sim.iterate_present(t)
	for _, player in sim.next(&players) {
		for sent in sim.commands(t, player) {
			throw := sent.(Command_Throw_Ball) or_continue
			throw_ball(t, player, throw.speed)
		}
	}
}

// A ball from `player`'s position, owned by them, once their THROW_COOLDOWN_S since the last throw ran out (else the
// throw is dropped). With MAX_BALLS in the air it is lost, costs no cooldown, and no event says so.
throw_ball :: proc(t: ^Tick, player: sim.Player, speed: u8) {
	data := sim.player_data(t, player)
	if sim.timer_running(t, data.throw_ready) do return
	ball, _, ok := sim.spawn(&t.state.balls)
	if !ok do return
	sim.timer_start(t, &data.throw_ready, THROW_COOLDOWN_S)
	capped := speed if speed <= THROW_SPEED_MAX else THROW_SPEED_MAX
	ball^ = {
		pos            = data.position,
		height         = HAND_HEIGHT,
		vertical_speed = f32(capped),
		thrower        = player,
	}
	sim.emit(t, Event_Ball_Thrown{player = player, speed = capped})
}

// Balls fall at GRAVITY; a ball whose centre is BALL_RADIUS or less above the ground despawns.
move_balls :: proc(t: ^Tick) {
	balls := sim.iterate(&t.state.balls)
	for ball, handle in sim.next(&balls) {
		ball.vertical_speed -= GRAVITY * t.dt
		ball.height += ball.vertical_speed * t.dt
		if ball.height <= BALL_RADIUS do sim.despawn(&t.state.balls, handle)
	}
}
