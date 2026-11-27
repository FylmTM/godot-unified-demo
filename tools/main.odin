// crypt_crew's CLI (unified/src/cli/README.md): unified's public commands, plus this game's own: `clips` (clips.odin),
// the README's clips and stills. Run it through the shims, ./uni or uni.cmd; it rebuilds itself when a file here
// changes.
package main

import "unified:cli"

main :: proc() {
	cli.run(cli.public_commands(), game_commands())
}

// The game's own commands.
game_commands :: proc() -> []cli.Command {
	commands := make([]cli.Command, 1)
	commands[0] = {
		name    = "clips",
		summary = "the README's clips and stills in docs/media/: each clip a uni render of its recording cut around an event, each still a look-dev shot or a recording's frame; sizes printed, a GIF over 4 MB fails; --record: the recordings made again first",
		options = cli.option_types(Clips_Opts),
		details = clips_details,
		run     = cmd_clips,
	}
	return commands
}
