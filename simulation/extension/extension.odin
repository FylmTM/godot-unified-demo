// Crypt Crew's GDExtension (game/crypt_crew.gdextension -> .out/bin/): the crypt_crew sim run by unified:godot, plus
// the game's glue (this file). The views and the frame are frame.odin, the HUD's session data hud.odin, and how the
// InputMap and the mouse become an Input input.odin. Built by `uni build` (and by every command that runs the game).
package crypt_crew_extension

import "unified:eos"
import "unified:godot"

import g "../crypt_crew"

// What the game gives unified's Godot host: its input sampler, its frame filler, its session data, the input values
// its scripts set, and how its view kinds are shown.
GLUE := godot.Glue(g.Game, View, MultiView) {
	sample_input = sample_input,
	fill_frame   = fill_frame,
	data         = Data,
	input_values = Input_Values,
	view_policy  = VIEW_POLICY,
	multi_policy = MULTI_POLICY,
}

// The sim's numbers the views pose by (Unified.constants), copied once at install: what lines a clip's blow up with the
// sim's, and what game/tools/coop.gd checks an arrival by.
Data_Constants :: struct {
	class_windups:   [len(g.Class)]f32, // each class's attack windup in seconds, by EnumClass (Any's 0)
	class_cooldowns: [len(g.Class)]f32, // each class's attack cooldown in seconds: from one attack's start to the next
	minion_windup:   f32, // a minion's swing's windup in seconds
	minion_rise:     f32, // how long a risen minion climbs out of the floor in seconds (RISE_S: the rise clip's last)
	minion_death:    f32, // how long a dead minion's row lingers in seconds (DEATH_S: the crowd sinks it by then)
	arrival_ring:    f32, // how far from the party an arrival's first ring of spots is (metres; the second, twice)
	save_version:    u8, // the save this build writes and continues (Setup.version): the app reads a save by it
	_pad:            [3]u8,
	loot_life:       f32, // how long a coin lies before it goes, in seconds (LOOT_LIFE_S: the coins blink before)
}

// godot.init calls it once: the numbers from the sim's tuning.
constants :: proc() -> (constants: Data_Constants) {
	for class in g.Class {
		constants.class_windups[class] = f32(g.CLASS_SPECS[class].windup) / g.TICK_HZ
		constants.class_cooldowns[class] = f32(g.CLASS_SPECS[class].cooldown) / g.TICK_HZ
	}
	constants.minion_windup = g.MINION_WINDUP_S
	constants.minion_rise = g.RISE_S
	constants.minion_death = g.DEATH_S
	constants.arrival_ring = g.ARRIVAL_RING
	constants.save_version = g.SAVE_VERSION
	constants.loot_life = g.LOOT_LIFE_S
	return
}

// The extension's entry point, named by game/crypt_crew.gdextension.
@(export, link_name = "crypt_crew_init")
crypt_crew_init :: proc "c" (
	get_proc_address: godot.Get_Proc_Address,
	library: godot.Class_Library,
	initialization: ^godot.Initialization,
) -> godot.Init_Result {
	// online play: EOS lobbies and P2P (the SDK loads at run time: a build without it, or without the .env's
	// credentials, plays alone, on a couch and on the LAN, and UnifiedSession.online_problem says why not online)
	return godot.init(&g.GAME, GLUE, get_proc_address, library, initialization, eos.lobby({}), constants = constants)
}
