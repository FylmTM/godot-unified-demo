// Crypt Crew's GDExtension (game/crypt_crew.gdextension -> .out/bin/): the crypt_crew sim run by unified:godot, plus
// the game's glue (this file). The views and the frame are frame.odin, the HUD's session data hud.odin, and how the
// InputMap and the mouse become an Input input.odin. Built by `uni build` (and by every command that runs the game).
package crypt_crew_extension

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
// sim's.
Data_Constants :: struct {
	class_windups: [len(g.Class)]f32, // each class's attack windup in seconds, by EnumClass (Any's 0)
	minion_windup: f32, // a minion's swing's windup in seconds
}

// godot.init calls it once: the windups from the sim's tuning.
constants :: proc() -> (constants: Data_Constants) {
	for class in g.Class do constants.class_windups[class] = f32(g.CLASS_SPECS[class].windup) / g.TICK_HZ
	constants.minion_windup = g.MINION_WINDUP_S
	return
}

// The extension's entry point, named by game/crypt_crew.gdextension.
@(export, link_name = "crypt_crew_init")
crypt_crew_init :: proc "c" (
	get_proc_address: godot.Get_Proc_Address,
	library: godot.Class_Library,
	initialization: ^godot.Initialization,
) -> godot.Init_Result {
	return godot.init(&g.GAME, GLUE, get_proc_address, library, initialization, constants = constants)
}
