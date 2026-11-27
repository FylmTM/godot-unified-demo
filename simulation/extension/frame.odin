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
	// The Mage's fireball in flight, by its handle, and where a local Mage's would land, by its player.
	View_Fireball,
	View_Fireball_Target,
	View_Elite, // keyed by its handle (its events' `elite`)
	// The mechanisms, each keyed by its handle (its events' `plate`, `gate`, `barricade`, `trap`), posed at its body.
	View_Plate,
	View_Gate,
	View_Barricade,
	View_Trap,
	// ---- ragdolls
	View_Ragdoll, // a downed hero's ragdoll, keyed by its player
	// The floor's hoard and lift, one of each: alone of their kinds (hoard.odin, lift.odin)
	View_Hoard,
	View_Lift,
	// ---- braziers (braziers.odin)
	View_Brazier, // keyed by its handle (its events' `brazier`), posed at its stand's foot
}

// The MultiMesh views (a MultiMeshInstance3D with a UnifiedMultiView each), keyed by their handles: the Mage's bolts
// and the skeleton Mages' bone bolts, the minions, the crowd (game/crowd/: the baked minion, its shader posing each
// instance from minion_instance), and the coins on the floor (game/views/coins.gd: its shader pops and spins each from loot_instance).
MultiView :: enum u8 {
	Bolt,
	Minion,
	Bone_Bolt, // a skeleton Mage's bolt: a kind of its own, so it draws in its own colour (one MultiMesh, one material)
	Loot,
}

// How each MultiMesh kind is shown. A bolt's and a minion's corrections glide like a scene view's (each keyed instance
// a track): a bolt is few and fast and a pop would show, and a crowd round a remote hero mispredicts, its corrections a
// shove the eye follows. A minion appears once its spawn is verified, since a minion a misprediction raised would
// flash and vanish. Its custom channels 1 and 2 are game-time stamps the host ages (minion_instance). A coin appears
// once its drop is verified too (a kill a rollback takes back drops nothing), and lies still, so it keeps no track;
// its channel 1, when it fell, is aged for its pop, spin and last seconds' blink (loot_instance).
MULTI_POLICY := [MultiView]godot.View_Policy {
	.Bolt = {smoothing = godot.SMOOTHING_DEFAULT},
	.Minion = {appear = .Verified, smoothing = godot.SMOOTHING_DEFAULT, ages = {1, 2}},
	.Bone_Bolt = {smoothing = godot.SMOOTHING_DEFAULT},
	.Loot = {appear = .Verified, ages = {1}},
}

// A hero, posed at its feet and turned to its facing. Its animation is a function of this data (game/views/hero.gd):
// a one-shot action at its age (an attack, an ability, a pick-up, a throw, a revive, going down), else a gait picked
// from its velocity in its own frame. A hero down shows a ring that fills as its revive comes on, none while heaved.
// A hero lying as a ragdoll is posed on the floor under its pelvis and shows only its ring and light: its ragdoll's view
// (View_Ragdoll) shows the body.
View_Hero :: struct {
	velocity:       [2]f32, // metres per second in the hero's frame: x to its right, y ahead
	action_started: sim.Game_Time, // when `action` began: the clip time is (shown_time - action_started) / tick_hz
	class:          g.Class, // EnumClass: which character the view shows
	action:         g.Action, // EnumAction
	grace:          bool, // it was revived a moment ago and takes no damage: the view blinks
	revive:         u8, // while down: how far its revive has come, 0 (none) to 255 (up again)
	heave:          g.Heave_Phase, // EnumHeavePhase: while down, held up or thrown by a Barbarian (no revive ring then)
	ragdoll:        bool, // down as a ragdoll: the view hides its character
	_pad:           [2]u8,
}

// A fireball in flight, keyed by its handle. Script-posed (VIEW_POLICY): its root stays where it was made and its orb
// flies the parabola from `from` to `to` at its age, (shown_time - cast_at) / tick_hz seconds of
// Unified.constants.fireball_flight_s, so after a rollback or a replay seek it shows where the flight is.
View_Fireball :: struct {
	from:    sim.Position, // where it left the Mage's hands
	to:      sim.Position, // where it lands and bursts, on the floor
	cast_at: sim.Game_Time, // when it left
}

// Where a local Mage's fireball would land, keyed by its player and posed there on the floor: the rules'
// fireball_target on the player's newest input sample, the same proc the cast calls, so the ring is where it will land.
// Shown while the Mage is up and its fireball is ready, or while it winds one up.
View_Fireball_Target :: struct {
	casting: bool, // winding up: the cast leaves for this spot at the windup's end (the view burns brighter)
}

// The scene views' policies that aren't the default (Glue.view_policy): a fireball's view poses its own orb on its
// flight's parabola, which the host's per-tick pose would only smooth; an elite appears once its spawn is verified, as
// a minion does: one a misprediction raised (a remote dev spawn, a surge a late command moved) would flash and vanish.
VIEW_POLICY := []godot.View_Kind_Policy {
	{kind = View_Fireball, policy = {pose = .Script}},
	{kind = View_Elite, policy = {appear = .Verified}},
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

// An elite, posed at its feet and turned to its facing; a pooled kind (game/views/elite.tscn). Its animation is a
// function of this data (game/views/elite.gd): its phase at its age, a stagger's hit at the last hit's, else a gait
// picked from its velocity; its health bar is hp of hp_max, and a Warrior's shield glints while it guards. The King
// (the boss) shows its slam's ring from its phase's start and its ward while warded; its bar is the HUD's.
View_Elite :: struct {
	velocity:  [2]f32, // metres per second in its frame: x to its right, y ahead
	since:     sim.Game_Time, // when `phase` began: a one-shot's clip time is (shown_time - since) / tick_hz
	struck:    sim.Game_Time, // when it was last hit (0: never): the flash, and a stagger's clip
	hp:        i16,
	hp_max:    i16,
	kind:      g.Elite_Kind, // EnumEliteKind: which skeleton the view shows
	phase:     g.Elite_Phase, // EnumElitePhase
	guard:     bool, // a Warrior whose shield is up (the rules' shield_up): the view's glint
	staggered: bool, // reeling from a knock (ELITE_STAGGER_KNOCK)
	// ---- the boss (boss.odin)
	warded:    bool, // the King, warded: no blow hurts it (the view's ward)
	_pad:      [3]u8,
}

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

// A coin's instance: where it lies, keyed by its handle (its events' `loot`); its custom data the contract of
// game/views/coin.gdshader's header. 0: its value (the shader sizes it); 1: when it fell, a stamp in ticks the host
// ages into seconds at the shown time; 2 and 3: spare.
loot_instance :: proc(coin: ^g.Loot, handle: sim.Handle(g.Loot)) -> godot.Multi_View_Item(MultiView) {
	return {
		key    = sim.handle_key(handle),
		kind   = .Loot,
		pos    = sim.Position(coin.pos),
		custom = {f32(coin.value), f32(coin.dropped), 0, 0},
	}
}

// Every present hero, every prop, every bolt, every fireball and where a local Mage's would land, every minion, every
// elite, every mechanism, every downed hero's ragdoll, the hoard and the lift, every brazier, every coin, then the HUD's
// data.
fill_frame :: proc(f: ^Frame) {
	fill_heroes(f)
	fill_props(f)
	bolts := sim.iterate(&f.state.bolts)
	for bolt, handle in sim.next(&bolts) {
		kind: MultiView = .Bone_Bolt if bolt.by_elite != {} else .Bolt
		godot.push_multi_view(f, {key = sim.handle_key(handle), kind = kind, pos = sim.Position(bolt.pos)})
	}
	fill_fireballs(f)
	minions := sim.iterate(&f.state.minions)
	for minion, handle in sim.next(&minions) {
		godot.push_multi_view(f, minion_instance(minion, handle))
	}
	fill_elites(f)
	fill_pieces(f)
	fill_ragdolls(f)
	fill_hoard_and_lift(f)
	fill_braziers(f)
	coins := sim.iterate(&f.state.loot)
	for coin, handle in sim.next(&coins) do godot.push_multi_view(f, loot_instance(coin, handle))
	fill_hud(f)
}

// Every present hero: at its feet (a ragdolled one's on the floor under its pelvis, g.floor_under: where its ring and
// light lie), turned as shown_facing says, posed by its action, its revive's progress and its heave.
fill_heroes :: proc(f: ^Frame) {
	heroes := sim.iterate_present(&f.state.players)
	for hero, player in sim.next(&heroes) {
		facing := shown_facing(f, hero, player)
		right := [2]f32{-facing.y, facing.x} // a model faces +Z: its right is -X
		ragdoll := g.ragdolled(hero)
		godot.push_view(f, player, {
			pos  = sim.Position(g.floor_under(f.world.phys, hero.pos) if ragdoll else hero.pos),
			rot  = dmath.quat_yaw(facing),
			warp = g.hero_warp(f.world.phys, hero),
		}, View_Hero {
			velocity       = {dmath.dot(hero.vel.xz, right), dmath.dot(hero.vel.xz, facing)},
			action_started = hero.action_started,
			class          = hero.class,
			action         = hero.action,
			grace          = sim.timer_running(f.time, hero.grace),
			revive         = u8(dmath.min(u32(hero.revive), u32(g.REVIVE_FULL)) * 255 / u32(g.REVIVE_FULL)),
			heave          = hero.heave,
			ragdoll        = ragdoll,
		})
	}
}

// Every fireball in flight; then, for each local Mage that is up with its fireball ready (or winding one up), the
// spot it would land on now: the rules' fireball_target on the player's newest input sample, ahead of the state by the
// input delay, as shown_facing turns the hero.
fill_fireballs :: proc(f: ^Frame) {
	fireballs := sim.iterate(&f.state.fireballs)
	for fireball, handle in sim.next(&fireballs) {
		godot.push_view(f, handle, {pos = sim.Position(fireball.from)}, View_Fireball {
			from    = sim.Position(fireball.from),
			to      = sim.Position(fireball.to),
			cast_at = fireball.cast_at,
		})
	}
	for player, local in f.local_players {
		hero := sim.player_data(&f.state.players, player)
		if hero == nil || !sim.player_present(&f.state.players, player) || hero.class != .Mage do continue
		casting := hero.action == .Cast
		ready := g.can_start_ability(hero) && !sim.timer_running(f.time, hero.ability_ready)
		if !casting && !ready do continue
		target := g.fireball_target(f.world.phys, hero, f.local_inputs[local])
		godot.push_view(f, player, {pos = sim.Position(target)}, View_Fireball_Target{casting = casting})
	}
}

// Every elite (a dying one as it fell: its body is gone, its feet stay where they were); the King's full health is the
// boss's, set as it woke (its spec's while asleep).
fill_elites :: proc(f: ^Frame) {
	boss := &f.state.boss
	elites := sim.iterate(&f.state.elites)
	for elite, handle in sim.next(&elites) {
		hp_max := g.ELITE_SPECS[elite.kind].hp
		is_boss := elite.kind == .King && handle == boss.elite
		if is_boss && boss.hp_max > 0 do hp_max = boss.hp_max
		right := [2]f32{-elite.facing.y, elite.facing.x} // a model faces +Z: its right is -X
		godot.push_view(f, handle, {
			pos = sim.Position(elite.pos),
			rot = dmath.quat_yaw(elite.facing),
		}, View_Elite {
			velocity  = {dmath.dot(elite.vel.xz, right), dmath.dot(elite.vel.xz, elite.facing)},
			since     = elite.since,
			struck    = elite.struck,
			hp        = elite.hp,
			hp_max    = hp_max,
			kind      = elite.kind,
			phase     = elite.phase,
			guard     = g.shield_up(f.time, elite),
			staggered = sim.timer_running(f.time, elite.stagger),
			warded    = is_boss && boss.warded,
		})
	}
}

// Every prop, the ones a local hero would grab highlighted (the rules' hands_target, on its shown facing): none while
// that hero's Interact would revive an ally instead (revive_target).
fill_props :: proc(f: ^Frame) {
	aimed: [godot.LOCAL_MAX]sim.Handle(g.Prop)
	for player, local in f.local_players {
		hero := sim.player_data(&f.state.players, player)
		if hero == nil || !sim.player_present(&f.state.players, player) do continue
		if g.revive_target(&f.state.players, player) != {} do continue
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
// Paused, nobody turns; nor does a hero in a dash (a charge, a roll), whose line the rules keep.
shown_facing :: proc(f: ^Frame, hero: ^g.Hero, player: sim.Player) -> [2]f32 {
	if f.state.clock.paused || hero.action == .Down || hero.action == .Charge || hero.action == .Roll do return hero.facing
	for local_player, local in f.local_players {
		if local_player == player do return g.hero_facing(f.local_inputs[local], hero.facing)
	}
	return hero.facing
}

// ---- mechanisms (plates.odin, gates.odin, barricades.odin, traps.odin)

// A plate, posed at its slab's centre: the slab sinks under a load as the body does, so the view only shows it.
View_Plate :: struct {
	pressed: bool, // sunk past PLATE_ON (the sim's rule, with its hysteresis)
}

// A gate, posed at its grille's centre as it rises and falls.
View_Gate :: struct {
	open: bool, // told to open: its grille rises (or is still on its way up)
}

// A barricade, posed at its fence's centre: standing, or tumbling as debris once broken.
View_Barricade :: struct {
	broken: bool,
}

// A trap, posed at its body's centre: spikes' sensor box (a hand above the floor), a roller's pillar as it goes. Spikes'
// height is the view's, a function of `up`, `since` and the shown time (game/views/trap.gd), so a rollback or a seek
// shows them where they are.
View_Trap :: struct {
	since: sim.Game_Time, // spikes: when they last rose or fell
	kind:  g.Trap_Kind, // EnumTrapKind: which model the view shows
	up:    bool, // spikes: up
	_pad:  [2]u8,
}

// Every mechanism, at its body.
fill_pieces :: proc(f: ^Frame) {
	phys := f.world.phys
	plates := sim.iterate(&f.state.plates)
	for plate, handle in sim.next(&plates) {
		godot.push_view(f, handle, piece_pose(phys, plate.body), View_Plate{pressed = plate.pressed})
	}
	gates := sim.iterate(&f.state.gates)
	for gate, handle in sim.next(&gates) {
		godot.push_view(f, handle, piece_pose(phys, gate.body), View_Gate{open = gate.open})
	}
	barricades := sim.iterate(&f.state.barricades)
	for barricade, handle in sim.next(&barricades) {
		godot.push_view(f, handle, piece_pose(phys, barricade.body), View_Barricade{broken = barricade.broken})
	}
	traps := sim.iterate(&f.state.traps)
	for trap, handle in sim.next(&traps) {
		godot.push_view(
			f,
			handle,
			piece_pose(phys, trap.body),
			View_Trap{since = trap.since, kind = trap.kind, up = trap.up},
		)
	}
}

// A mechanism's pose: its body's centre and turn, and its body's warp epoch (a body made again snaps there).
piece_pose :: proc(phys: ^physics.World, body: physics.Body_Ref) -> godot.View_Item {
	return {
		pos  = sim.Position(physics.body_position(phys, body)),
		rot  = physics.body_rotation(phys, body),
		warp = physics.body_warp(phys, body),
	}
}

// ---- ragdolls

// A downed hero's ragdoll (g.ragdolled), keyed by its player, drawn on its class's character (game/views/ragdoll.gd).
// The root is posed at the pelvis, turned as the pelvis is from its rest pose (a ragdoll lying as it was made, upright
// and facing +Z, poses its root unturned), so the host interpolates the body as a whole; the bones are data in the
// root's frame, which the script turns the rig's bones by: the torso's (the pelvis, the spine, the chest, the head) by
// `turns`, each limb's by `turns` after the turn that takes its rest direction onto the ragdoll bone's at rest (from
// `reaches`: the rig's rest pose is a T-pose, the ragdoll's arms hang down), so a knee or an elbow bends in its own
// plane. `time` is the tick the bones are of: the script interpolates them between two ticks, as the host does the root.
View_Ragdoll :: struct {
	// Each bone's rotation from its rest pose (physics.ragdoll_rest_pose, facing +Z), in the root's frame: the
	// pelvis's is none.
	turns:   [physics.Ragdoll_Bone]godot.Quat,
	// Each bone's direction, a unit vector in the root's frame, from its joint (its body's origin) to the far end of its
	// capsule.
	reaches: [physics.Ragdoll_Bone][3]f32,
	time:    sim.Game_Time, // the tick of `turns` and `reaches`
	class:   g.Class, // EnumClass: which character the view shows
	_pad:    [3]u8,
}

// Every present hero lying as a ragdoll. Its warp epoch is the hero's (g.hero_warp): a revive's teleport moves it on,
// so the ragdoll of the hero's next fall snaps to it rather than gliding from where the last one lay.
fill_ragdolls :: proc(f: ^Frame) {
	rest := physics.ragdoll_rest_pose({}, scale = g.RAGDOLL_SCALE)
	heroes := sim.iterate_present(&f.state.players)
	for hero, player in sim.next(&heroes) {
		if !g.ragdolled(hero) do continue
		pelvis := hero.ragdoll.bones[.Pelvis]
		root := dmath.quat_mul(physics.body_rotation(f.world.phys, pelvis), conjugate(rest[.Pelvis].q))
		into_root := conjugate(root)
		data := View_Ragdoll {
			time  = f.time,
			class = hero.class,
		}
		for body, bone in hero.ragdoll.bones {
			turned := physics.body_rotation(f.world.phys, body)
			data.turns[bone] = godot.Quat(dmath.quat_mul(into_root, dmath.quat_mul(turned, conjugate(rest[bone].q))))
			capsules, _ := physics.ragdoll_capsules(bone, g.RAGDOLL_SCALE)
			far := capsules[0].center1
			if dmath.length_sq(capsules[0].center2) > dmath.length_sq(far) do far = capsules[0].center2
			data.reaches[bone] = dmath.quat_rotate(into_root, dmath.quat_rotate(turned, dmath.normalize(far)))
		}
		godot.push_view(f, player, {
				pos  = sim.Position(physics.body_position(f.world.phys, pelvis)),
				rot  = root,
				warp = g.hero_warp(f.world.phys, hero),
			}, data)
	}
}

// The inverse of a unit quaternion (x, y, z, w).
@(private = "file")
conjugate :: proc(quat: [4]f32) -> [4]f32 {
	return {-quat.x, -quat.y, -quat.z, quat.w}
}

// ---- the hoard and the lift (hoard.odin, lift.odin)

// The floor's hoard, posed at the bottom of its box (its model's origin) and turned as its body is
// (game/views/hoard.gd).
View_Hoard :: struct {
	aimed: bool, // a local hero's Interact would take one of its handles now (the rules' haul_target): it glows
	held:  bool, // a hand is on it: carried or dragged (the creak of its weight)
	_pad:  [2]u8,
}

// The floor's lift, posed at the middle of its deck's top and turned as the deck is (game/views/lift.gd): the deck
// creaks while it goes down.
View_Lift :: struct {
	phase: g.Lift_Phase, // EnumLiftPhase
	_pad:  [3]u8,
}

// The hoard and the lift, where the floor has them; the hoard highlighted while a local hero's Interact would take a
// handle (haul_target, on the state, as the press asks it).
fill_hoard_and_lift :: proc(f: ^Frame) {
	if hoard := &f.state.hoard; hoard.body != {} {
		aimed := false
		for player in f.local_players {
			hero := sim.player_data(&f.state.players, player)
			if hero == nil || !sim.player_present(&f.state.players, player) do continue
			aimed ||= g.haul_target(f.world.phys, hoard, &f.state.lift, hero) != .None
		}
		godot.push_view(f, {
			pos  = sim.Position(physics.body_world_point(f.world.phys, hoard.body, {0, -g.HOARD_HALF.y, 0})),
			rot  = physics.body_rotation(f.world.phys, hoard.body),
			warp = physics.body_warp(f.world.phys, hoard.body),
		}, View_Hoard{aimed = aimed, held = hoard.haulers != {}})
	}
	if lift := &f.state.lift; lift.body != {} {
		godot.push_view(f, {
			pos = sim.Position(physics.body_world_point(f.world.phys, lift.body, {0, g.LIFT_HALF.y, 0})),
			rot = physics.body_rotation(f.world.phys, lift.body),
		}, View_Lift{phase = lift.phase})
	}
}

// ---- braziers (braziers.odin)

// A brazier, posed at its stand's foot (its marker); game/views/brazier.gd draws its fire at the bowl while it is lit,
// an ember growing as it is kindled, and plays its sound as it lights.
View_Brazier :: struct {
	lit_at:  sim.Game_Time, // when it lit: the fire flares from then (shown_time - lit_at)
	kindled: u8, // while unlit: how far its kindling has come, 0 (none) to 255 (lit)
	lit:     bool,
	_pad:    [2]u8,
}

// Every brazier on the floor, at its marker.
fill_braziers :: proc(f: ^Frame) {
	defs := sim.slice(&f.world.floors[f.state.level.id].places.braziers)
	braziers := sim.iterate(&f.state.braziers)
	for brazier, handle in sim.next(&braziers) {
		kindled := dmath.min(u32(brazier.progress), u32(g.BRAZIER_LIGHT_TICKS)) * 255 / u32(g.BRAZIER_LIGHT_TICKS)
		godot.push_view(f, handle, {pos = sim.Position(defs[handle.index].pos)}, View_Brazier {
			lit_at  = brazier.lit_at,
			kindled = u8(kindled),
			lit     = brazier.lit,
		})
	}
}
