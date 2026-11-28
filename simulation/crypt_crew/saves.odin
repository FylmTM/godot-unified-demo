// The save (unified/src/sim/README.md, Saves): the Setup that continues a run in a new session. It is taken at the
// run's save points (mark_save_point): the run's beginning, each descent, each life lost and the run's end; never between
// them, whatever happens on the floor. It holds the floor the party is on, the run (its mode, difficulty, lives and
// number), its tally (the surges faced, the felled, the purse, the depth, the time played) and every member's boons by a stable profile
// id (Saved_Hero), so a Continue starts that floor from its start with all of it carried on (the coins left lying go
// with the floor). A run that ended, and the Pit (one life, no save), save the hub's floor instead: no run to continue.
// The app keeps it as JSON (UnifiedSetup.to_json) in one slot, written by the host or the single player.
//
// Boons come back by profile id, never by slot: a member's first arrival of a session takes the row with its Profile's
// id (claim_saved_hero), each row once, and the host's save carries a joiner's row, so a joiner continuing on its own
// keeps its boons. A second machine with an id a member who arrived first already has (a copied settings file) is
// marked a duplicate as it arrives (Hero.duplicate): it takes no row and is never saved, so the id's row stays the
// first member's, present or away. Rows of the saved party that haven't come back yet are carried on into the next
// save, after the members.
//
// A save reads over the build's default by field name, so an added field needs nothing; SAVE_VERSION moves when an old
// save can't be read as it is (2: the run and the heroes' boons; a version 1 save is set aside by the app).
package crypt_crew

import "unified:sim"

// A save's Setup.version: the save this build writes and continues (the app tells the player about any other).
SAVE_VERSION :: u8(2)

// The most members a save keeps the boons of.
SAVED_HEROES :: 8

// The session's Setup: a new game (version 0: Floor 1 and no crowd unless set) or the save it continues (Game.save).
Setup :: struct {
	version:    u8, // SAVE_VERSION for a save; 0: a new game
	floor:      Level_Id, // the floor the party starts on: a new game's (Floor 1 unless set; the app's: the hub), a save's
	// A held crowd instead of the director's packs and surges (director.odin, Crowd): the benchmark rows', the scale
	// tests', a look at a crowd (`--setup floor=arena,crowd=fight`). Never in a save.
	crowd:      Crowd,
	mode:       Mode, // the run's (run.odin): a new game outside the hub plays it at once (`--setup mode=pit`)
	difficulty: Difficulty, // the run's (`--setup difficulty=hard`)
	lives:      u8, // the run's lives left (a new game's: 0, the difficulty's; set, a test's own)
	_pad:       [2]u8,
	surges:     u32, // the surges it had faced at the save point
	kills:      u32, // the skeletons it had felled
	gold:       u32, // the gold in its purse (loot.odin)
	depth:      u32, // the floors it had gone down (lift.odin)
	run_number: u32, // the runs begun (run.odin): what the boon offers are keyed by
	ticks:      u32, // the run's game time at the save point (run_ticks): the results' clock carries on from it
	heroes:     sim.List(Saved_Hero, SAVED_HEROES), // each member's boons, by profile id (claim_saved_hero)
}

// A member's boons in a save, by its Profile's id.
Saved_Hero :: struct {
	id:    u64, // its Profile's (never 0: a member without an id keeps nothing)
	boons: Boons,
	class: Class, // the class it played: what it plays again when its Profile wishes for none
	_pad:  u8,
}
#assert(size_of(Saved_Hero) == 16)

// The save from a tick's state (sim.Game.save): what the last save point marked (State.saved). Nothing while no save
// point has been marked this session and the session is no Continue (a Continue's is the Setup it started from, the
// save until its next save point). Since the snapshot changes only at a save point, a save is made at each and never
// between (unified keeps a save only when its bytes change).
save :: proc(state: ^State, setup: ^Setup) -> bool {
	if state.saved.version != SAVE_VERSION do return false
	setup^ = state.saved
	return true
}

// Refuses a save this build can't continue (sim.Game.setup_check): its floor is neither one of the crypt's
// (FLOOR_ORDER) nor the hub, or it holds a run with no life left. A new game may name any floor (a test's, a preset's).
setup_check :: proc(setup: ^Setup) -> string {
	if setup.version != SAVE_VERSION || setup.floor == .Hub do return ""
	for floor in FLOOR_ORDER {
		if floor == setup.floor do return "" if setup.lives > 0 else "its run has no life left"
	}
	return "its floor is not one a run is saved on"
}

// The floor a session starts on, with its tally (init): a save's, or a new game's with none. A Continue's snapshot is
// the Setup itself, so its save stands until the next save point.
start_from_setup :: proc(t: ^Tick) -> Level_Id {
	if t.setup.version != SAVE_VERSION do return t.setup.floor
	t.state.saved = t.setup
	t.state.surges = t.setup.surges
	t.state.kills = t.setup.kills
	t.state.gold = t.setup.gold
	t.state.depth = t.setup.depth
	return t.setup.floor
}

// A save point (begin_run, a descent, a life lost, the run's end): the save is this tick's floor, run and tally, and the
// heroes' boons (saved_heroes). A run that isn't playing (it ended), the Pit and the hub save the hub's floor alone: no
// run to continue. Nothing under a held crowd, nor on a floor no run is saved on (the workshop, the arena outside the
// Pit: a test's).
mark_save_point :: proc(t: ^Tick) {
	if t.setup.crowd != .None do return
	run := &t.state.run
	floor := t.state.level.id
	if run.phase != .Playing || run.mode == .Pit do floor = .Hub
	saveable := floor == .Hub
	for crypt in FLOOR_ORDER do saveable ||= crypt == floor
	if !saveable do return
	t.state.saved = {
		version    = SAVE_VERSION,
		floor      = floor,
		mode       = run.mode,
		difficulty = run.difficulty,
		run_number = run.number,
	}
	if floor == .Hub do return
	saved := &t.state.saved
	saved.lives = run.lives
	saved.surges = t.state.surges
	saved.kills = t.state.kills
	saved.gold = t.state.gold
	saved.depth = t.state.depth
	saved.ticks = run_ticks(t)
	saved_heroes(t, &saved.heroes)
}

// The heroes a save keeps (at most SAVED_HEROES): every known member whose Profile has an id and who is no duplicate
// (mark_duplicate), the present first, then the rows of the Setup's saved party no member has taken back (they come back
// in a later session).
@(private = "file")
saved_heroes :: proc(t: ^Tick, heroes: ^sim.List(Saved_Hero, SAVED_HEROES)) {
	for pass in 0 ..< 2 {
		present := pass == 0
		known := sim.iterate_known(t)
		for hero, player in sim.next(&known) {
			if sim.player_present(t, player) != present || hero.duplicate do continue
			add_saved_hero(heroes, {id = sim.player_profile(t, player).id, boons = hero.boons, class = hero.class})
		}
	}
	if t.setup.version != SAVE_VERSION do return
	for &row, i in sim.slice(&t.setup.heroes) {
		if t.state.run.claimed & (1 << uint(i)) == 0 do add_saved_hero(heroes, row)
	}
}

// `row` added to `heroes`, unless its id is 0, already there, or the list is full.
@(private = "file")
add_saved_hero :: proc(heroes: ^sim.List(Saved_Hero, SAVED_HEROES), row: Saved_Hero) {
	if row.id == 0 do return
	for &kept in sim.slice(heroes) {
		if kept.id == row.id do return
	}
	sim.append(heroes, row)
}

// `player` arrives (update_presence, before its class is set): it is a duplicate if its Profile's id is another known
// member's who arrived before it (its class set) and is no duplicate itself. Members arriving on one tick arrive in
// slot order, so the lower slot is the first.
mark_duplicate :: proc(t: ^Tick, player: sim.Player) {
	hero := sim.player_data(t, player)
	id := sim.player_profile(t, player).id
	hero.duplicate = false
	if id == 0 do return
	known := sim.iterate_known(t)
	for other, member in sim.next(&known) {
		if member == player || other.class == .Any || other.duplicate do continue
		if sim.player_profile(t, member).id == id {
			hero.duplicate = true
			return
		}
	}
}

// `player`'s first arrival of the session (its hero's class still Any): the Setup's saved row with its Profile's id
// that no member has taken yet gives it its boons, and the class it played as its own (arrival_class reads it as what
// it played), and is taken (Run.claimed). A duplicate (mark_duplicate) takes nothing.
claim_saved_hero :: proc(t: ^Tick, player: sim.Player) {
	hero := sim.player_data(t, player)
	id := sim.player_profile(t, player).id
	if hero.class != .Any || hero.duplicate || id == 0 || t.setup.version != SAVE_VERSION do return
	for &row, i in sim.slice(&t.setup.heroes) {
		bit := u8(1) << uint(i)
		if row.id != id || t.state.run.claimed & bit != 0 do continue
		t.state.run.claimed |= bit
		hero.boons, hero.class = row.boons, row.class
		return
	}
}
