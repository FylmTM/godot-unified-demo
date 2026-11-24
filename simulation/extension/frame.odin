// The view contract and the frame (session thread): every view the state shows, filled for each published tick from
// its state (the newest prediction, filled again after a rollback). It reads the state and never writes it; what a
// view shows of the rules' next move calls the sim's own proc, so the two cannot disagree (unified/docs/gameplay.md).
package crypt_crew_extension

import "core:slice"
import "unified:dmath"
import "unified:godot"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// What fill_frame gets: the tick's state and world, and where the views go.
Frame :: godot.Frame(g.Game, View, MultiView)

// The scene views, a struct per kind: what its view's script reads as `data` (ViewHero). A hero's is keyed by its
// player (sim.player_key), a prop's by its handle (its events' `prop`).
View :: union {
	View_Hero,
	View_Prop,
}

// No MultiMesh views yet.
MultiView :: enum u8 {}

// A hero, posed at its feet and turned to its facing. Its animation is a function of this data (game/views/hero.gd):
// a one-shot action at its age, else a gait picked from its velocity in its own frame.
View_Hero :: struct {
	velocity:       [2]f32, // metres per second in the hero's frame: x to its right, y ahead
	action_started: sim.Game_Time, // when `action` began: the clip time is (shown_time - action_started) / tick_hz
	class:          g.Class, // EnumClass: which character the view shows
	action:         g.Action, // EnumAction
	carrying:       bool, // it holds a prop
	_pad:           u8,
}

// A prop, posed at the bottom of its body (its model's origin) and turned as its body is; a pooled kind (prop.tscn).
View_Prop :: struct {
	held_by: sim.Player, // the hero carrying it (0: nobody)
	kind:    g.Prop_Kind, // EnumPropKind: which model the view shows
	aimed:   bool, // a local hero's Interact would grab it now (grab_target): the view highlights it
}

// Every present hero, every prop, then the HUD's data.
fill_frame :: proc(f: ^Frame) {
	heroes := sim.iterate_present(&f.state.players)
	for hero, player in sim.next(&heroes) {
		facing := shown_facing(f, hero, player)
		right := [2]f32{-facing.y, facing.x} // a model faces +Z: its right is -X
		godot.push_view(f, player, {
			pos  = sim.Position(hero.pos),
			rot  = dmath.quat_yaw(facing),
			warp = g.hero_warp(f.world.phys, hero),
		}, View_Hero {
			velocity       = {dmath.dot(hero.vel.xz, right), dmath.dot(hero.vel.xz, facing)},
			action_started = hero.action_started,
			class          = hero.class,
			action         = hero.action,
			carrying       = hero.held != {},
		})
	}
	fill_props(f)
	fill_hud(f)
}

// Every prop, the ones a local hero would grab highlighted.
fill_props :: proc(f: ^Frame) {
	phys := f.world.phys
	aimed: [godot.LOCAL_MAX]sim.Handle(g.Prop)
	for player, local in f.local_players {
		hero := sim.player_data(&f.state.players, player)
		if hero == nil || !sim.player_present(&f.state.players, player) || hero.held != {} do continue
		aimed[local] = g.grab_target(phys, &f.state.props, hero.pos, shown_facing(f, hero, player))
	}
	props := sim.iterate(&f.state.props)
	for prop, handle in sim.next(&props) {
		godot.push_view(f, handle, {
			pos  = sim.Position(g.prop_base(phys, prop)),
			rot  = physics.body_rotation(phys, prop.body),
			warp = physics.body_warp(phys, prop.body),
		}, View_Prop{held_by = prop.held_by, kind = prop.kind, aimed = slice.contains(aimed[:], handle)})
	}
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
