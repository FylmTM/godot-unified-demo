// Crypt Crew's GDExtension (game/crypt_crew.gdextension -> .out/bin/): the crypt_crew sim run by unified:godot, plus
// the game's glue (this file). The views and the frame are frame.odin, the HUD's session data hud.odin, and how the
// InputMap and the mouse become an Input input.odin. Built by `uni build` (and by every command that runs the game).
package crypt_crew_extension

import "unified:godot"

import g "../crypt_crew"

// What the game gives unified's Godot host: its input sampler, its frame filler, its session data and the input
// values its scripts set.
GLUE := godot.Glue(g.Game, View, MultiView) {
	sample_input = sample_input,
	fill_frame   = fill_frame,
	data         = Data,
	input_values = Input_Values,
}

// The extension's entry point, named by game/crypt_crew.gdextension.
@(export, link_name = "crypt_crew_init")
crypt_crew_init :: proc "c" (
	get_proc_address: godot.Get_Proc_Address,
	library: godot.Class_Library,
	initialization: ^godot.Initialization,
) -> godot.Init_Result {
	return godot.init(&g.GAME, GLUE, get_proc_address, library, initialization)
}
