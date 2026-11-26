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

// The MultiMesh views (a MultiMeshInstance3D with a UnifiedMultiView each), keyed by their handles: the Mage's bolts,
// and the minions, the crowd (game/crowd/: the baked minion, its shader posing each instance from minion_instance).
MultiView :: enum u8 {
	Bolt,
	Minion,
}

// How each MultiMesh kind is shown. A bolt's and a minion's corrections glide like a scene view's (each keyed instance
// a track): a bolt is few and fast and a pop would show, and a crowd round a remote hero mispredicts, its corrections a
// shove the eye follows. A minion appears once its spawn is verified, since a minion a misprediction raised would
// flash and vanish. Its custom channels 1 and 2 are game-time stamps the host ages (minion_instance).
MULTI_POLICY := [MultiView]godot.View_Policy {
	.Bolt = {smoothing = godot.SMOOTHING_DEFAULT},
	.Minion = {appear = .Verified, smoothing = godot.SMOOTHING_DEFAULT, ages = {1, 2}},
}

// A hero, posed at its feet and turned to its facing. Its animation is a function of this data (game/views/hero.gd):
// a one-shot action at its age (an attack, a pick-up, a throw, going down), else a gait picked from its velocity in its
// own frame.
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

// A crowd minion's clip, its custom channel 0: the crowd's clips in MinionCrowd.Clip's order
// (game/crowd/minion_crowd.gd, which names the baked clips). The two lists change together: view_test.odin and the art
// checks pin both to the same numbers.
Minion_Clip :: enum u8 {
	Idle,
	Walk,
	Attack,
	Rise,
	Death,
}

// Below this speed (metres per second) a chasing minion stands rather than walks.
MINION_STILL_SPEED :: f32(0.3)
// A minion's gait phase spreads the crowd's loops apart (no lockstep): its handle's key, modulo MINION_PHASE_KEYS
// (past its generation's bits), times MINION_PHASE_S seconds, which the loop's clip wraps.
MINION_PHASE_KEYS :: 997
MINION_PHASE_S :: f32(0.618034)
// The stamp of a minion never struck (its custom channel 2): far in the past, so it never flashes (a 0 stamp would age
// as the shown time itself, and flash every minion in a session's first ticks).
MINION_NEVER_STRUCK :: f32(-1e9)

// The scene views' policies that aren't the default (Glue.view_policy): none.
VIEW_POLICY := []godot.View_Kind_Policy{}

// A minion's crowd instance: at its feet, turned to its facing, keyed by its handle; its custom data the contract of
// game/crowd/crowd_minion.gdshader's header. 0: its clip (Minion_Clip: a chaser that isn't moving stands); 1: the
// clip's start stamp, its phase's tick for a one-shot (the rise, the swing, the fall), minus its gait phase for a loop
// (the stance and the walk), so a minion that stops and goes doesn't restart its gait; 2: its last hit's stamp
// (MINION_NEVER_STRUCK: never); 3: spare. Stamps are ticks; the host ages 1 and 2 into seconds at the shown time.
minion_instance :: proc(minion: ^g.Minion, handle: sim.Handle(g.Minion)) -> godot.Multi_View_Item(MultiView) {
	clip: Minion_Clip
	switch minion.phase {
	case .Rise:
		clip = .Rise
	case .Idle:
		clip = .Idle
	case .Chase:
		moving := dmath.length_sq(minion.vel) > MINION_STILL_SPEED * MINION_STILL_SPEED
		clip = .Walk if moving else .Idle
	case .Attack:
		clip = .Attack
	case .Dying:
		clip = .Death
	}
	key := sim.handle_key(handle)
	start := f32(minion.since)
	if clip == .Idle || clip == .Walk {
		start = -f32(key % MINION_PHASE_KEYS) * MINION_PHASE_S * g.TICK_HZ
	}
	struck := f32(minion.struck) if minion.struck != 0 else MINION_NEVER_STRUCK
	return {
		key    = key,
		kind   = .Minion,
		pos    = sim.Position(minion.pos),
		rot    = dmath.quat_yaw(minion.facing),
		custom = {f32(clip), start, struck, 0},
	}
}

// Every present hero, every prop, every bolt, every minion, then the HUD's data.
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
	bolts := sim.iterate(&f.state.bolts)
	for bolt, handle in sim.next(&bolts) {
		godot.push_multi_view(f, {key = sim.handle_key(handle), kind = .Bolt, pos = sim.Position(bolt.pos)})
	}
	minions := sim.iterate(&f.state.minions)
	for minion, handle in sim.next(&minions) {
		godot.push_multi_view(f, minion_instance(minion, handle))
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
