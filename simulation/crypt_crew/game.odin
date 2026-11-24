// crypt_crew (README.md): a top-down co-op dungeon crawler for 1-4 players, its rules as one deterministic sim that
// unified runs under rollback netcode.
//
// One system per file: game (this: the descriptor and the tick, its table of contents), tuning (every rule number),
// input (the input and the commands), state, events, world (the physics world, Floor 1's navigation and places,
// init and entering a level), presence (arrivals and leaves), heroes (facing, movement, read back), hands (grab,
// carry, drop, throw), props (their bodies, impacts and throws' ends), pause (the co-op pause), dev (the dev commands)
// and script (the scripted player).
package crypt_crew

import "unified:physics"
import "unified:sim"

PLAYERS :: 4 // input slots: the most heroes in the game at once
TICK_HZ :: 64 // ticks per second of game time

// The game's version (sim.Game.version, part of the netcode's compat): bump it when a rule or constant changes what a
// tick computes without changing the State or Input layout, or two builds desync instead of refusing each other.
VERSION :: "1"

// The game's types for unified:sim: a physics World, a Profile per player, no Setup yet.
Game :: sim.Game(State, Input, World, Event, Command, sim.No_Setup, Profile, PLAYERS)
// What every system gets: the state, the world, the inputs and commands, the tick's player changes.
Tick :: sim.Tick(Game)

// The game: what the headless binary, the GDExtension and the tests run (its hooks: `uni doc sim Game`).
@(rodata)
GAME := Game {
	name              = "crypt_crew",
	version           = VERSION,
	tick_hz           = TICK_HZ,
	levels            = {{"floor_1", #load("../../game/levels/floor_1.level")}}, // game/levels/floor_1.tscn's (uni bake)
	world_create      = world_create,
	world_destroy     = world_destroy,
	extra             = extra,
	init              = init,
	tick              = tick,
	scripted_input    = scripted_input,
	scripted_commands = scripted_commands,
	scripted_profile  = scripted_profile,
}

// The tick's timing zones (sim.zone): the dev UI's stacked graph, and the groups its draw toggles name.
Zone :: enum u8 {
	Presence,
	Commands,
	Heroes,
	Physics,
	Props,
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
		face_heroes(t)
		use_hands(t) // after facing: a grab takes what the hero now faces
		update_holds(t)
		move_heroes(t)
	}
	{
		sim.zone(t, Zone.Physics)
		physics.step(t.world.phys)
		read_back_heroes(t)
	}
	{
		sim.zone(t, Zone.Props)
		prop_impacts(t)
		age_throws(t)
	}
}
