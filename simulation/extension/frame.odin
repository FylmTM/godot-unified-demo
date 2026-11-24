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
// player (sim.player_key), a prop's and a minion's by their handles (their events' `prop`, `minion`).
View :: union {
	View_Hero,
	View_Prop,
	View_Minion,
}

// No MultiMesh views yet.
MultiView :: enum u8 {}

// A hero, posed at its feet and turned to its facing. Its animation is a function of this data (game/views/hero.gd):
// a one-shot action at its age (a pick-up, a throw, going down), else a gait picked from its velocity in its own frame.
View_Hero :: struct {
	velocity:       [2]f32, // metres per second in the hero's frame: x to its right, y ahead
	action_started: sim.Game_Time, // when `action` began: the clip time is (shown_time - action_started) / tick_hz
	class:          g.Class, // EnumClass: which character the view shows
	action:         g.Action, // EnumAction
	grace:          bool, // it rose a moment ago and takes no damage: the view blinks
	_pad:           u8,
}

// A prop, posed at the bottom of its body (its model's origin) and turned as its body is; a pooled kind (prop.tscn).
View_Prop :: struct {
	kind:  g.Prop_Kind, // EnumPropKind: which model the view shows
	aimed: bool, // a local hero's Interact would grab it now (the rules' hands_target): the view highlights it
}

// A minion, posed at its feet and turned to its facing; a pooled kind (minion.tscn) shown only once its spawn is
// verified (VIEW_POLICY), since a minion a misprediction raised would flash and vanish. Its animation is a function of
// its phase and when that began, its flash of when it was struck (game/views/minion.gd).
View_Minion :: struct {
	since:  sim.Game_Time, // when `phase` began
	struck: sim.Game_Time, // when it was last hit (0: never)
	phase:  g.Minion_Phase, // EnumMinionPhase
	moving: bool, // it moved faster than MINION_STILL_SPEED this tick: a chaser that can't get anywhere stands
	_pad:   [2]u8,
}

// Below this speed (metres per second) a minion's view stands rather than walks.
MINION_STILL_SPEED :: f32(0.3)

// The kinds whose policy isn't the default (Glue.view_policy): minions appear once verified.
VIEW_POLICY := []godot.View_Kind_Policy{{View_Minion, {appear = .Verified}}}

// Every present hero, every prop, every minion, then the HUD's data.
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
			grace          = sim.timer_running(f.time, hero.grace),
		})
	}
	fill_props(f)
	minions := sim.iterate(&f.state.minions)
	for minion, handle in sim.next(&minions) {
		godot.push_view(f, handle, {pos = sim.Position(minion.pos), rot = dmath.quat_yaw(minion.facing)}, View_Minion {
			since  = minion.since,
			struck = minion.struck,
			phase  = minion.phase,
			moving = dmath.length_sq(minion.vel) > MINION_STILL_SPEED * MINION_STILL_SPEED,
		})
	}
	fill_hud(f)
}

// Every prop, the ones a local hero would grab highlighted (the rules' hands_target, on its shown facing).
fill_props :: proc(f: ^Frame) {
	aimed: [godot.LOCAL_MAX]sim.Handle(g.Prop)
	for player, local in f.local_players {
		hero := sim.player_data(&f.state.players, player)
		if hero == nil || !sim.player_present(&f.state.players, player) do continue
		aimed[local] = g.hands_target(f.world.phys, &f.state.props, hero, shown_facing(f, hero, player))
	}
	props := sim.iterate(&f.state.props)
	for prop, handle in sim.next(&props) {
		godot.push_view(f, handle, {
			pos  = sim.Position(g.prop_base(f.world.phys, prop)),
			rot  = physics.body_rotation(f.world.phys, prop.body),
			warp = physics.body_warp(f.world.phys, prop.body),
		}, View_Prop{kind = prop.kind, aimed = slice.contains(aimed[:], handle)})
	}
}

// Where a hero is shown looking: a local hero that is up turns with its newest input sample at once (the rules' own
// hero_facing on Frame.local_inputs, ahead of the state by the input delay), every other hero as the state has it.
// Paused, nobody turns.
shown_facing :: proc(f: ^Frame, hero: ^g.Hero, player: sim.Player) -> [2]f32 {
	if f.state.clock.paused || hero.action == .Down do return hero.facing
	for local_player, local in f.local_players {
		if local_player == player do return g.hero_facing(f.local_inputs[local], hero.facing)
	}
	return hero.facing
}
