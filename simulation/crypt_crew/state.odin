package crypt_crew

import "unified:sim"

// The whole simulation state: one pointer-free block (checked by sim.create). Everything tick reads across ticks lives
// here: kept anywhere else (the World, a package variable), it desyncs after a rollback (unified/docs/gameplay.md).
State :: struct {
	clock:   sim.Clock, // game time and the co-op pause (pause.odin): the harness advances it unless paused
	players: sim.Players(Player_Data, sim.No_Profile, Input, PLAYERS),
	balls:   sim.Table(Ball, MAX_BALLS),
}

// A player's data (the State's sim.Players): zeroed for someone new, kept while they are away.
Player_Data :: struct {
	position:    [2]f32,
	throw_ready: sim.Timer, // no throw until it runs out (THROW_COOLDOWN_S): on game time, so it waits out a pause
}

// A ball in the air: its ground position, height and vertical speed, and who threw it (who may have left).
Ball :: struct {
	pos:            [2]f32,
	height:         f32,
	vertical_speed: f32,
	thrower:        sim.Player,
}
