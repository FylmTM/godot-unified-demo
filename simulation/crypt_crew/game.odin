// crypt_crew (README.md): 1-4 players move capsules on a floor and throw balls straight up.
//
// The files, by feature: game (this: the descriptor and the tick), input (the input and the commands), state, events,
// players, balls, the co-op pause (pause) and the scripted inputs (script).
package crypt_crew

import "unified:sim"

PLAYERS :: 4 // input slots: the most players in the game at once
TICK_HZ :: 64

// The game's version (sim.Game.version, part of the netcode's compat): bump it when a rule or constant changes what a
// tick computes without changing the State or Input layout, or two builds desync instead of refusing each other.
VERSION :: "1"

// The game's types for unified:sim: no World (no physics, no level).
Game :: sim.Game(State, Input, sim.No_World, Event, Command, sim.No_Setup, sim.No_Profile, PLAYERS)
// What every system gets: the state, the inputs and commands, the tick's player changes.
Tick :: sim.Tick(Game)

// The game: what the headless binary, the GDExtension and the tests run. Its optional hooks are documented on
// sim.Game's fields (`uni doc sim Game`); levels go inline (it is @(rodata)):
// `levels = {{"meadow", #load("../../game/levels/meadow.level")}}`.
@(rodata)
GAME := Game {
	name              = "crypt_crew",
	version           = VERSION,
	tick_hz           = TICK_HZ,
	tick              = tick,
	scripted_input    = scripted_input,
	scripted_commands = scripted_commands,
}

// One tick: the systems in their order (README.md, Systems).
tick :: proc(t: ^Tick) {
	place_new_players(t) // presence first: people come and go while paused
	apply_pause(t) // commands are read on paused ticks too
	if t.paused do return // the co-op pause: no system runs (a physics game returns before physics.step)
	move_players(t)
	throw_balls(t)
	move_balls(t)
}
