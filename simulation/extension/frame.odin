package crypt_crew_extension

import "unified:godot"
import "unified:sim"

import g "../crypt_crew"

Frame :: godot.Frame(g.Game, View, MultiView)

// The scene views, a struct per kind: what its view's script reads as `data` (ViewPlayer).
View :: union {
	View_Player,
}

MultiView :: enum u8 {
	Ball,
}

PLAYER_COLORS := [g.PLAYERS]godot.Color {
	{1, 0.4, 0.4, 1},
	{0.7, 1, 0.4, 1},
	{0.4, 1, 1, 1},
	{0.7, 0.4, 1, 1},
}

GONE_COLOR :: godot.Color{0.5, 0.5, 0.5, 1}

View_Player :: struct {
	color: godot.Color,
}

Data :: union {
	Data_Hud,
}

Data_Hud :: struct {
	players: u32,
	balls:   u32,
	color:   godot.Color,
	paused:  bool, // the co-op pause (the State's Clock)
	_pad:    [3]u8,
}

// The views of a published tick, from its state (the newest prediction, filled again after a rollback): reads the
// state, never writes it. What a view shows of the rules' next move calls the sim's own proc, or the two disagree
// (unified/docs/gameplay.md).
fill_frame :: proc(f: ^Frame) {
	fill_frame_players(f)
	fill_frame_balls(f)
	fill_frame_hud(f)
}

// A capsule per present player. Nothing here teleports; a body that does pushes its warp epoch
// (`warp = physics.body_warp(f.world.phys, body)`), or its view glides across the map (unified/docs/gameplay.md).
fill_frame_players :: proc(f: ^Frame) {
	players := sim.iterate_present(&f.state.players)
	for data, player in sim.next(&players) {
		slot := sim.player_slot(&f.state.players, player)
		godot.push_view(f, player, {pos = sim.position_floor(data.position)}, View_Player{color = PLAYER_COLORS[slot]})
	}
}

fill_frame_balls :: proc(f: ^Frame) {
	balls := sim.iterate(&f.state.balls)
	for ball, handle in sim.next(&balls) {
		godot.push_multi_view(f, {
			key   = sim.handle_key(handle),
			kind  = .Ball,
			pos   = sim.position_floor(ball.pos, ball.height),
			color = player_color(f, ball.thrower),
		})
	}
}

fill_frame_hud :: proc(f: ^Frame) {
	godot.push_data(f, Data_Hud {
		players = u32(sim.present_count(&f.state.players)),
		balls   = u32(f.state.balls.count),
		color   = player_color(f, f.local_players[0]),
		paused  = f.state.clock.paused,
	})
}

player_color :: proc(f: ^Frame, player: sim.Player) -> godot.Color {
	slot, present := sim.player_slot(&f.state.players, player)
	return PLAYER_COLORS[slot] if present else GONE_COLOR
}
