// The view contract and the frame (session thread): every view the state shows, filled for each published tick from
// its state (the newest prediction, filled again after a rollback). It reads the state and never writes it; what a
// view shows of the rules' next move calls the sim's own proc, so the two cannot disagree (unified/docs/gameplay.md).
package crypt_crew_extension

import "unified:dmath"
import "unified:godot"
import "unified:sim"

import g "../crypt_crew"

// What fill_frame gets: the tick's state and world, and where the views go.
Frame :: godot.Frame(g.Game, View, MultiView)

// The scene views, a struct per kind: what its view's script reads as `data` (ViewHero). A hero's is keyed by its
// player (sim.player_key).
View :: union {
	View_Hero,
}

// No MultiMesh views yet.
MultiView :: enum u8 {}

// A hero, posed at its feet and turned to its facing. Its animation is a function of this data (game/views/hero.gd):
// a one-shot action at its age, else a gait picked from its velocity in its own frame.
View_Hero :: struct {
	velocity:       [2]f32, // metres per second in the hero's frame: x to its right, y ahead
	action_started: sim.Game_Time, // when `action` began: the clip time is (shown_time - action_started) / tick_hz
	hp:             i16,
	class:          g.Class, // EnumClass: which character the view shows
	action:         g.Action, // EnumAction
	slot:           u8, // the input slot its player holds
	_pad:           [3]u8,
}

// Every present hero, then the HUD's data.
fill_frame :: proc(f: ^Frame) {
	heroes := sim.iterate_present(&f.state.players)
	for hero, player in sim.next(&heroes) {
		facing := shown_facing(f, hero, player)
		right := [2]f32{-facing.y, facing.x} // a model faces +Z: its right is -X
		slot, _ := sim.player_slot(&f.state.players, player)
		godot.push_view(f, player, {
			pos  = sim.Position(hero.pos),
			rot  = dmath.quat_yaw(facing),
			warp = hero.warp,
		}, View_Hero {
			velocity       = {dmath.dot(hero.vel.xz, right), dmath.dot(hero.vel.xz, facing)},
			action_started = hero.action_started,
			hp             = hero.hp,
			class          = hero.class,
			action         = hero.action,
			slot           = u8(slot),
		})
	}
	fill_hud(f)
}

// Where a hero is shown looking: a local hero turns with its newest input sample at once (the rules' own hero_facing on
// Frame.local_inputs, ahead of the state by the input delay), every other hero as the state has it. Paused, nobody
// turns.
shown_facing :: proc(f: ^Frame, hero: ^g.Hero, player: sim.Player) -> [2]f32 {
	if f.state.clock.paused do return hero.facing
	for local_player, local in f.local_players {
		if local_player == player do return g.hero_facing(f.local_inputs[local], hero.facing)
	}
	return hero.facing
}
