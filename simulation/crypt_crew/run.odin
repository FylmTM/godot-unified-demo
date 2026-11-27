// The run: what a session plays between two visits to the hub. The session starts in the hub (the graveyard: no damage,
// no director, no wipe), where the party sets the next run's mode and difficulty at its two shrines and boards the
// crypt's lift; the session lives on across runs, so friends stay together. The hub's lift goes without a hoard
// (Lift_Def.hoard) and takes the party into the run (begin_run): the crypt's first floor, or the endless arena (the
// Pit, arena.odin), with the difficulty's lives (DIFFICULTY). A wipe costs a life (party_fell): with lives left the
// floor starts over from its save point, the purse and the felled as they stood there; the last one ends the run,
// lost. Either ending (end_run: the last life, or the boss's death) holds RUN_END_S for the results, then the party is
// back in the hub.
//
// The run is a value in the block (State.run) that rides in the save (saves.odin), so quitting refills no life. Its
// number keys the boon offers (boons.offer_index), so a second run's cards are not the first's, and a Continue deals as
// the run it continues did.
//
// A shrine (a `shrine` marker) is turned by an Interact press within SHRINE_RANGE of it, by anyone: each press moves its
// setting on to the next value, at most once every SHRINE_COOLDOWN_S, so two heroes pressing on one tick turn it once.
// Interact means what it always has first (a haul, a drop, a grab, a revive): a shrine takes only a press nothing else
// would (shrine_target, which the HUD's prompt asks too). The shrines lock once the hub's lift boards.
package crypt_crew

import "unified:dmath"
import "unified:sim"

// What a shrine sets (game/levels/markers/shrine.gd's `sets`, by name).
Shrine_Setting :: enum u8 {
	Mode, // the crypt's floors or the endless arena
	Difficulty,
}

// A shrine's place (a `shrine` marker): a floor's Places keep one for each setting at most.
Shrine_Def :: struct {
	pos:    [3]f32,
	placed: bool, // the floor has one for this setting
	_pad:   [3]u8,
}

// What a run plays.
Mode :: enum u8 {
	Crypt, // the crypt's floors (FLOOR_ORDER), down to the boss
	Pit, // the endless arena's waves, one life (arena.odin)
}

// How hard a run is (DIFFICULTY).
Difficulty :: enum u8 {
	Normal,
	Hard,
}

// Where the session is in a run.
Run_Phase :: enum u8 {
	Hub, // between runs, in the hub
	Playing,
	Won, // the boss fell: the results show for RUN_END_S, then the hub
	Lost, // the last life went: the results show for RUN_END_S, then the hub
}

// The run, in the State (State.run).
Run :: struct {
	since:      sim.Game_Time, // when `phase` began (Playing's: the run's start)
	number:     u32, // the runs begun, a save's included (0: none yet): what the boon offers are keyed by
	offers:     u32, // the boon choices opened this run (each lift's bottom, each lull of the Pit): Hero.picked's count
	mode:       Mode, // the run's, while it plays; in the hub, the mode shrine's setting
	difficulty: Difficulty, // likewise
	phase:      Run_Phase,
	lives:      u8, // the wipes the run can still take
	claimed:    u8, // the Setup's saved heroes taken back this session, a bit by row (saves.odin)
	_pad:       [3]u8,
}

// A run began (begin_run): `mode` at `difficulty`.
Event_Run_Began :: struct {
	mode:       Mode,
	difficulty: Difficulty,
}

// The run ended (end_run): `won` (the boss fell) or lost (the last life went), with its tally: the floors gone down,
// the purse, the felled and the surges (the Pit's waves) faced, over `ticks` of game time. The results panel shows
// it once CONFIRMED.
Event_Run_Ended :: struct {
	won:    bool,
	mode:   Mode,
	_pad:   [2]u8,
	depth:  u32,
	gold:   u32,
	kills:  u32,
	surges: u32,
	ticks:  u32,
}

// `player` turned a shrine: its setting `sets` is now `value` (a Mode or a Difficulty, by number).
Event_Shrine :: struct {
	player: sim.Player,
	sets:   Shrine_Setting,
	value:  u8,
}

// A wipe cost a life: `lives` are left, and the purse is back at `gold` (the save point's).
Event_Life_Lost :: struct {
	lives: u8,
	gold:  u32,
}

// The run at the session's start (init): a save's as it was; a new game's on the Setup's mode and difficulty, playing
// at once on any floor but the hub (a test's or a preset's floor: Setup.lives, when set, overrides the difficulty's).
start_run :: proc(t: ^Tick) {
	run := &t.state.run
	run.mode, run.difficulty = t.setup.mode, t.setup.difficulty
	run.since = t.time
	if t.setup.version == SAVE_VERSION {
		run.number, run.offers, run.lives = t.setup.run_number, t.setup.depth, t.setup.lives
		run.phase = .Hub if t.setup.floor == .Hub else .Playing
		return
	}
	if t.setup.floor == .Hub do return
	run.number, run.phase = 1, .Playing
	run.lives = t.setup.lives if t.setup.lives > 0 else run_lives(run)
}

// A run begins (the hub's lift reached its bottom, Lift_Def.hoard false): its number goes up, the tally and every
// known hero's boons go (a saved row's with them: what the session started from belongs to an older run), the lives
// are the difficulty's, the party enters the run's first floor (the crypt's, or the Pit's arena), and the save point
// is marked there.
begin_run :: proc(t: ^Tick) {
	run := &t.state.run
	run.number += 1
	run.offers = 0
	run.lives = run_lives(run)
	run.claimed = 0xff
	run.phase, run.since = .Playing, t.time
	t.state.gold, t.state.kills, t.state.surges, t.state.depth = 0, 0, 0, 0
	known := sim.iterate_known(t)
	for hero in sim.next(&known) do hero.boons, hero.picked = {}, 0
	t.state.pit = {}
	enter_level(t, .Arena if run.mode == .Pit else FLOOR_ORDER[0])
	mark_save_point(t)
	sim.emit(t, Event_Run_Began{mode = run.mode, difficulty = run.difficulty})
}

// The lives a run of `run`'s mode and difficulty starts with.
run_lives :: proc(run: ^Run) -> u8 {
	return PIT_LIVES if run.mode == .Pit else DIFFICULTY[run.difficulty].lives
}

// The whole party stayed down (check_wipe's WIPE_S ran out): a life goes. With lives left the floor starts over from
// its save point (restart_floor), the purse and the felled back at the save's (boons were won at the lifts, so they
// stay; the surges faced stay too, a count of the run's), and the save point is marked again (the lives are in it); at
// none, the run is lost.
party_fell :: proc(t: ^Tick) {
	run := &t.state.run
	if run.phase != .Playing do return
	run.lives = run.lives - 1 if run.lives > 0 else 0
	if run.lives == 0 {
		sim.emit(t, Event_Life_Lost{lives = 0, gold = t.state.gold})
		end_run(t, won = false)
		return
	}
	if t.state.saved.version == SAVE_VERSION {
		t.state.gold, t.state.kills = t.state.saved.gold, t.state.saved.kills
	}
	sim.emit(t, Event_Life_Lost{lives = run.lives, gold = t.state.gold})
	restart_floor(t)
	mark_save_point(t)
}

// The run ends, `won` or lost: its tally goes out (Event_Run_Ended), a choice the Pit had open closes, the save point is
// marked (a save of no run: the hub's), and RUN_END_S later the party is back in the hub (update_run).
end_run :: proc(t: ^Tick, won: bool) {
	run := &t.state.run
	if run.phase != .Playing do return
	ended := Event_Run_Ended {
		won    = won,
		mode   = run.mode,
		depth  = t.state.depth,
		gold   = t.state.gold,
		kills  = t.state.kills,
		surges = t.state.surges,
		ticks  = u32(t.time - run.since),
	}
	if choice_open(t.state) do sim.emit(t, Event_Choice{open = false})
	t.state.pit = {}
	run.phase, run.since = .Won if won else .Lost, t.time
	mark_save_point(t)
	sim.emit(t, ended)
}

// After the lift: a run that ended RUN_END_S ago takes the party back to the hub.
update_run :: proc(t: ^Tick) {
	run := &t.state.run
	if run.phase != .Won && run.phase != .Lost do return
	if u32(t.time - run.since) < RUN_END_TICKS do return
	run.phase, run.since = .Hub, t.time
	enter_level(t, .Hub)
}

// Whether nothing can hurt the party now: the hub, a run's end, the Pit's lull choice. No hero takes damage
// (damage_hero), the party can't wipe (check_wipe) and the director raises nothing (director_runs).
harmless :: proc(t: ^Tick) -> bool {
	return t.state.run.phase != .Playing || t.state.pit.stage == .Choosing
}

// Whether the director raises surges now: a run playing, and in the Pit only between its lulls.
director_runs :: proc(t: ^Tick) -> bool {
	return t.state.run.phase == .Playing && t.state.pit.stage == .Waves
}

// Whether the party plays the Pit (arena.odin): a Pit run on the arena.
in_pit :: proc(t: ^Tick) -> bool {
	return t.state.run.mode == .Pit && t.state.run.phase == .Playing && t.state.level.id == .Arena
}

// ---- the difficulty and the depth ramp (DIFFICULTY, SURGE_PER_DEPTH, DEPTH_HP)

// A surge's size before the floor's cap: the crypt's (SURGE_BASE, SURGE_PER_HERO for each hero present, SURGE_GROWTH
// for each surge faced on the floor, SURGE_PER_DEPTH for each floor gone down) or the Pit's wave (pit_wave), times the
// difficulty's surge scale, rounded.
surge_size :: proc(t: ^Tick) -> int {
	heroes := SURGE_PER_HERO * sim.present_count(t)
	size: int
	if in_pit(t) {
		size = pit_wave(int(t.state.floor_surges) + 1, sim.present_count(t))
	} else {
		size = SURGE_BASE + heroes + SURGE_GROWTH * int(t.state.floor_surges) + SURGE_PER_DEPTH * int(t.state.depth)
	}
	return int(dmath.to_i32_clamped(dmath.round(f32(size) * DIFFICULTY[t.state.run.difficulty].surge), 0, max(i32)))
}

// How long until the next surge, as raise_surges restarts its clock: the Pit's PIT_SURGE_S, else the floor's
// (surge_every: quicker once the haul has begun).
surge_clock :: proc(t: ^Tick) -> u32 {
	return PIT_SURGE_TICKS if in_pit(t) else surge_every(t)
}

// Every how many surges on a floor one brings an elite: the Pit's PIT_ELITE_EVERY, else the difficulty's.
elite_every :: proc(t: ^Tick) -> u32 {
	return PIT_ELITE_EVERY if in_pit(t) else DIFFICULTY[t.state.run.difficulty].elite_every
}

// A minion's hit points as it rises: MINION_HP, times the difficulty's and the depth ramp's (DEPTH_HP a floor gone
// down), rounded.
minion_hp :: proc(state: ^State) -> i16 {
	scale := DIFFICULTY[state.run.difficulty].minion_hp * (1 + DEPTH_HP * f32(state.depth))
	return i16(dmath.to_i32_clamped(dmath.round(f32(MINION_HP) * scale), 1, i32(max(i16))))
}

// What a minion's swing takes from a hero: MINION_DAMAGE, times the difficulty's, rounded.
minion_damage :: proc(t: ^Tick) -> i16 {
	scaled := dmath.round(f32(MINION_DAMAGE) * DIFFICULTY[t.state.run.difficulty].minion_damage)
	return i16(dmath.to_i32_clamped(scaled, 1, i32(max(i16))))
}

// An elite of `kind`'s hit points as it rises: its spec's, times the difficulty's, rounded.
elite_hp :: proc(state: ^State, kind: Elite_Kind) -> i16 {
	scaled := dmath.round(f32(ELITE_SPECS[kind].hp) * DIFFICULTY[state.run.difficulty].elite_hp)
	return i16(dmath.to_i32_clamped(scaled, 1, i32(max(i16))))
}

// `gold` as the run's difficulty pays it (a coin's drop, the hoard's), rounded.
run_gold :: proc(t: ^Tick, gold: int) -> int {
	return int(dmath.to_i32_clamped(dmath.round(f32(gold) * DIFFICULTY[t.state.run.difficulty].gold), 0, max(i32)))
}

// ---- the hub's shrines

// The shrine `player`'s hero would turn with an Interact press now, and whether there is one: in the hub with its lift
// waiting, the hero up with free hands (can_grab) and nothing else its press would take (no hoard's handle, no prop:
// a shrine is last in Interact's order), within SHRINE_RANGE of the shrine on the floor plan (the nearer of two). Pure:
// what the tick and the HUD's prompt both ask.
shrine_target :: proc(state: ^State, world: ^World, player: sim.Player) -> (setting: Shrine_Setting, ok: bool) {
	if state.run.phase != .Hub || state.lift.phase != .Waiting do return
	hero := sim.player_data(&state.players, player)
	if hero == nil || hero.action == .Down || !can_grab(hero) || hero.handle != .None do return
	if haul_target(world.phys, &state.hoard, &state.lift, hero) != .None do return
	if hands_target(world.phys, &state.props, hero, hero.facing) != {} do return
	nearest := SHRINE_RANGE * SHRINE_RANGE
	for &def, candidate in world.floors[state.level.id].places.shrines {
		if !def.placed do continue
		if apart := dmath.length_sq(def.pos.xz - hero.pos.xz); apart <= nearest {
			setting, ok, nearest = candidate, true, apart
		}
	}
	return
}

// Each present hero's Interact press at a shrine (shrine_target), in slot order: the shrine's setting moves on to its
// next value, unless the shrine changed less than SHRINE_COOLDOWN_S ago (so a second press on the same tick, or a
// held tap's bounce, turns it once).
press_shrines :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for _, player in sim.next(&heroes) {
		if .Interact not_in sim.buttons(t, player).pressed do continue
		setting := shrine_target(t.state, t.world, player) or_continue
		if sim.timer_running(t, t.state.shrines[setting]) do continue
		sim.timer_start_ticks(t, &t.state.shrines[setting], SHRINE_COOLDOWN_TICKS)
		run := &t.state.run
		value: u8
		switch setting {
		case .Mode:
			run.mode = Mode((int(run.mode) + 1) % len(Mode))
			value = u8(run.mode)
		case .Difficulty:
			run.difficulty = Difficulty((int(run.difficulty) + 1) % len(Difficulty))
			value = u8(run.difficulty)
		}
		sim.emit(t, Event_Shrine{player = player, sets = setting, value = value})
	}
}
