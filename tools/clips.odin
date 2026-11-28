// `uni clips`: the README's clips and stills (docs/media/), made again from the game's recordings whenever the game
// changes. One table (CLIPS) says what each clip shows: its recording, the event it is cut around (`uni render --at`,
// so a recording made again keeps its clip on the same moment), its size, frame rate and whose view; another (SHOTS)
// the stills, the look-dev scene's shots. Each clip is a `uni render` of its row; the sizes are printed and a GIF over
// GIF_LIMIT fails the command (a README's clips load on every visit).
//
// The recordings: the two-player plays are replay regressions (simulation/tests/replays/<name>, recorded by `./uni
// coop --rerecord <name>`: game/tools/coop_<name>.gd), the crowd a driven single-player session (crowd_drive) kept in
// its drive instance's user data. `--record` makes them all again first, so the clips follow a change to the sim.
package main

import "core:fmt"
import "core:os"
import "core:strings"

import "unified:cli"

// What a clip is made from and how it is cut.
Clip :: struct {
	name:      string, // docs/media/<name>.gif
	recording: string, // a replay regression's name, or CROWD (crowd_drive's)
	at:        string, // the event it is cut around (render --at: Event_Name[#n]); "": from..to instead
	before:    string, // with `at`: how long before it the clip starts, and after it ends
	after:     string,
	from:      string, // without `at`: where it starts and ends in the recording
	to:        string,
	size:      string, // each view's (side by side: each pane's)
	fps:       int,
	player:    string, // whose view (render --player: P<n>, or "1,2" side by side)
	budget:    f64, // the size it is meant to stay within (MB): printed beside it, not enforced
}

// The crowd's recording: crowd_drive's session (CROWD_INSTANCE's user data), not a replay regression.
CROWD :: "crowd"
CROWD_INSTANCE :: "clips"

// A GIF bigger than this (bytes) fails the command.
GIF_LIMIT :: 4 << 20

// The two-player plays `--record` records again (`uni coop --rerecord <name>`), in order.
PLAYS :: []string{"lan_pair", "haul", "king"}

// docs/media/: the README's media.
MEDIA_DIR :: "docs/media"

// The look-dev shots' size.
SHOT_SIZE :: "1280x720"

// The README's clips.
CLIPS :: []Clip {
	// The hero clip: the King's first slam, its braziers burning, both heroes at it (the Barbarian's view: the
	// Knight's camera keeps the far wall in frame there).
	{
		name      = "hero",
		recording = "king",
		at        = "Event_Boss_Slam",
		before    = "3s",
		after     = "3s",
		size      = "720x405",
		fps       = 10,
		player    = "2",
		budget    = 3.5,
	},
	// The bad link: both players' views of the carry past the roller and across the spikes, to its set-down in the hall.
	{
		name      = "haul_coop",
		recording = "haul",
		at        = "Event_Hoard_Dropped#1",
		before    = "4.5s",
		after     = "0s",
		size      = "400x225",
		fps       = 10,
		player    = "1,2",
		budget    = 3,
	},
	// The crowd: five hundred skeletons closing on a hero standing still (the camera still).
	{
		name      = "crowd",
		recording = CROWD,
		from      = "1.5s",
		to        = "5.5s",
		size      = "480x270",
		fps       = 10,
		player    = "1",
		budget    = 3,
	},
	// The set pieces: the hoard carried onto the lift's deck, the lift boarding and going down.
	{
		name      = "setpieces",
		recording = "haul",
		at        = "Event_Lift",
		before    = "3s",
		after     = "3s",
		size      = "480x270",
		fps       = 10,
		player    = "1",
		budget    = 2.5,
	},
	// The ragdoll: the downed Knight heaved, thrown and landing.
	{
		name      = "ragdoll",
		recording = "haul",
		at        = "Event_Heave_Landed",
		before    = "2s",
		after     = "2s",
		size      = "480x270",
		fps       = 10,
		player    = "1",
		budget    = 1.5,
	},
	// The King: its ward broken together, the Knight lighting the second brazier.
	{
		name      = "king",
		recording = "king",
		at        = "Event_Boss_Ward#2",
		before    = "4s",
		after     = "2s",
		size      = "640x360",
		fps       = 12,
		player    = "1",
		budget    = 2.5,
	},
	// The regression: the prop thrown at the ring of 32 (the LAN recording, a test).
	{
		name      = "regression",
		recording = "lan_pair",
		at        = "Event_Prop_Thrown#5",
		before    = "1.5s",
		after     = "2.5s",
		size      = "640x360",
		fps       = 12,
		player    = "1",
		budget    = 2,
	},
}

// The README's stills: look-dev shots (`uni tool lookdev --shots`: game/lookdev/lookdev.gd's), by name, each written
// as docs/media/<name>.png.
SHOTS :: []string{"heroes", "vault_lit", "hub", "crypt_wide"}

Clips_Opts :: struct {
	record:   bool `usage:"first record every clip's recording again: the plays (uni coop --rerecord) and the crowd (a uni drive session)"`,
	overflow: [dynamic]string `hint:"[name]" usage:"one clip or still by its name (default: all of them)"`,
}

// `clips -h`'s details.
clips_details :: proc() -> string {
	b := strings.builder_make()
	fmt.sbprintf(
		&b,
		"Writes %s/<clip>.gif and <still>.png. The clips (a GIF over %d MB fails):\n",
		MEDIA_DIR,
		GIF_LIMIT >> 20,
	)
	for clip in CLIPS {
		cut :=
			clip.at != "" ? fmt.tprintf("%s -%s +%s", clip.at, clip.before, clip.after) : fmt.tprintf("%s to %s", clip.from, clip.to)
		views := fmt.tprintf(", player %s", clip.player)
		fmt.sbprintf(
			&b,
			"  %-11s %-9s %s, %s at %d fps%s (meant for %.1f MB)\n",
			clip.name,
			clip.recording,
			cut,
			clip.size,
			clip.fps,
			views,
			clip.budget,
		)
	}
	fmt.sbprintf(&b, "The stills, look-dev shots at %s: %s", SHOT_SIZE, strings.join(SHOTS, ", "))
	return strings.to_string(b)
}

cmd_clips :: proc(args: []string) -> cli.Result {
	opts: Clips_Opts
	cli.parse(&opts, args)
	if len(opts.overflow) > 1 do cli.usage("one name at most: uni clips [name] [--record]")
	only := len(opts.overflow) == 1 ? opts.overflow[0] : ""
	if only != "" {
		known := false
		for clip in CLIPS do known ||= clip.name == only
		for shot in SHOTS do known ||= shot == only
		if !known do cli.usage("no clip or still %q (uni clips -h lists them)", only)
	}
	media := cli.join(cli.state.project.root, MEDIA_DIR)
	cli.make_dirs(media)
	if opts.record {
		for play in PLAYS {
			if only == "" || uses(only, play) do uni("coop", "--rerecord", play)
		}
		if only == "" || uses(only, CROWD) do crowd_drive()
	}
	lines: [dynamic]string
	failed: [dynamic]string
	for clip in CLIPS {
		if only != "" && clip.name != only do continue
		out := cli.join(media, fmt.tprintf("%s.gif", clip.name))
		cmd := render_cmd(clip.recording, out)
		if clip.at != "" {
			append(&cmd, "--at", clip.at, "--before", clip.before, "--after", clip.after)
		} else {
			append(&cmd, "--from", clip.from, "--to", clip.to)
		}
		append(&cmd, "--size", clip.size, "--fps", fmt.tprint(clip.fps))
		append(&cmd, "--player", clip.player)
		uni(..cmd[:])
		bytes := file_bytes(out)
		line := fmt.tprintf(
			"%-15s %5.2f MB (meant for %.1f)",
			fmt.tprintf("%s.gif", clip.name),
			f64(bytes) / f64(1 << 20),
			clip.budget,
		)
		if bytes > GIF_LIMIT {
			line = fmt.tprintf("%s  OVER %d MB", line, GIF_LIMIT >> 20)
			append(&failed, clip.name)
		}
		append(&lines, line)
	}
	shots := false
	for shot in SHOTS {
		if only != "" && shot != only do continue
		if !shots do uni("tool", "--window", "--shots", "--size", SHOT_SIZE, "lookdev")
		shots = true
		out := cli.join(media, fmt.tprintf("%s.png", shot))
		cli.copy_file(out, cli.join(cli.state.project.out, "shots", "lookdev", fmt.tprintf("%s.png", shot)))
		append(&lines, fmt.tprintf("%-15s %5.2f MB", fmt.tprintf("%s.png", shot), f64(file_bytes(out)) / f64(1 << 20)))
	}
	for line in lines do fmt.println(line)
	if len(failed) > 0 {
		return {
			ok      = false,
			summary = fmt.aprintf("clips FAILED: over %d MB: %s", GIF_LIMIT >> 20, strings.join(failed[:], ", ")),
		}
	}
	return {ok = true, summary = fmt.aprintf("clips: %d files in %s", len(lines), MEDIA_DIR)}
}

// Whether clip `name` is made from `recording` (a still is made from none).
uses :: proc(name, recording: string) -> bool {
	for clip in CLIPS do if clip.name == name do return clip.recording == recording
	return false
}

// `uni render <recording> --out <out>`'s start: a replay regression by its name, the crowd by its folder.
render_cmd :: proc(recording, out: string) -> [dynamic]string {
	cmd: [dynamic]string
	append(&cmd, "render", recording == CROWD ? crowd_recording() : recording, "--out", out)
	return cmd
}

// The crowd's source: a single-player session on the arena under a held fighting crowd, its hero standing mid-arena
// (where it arrives) swinging, the crowd closing in; driven tick by tick (`uni drive`, headless), its recording left
// in the drive instance's user data (its recordings cleared first, so it holds this one alone).
crowd_drive :: proc() {
	cli.remove_tree(crowd_recordings())
	drive :: proc(args: ..string) {
		cmd: [dynamic]string
		append(&cmd, "drive", "--name", CROWD_INSTANCE)
		append(&cmd, ..args)
		uni(..cmd[:])
	}
	drive("--headless", "start", "--", "--autostart", "--setup", "floor=arena,crowd=fight")
	drive("pause")
	drive("step", "64") // the crowd risen and on its way
	drive("--timeout", "60", "press", "attack", "640") // ten seconds of swings, the hero standing
	drive("stop")
}

// Where the drive instance keeps its session recordings (its user data: .out/drive/<instance>/user/).
crowd_recordings :: proc() -> string {
	return cli.join(
		cli.state.project.out,
		"drive",
		CROWD_INSTANCE,
		"user",
		cli.state.project.games[0].name,
		"recordings",
	)
}

// The crowd's recording folder (the newest in crowd_recordings); stops the command when there is none.
crowd_recording :: proc() -> string {
	entries, err := os.read_all_directory_by_path(crowd_recordings(), context.temp_allocator)
	newest := ""
	if err == nil {
		for entry in entries {
			if entry.type == .Directory && entry.name > os.base(newest) do newest = entry.fullpath
		}
	}
	if newest == "" do cli.fatal("no crowd recording in %s: uni clips --record makes it", crowd_recordings())
	return newest
}

// Runs a `uni` command (this binary), its output ours; a failure stops the command.
uni :: proc(args: ..string) {
	cmd: [dynamic]string
	append(&cmd, cli.self_exe())
	append(&cmd, ..args)
	cli.must_run({cmd = cmd[:]}, fmt.tprintf("uni %s", strings.join(args, " ", context.temp_allocator)))
}

// A file's size in bytes (0: none).
file_bytes :: proc(path: string) -> i64 {
	info, err := os.stat(path, context.temp_allocator)
	return err == nil ? info.size : 0
}
