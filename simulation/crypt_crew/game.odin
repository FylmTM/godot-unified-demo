// crypt_crew (README.md): a top-down co-op dungeon crawler for 1-4 players, its rules as one deterministic sim that
// unified runs under rollback netcode.
//
// One system per file: game (this: the descriptor and the tick, its table of contents), tuning (every rule number),
// input (the input and the commands), state, events, world (the physics world, each level's floor: its navigation and
// places; init, entering a level and restarting it), presence (arrivals, leaves, where an arrival appears), heroes
// (facing, movement, read back), hands (grab, carry, drop, throw), attacks and abilities (the shared machinery of each)
// and a file per class (knight, barbarian, mage, rogue), bolts and fireballs (the Mage's), props (their bodies, hits,
// impacts and throws' ends), minions (targets, steering, swings, dying), director (sleeping packs, surges, held crowds
// and the benchmarks' populations), health (damage, down, the wipe), revive (allies tending the downed), pause (the
// co-op pause), saves (the Setup a save is, and the tally it carries), dev (the dev commands) and script (the scripted
// player).
package crypt_crew

import "unified:physics"
import "unified:sim"

PLAYERS :: 4 // input slots: the most heroes in the game at once
TICK_HZ :: 64 // ticks per second of game time

// The game's version (sim.Game.version, part of the netcode's compat): bump it when a rule or constant changes what a
// tick computes without changing the State or Input layout, or two builds desync instead of refusing each other.
VERSION :: "17"

// The game's types for unified:sim: a physics World, a Setup (a new game or a save), a Profile per player.
Game :: sim.Game(State, Input, World, Event, Command, Setup, Profile, PLAYERS)
// What every system gets: the state, the world, the inputs and commands, the tick's player changes.
Tick :: sim.Tick(Game)

// The game: what the headless binary, the GDExtension and the tests run (its hooks: `uni doc sim Game`).
@(rodata)
GAME := Game {
	name              = "crypt_crew",
	version           = VERSION,
	tick_hz           = TICK_HZ,
	// game/levels/<name>.tscn's (uni bake), in Level_Id's order
	levels            = {
		{"floor_1", #load("../../game/levels/floor_1.level")},
		{"arena", #load("../../game/levels/arena.level")},
	},
	world_create      = world_create,
	world_destroy     = world_destroy,
	extra             = extra,
	init              = init,
	tick              = tick,
	scripted_input    = scripted_input,
	scripted_commands = scripted_commands,
	scripted_profile  = scripted_profile,
	save              = save,
	bench_prepare     = bench_prepare,
	// The game's row (today's play on Floor 1), and the crowd's on the arena (director.odin, Crowd): what sleepers,
	// a crowd on the move and a crowd in a fight cost at the most any floor holds.
	benches           = {
		{
			what     = "floor 1: four heroes against a held surge among the props",
			entities = BENCH_FLOOR_MINIONS,
			ticks    = 600,
		},
		{
			name     = "crowd_idle",
			what     = "the arena: a crowd asleep out of sight of four heroes standing still",
			setup    = "floor=arena,crowd=idle",
			entities = MINION_CAP,
			ticks    = 600,
		},
		{
			name     = "crowd_chase",
			what     = "the arena: a crowd chasing four heroes who walk and never attack",
			setup    = "floor=arena,crowd=chase",
			entities = MINION_CAP,
			ticks    = 600,
		},
		{
			name     = "crowd_fight",
			what     = "the arena: a crowd around four heroes who hold Attack, the felled rising again",
			setup    = "floor=arena,crowd=fight",
			entities = MINION_CAP,
			ticks    = 600,
		},
	},
}

// The tick's timing zones (sim.zone): the dev UI's stacked graph, and the groups its draw toggles name.
Zone :: enum u8 {
	Presence,
	Commands,
	Heroes,
	Director,
	Minions,
	Physics,
	Strikes,
	Props,
	Health,
}

// One tick: the systems in their order, each group a timing zone.
tick :: proc(t: ^Tick) {
	{
		sim.zone(t, Zone.Presence)
		update_presence(t) // first: people come and go while paused
		apply_pause(t) // the pause's own command is read on paused ticks too
	}
	if t.paused do return // the co-op pause: no system runs, physics.step included
	{
		sim.zone(t, Zone.Commands)
		apply_dev_commands(t)
	}
	{
		sim.zone(t, Zone.Heroes)
		revive_heroes(t) // first: the press that starts a revive grabs nothing
		face_heroes(t)
		use_hands(t) // after facing: a grab takes what the hero now faces
		use_abilities(t) // after the hands: hands full start none
		start_attacks(t) // after the hands and abilities: a throw's or a charge's Attack press starts no attack
		update_holds(t)
		move_heroes(t)
	}
	{
		sim.zone(t, Zone.Director)
		locate_heroes(t)
		raise_surges(t)
		wake_packs(t)
	}
	{
		sim.zone(t, Zone.Minions)
		target_heroes(t)
		move_minions(t)
	}
	{
		sim.zone(t, Zone.Physics)
		physics.step(t.world.phys)
		read_back_heroes(t)
	}
	{
		sim.zone(t, Zone.Strikes)
		t.world.strike_grid = false // the first query below builds it (strike_grid): a tick without one builds none
		resolve_strikes(t) // after the step: a blow lands on where things are now
		charge_strikes(t)
		fly_bolts(t)
		fly_fireballs(t)
		prop_hits(t)
	}
	{
		sim.zone(t, Zone.Props)
		prop_impacts(t)
		age_throws(t)
	}
	{
		sim.zone(t, Zone.Health)
		age_minions(t) // after the step: a swing lands on where the hero is now
		check_wipe(t)
	}
}
