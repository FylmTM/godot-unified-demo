---
name: unified-godot
description: Checking, running and playing a unified game in Godot - the order to run the godot suite in, rebaking levels, play-checking a change with uni drive, and the windowed checks. Use after changing the game's GDScript, scenes, levels, extension or view contract, and when asked to run, play or look at the game.
---

# Checking the game in Godot

Every command builds a stale extension and re-imports changed files first. What each step proves: `./uni test -h`.

1. After a GDScript or scene change: `./uni test --suite godot --only validate`. It stops at the first strict error
   (no `uni` command lists them all): fix it and run it again.
2. After editing a level scene or its markers: `./uni bake`, and commit the `.tscn` and its `.level` together. A
   level whose geometry changed and whose `NavigationRegion3D` opts in (metadata `unified_nav_bake`): `./uni bake
   <game> --nav` bakes the navigation first. Walkers that stand still or float: `--report` shows the mesh the sim
   gets, instead of a test that dumps polygons (how to read it: `unified/src/navreport/README.md`).
3. Before handing back: the whole `./uni test --suite godot`, then `./uni verify`.

## Play-checking with uni drive

Play what you built, beside its tests (verbs: `./uni drive -h`):

1. `./uni drive start -- --autostart` (or the session flags, or the menus through `ui` and `click`). A script
   error fails `start` (as `res://file.gd:line`) and stops the game; one loaded later shows in `status`.
2. `pause`, then `press <action> <ticks>` or `step <n>`: paused, every tick is accounted for, so a check can say
   where a thing must be after n ticks. `values yaw=0.25` holds an input value (a first-person look) until
   `values clear`.
3. `state <path>` and `events` for what the sim computed; `shot`, then read the PNG, for what the player sees.
4. `stop`: it fails on errors or leaks in the game's log. An instance runs the code it started with: after a change,
   `stop` and `start` again.

Two at once: `start --name host -- --host-port 7000` and `start --name joiner -- --join 127.0.0.1:7000`, then
`--name` on every verb.

## A clip for a README

A clip is a recording the game plays back, so it is made again whenever the game changes and stays true to it:

1. Record what to show: play it (`./uni drive start -- --autostart`, then `press` and `step`; `stop` saves the
   session's recording under `.out/user/`, `UnifiedSession.recording` names it), or take a replay regression or the
   developer's F3 note (`./uni feedback`).
2. `./uni render <recording> --out docs/clip.gif --from 2s --to 12s` (`--player n`: whose view; `--speed`; `.avi` for
   a video with sound, a directory for PNG frames). The window opens like any agent's; the clip is frame-exact.
3. Read a frame or two (`--out .out/frames/`, then the PNGs) before committing the GIF. Keep it short and small:
   a camera that moves changes every pixel, so a few seconds at 15 fps is a few MB.

## Windows

Never disturb the developer: a window an agent opens starts muted in the top-left corner of the leftmost screen and never takes focus
(`drive start`, `tool --window` and `coop --window` always do; `run` takes `--mute --screen left --background`). The
editor takes focus: open it only when asked. `./uni tool <script> --window --shots` saves PNGs under `.out/shots/`
(`--size WxH` for a look at another window size: one bigger than the leftmost screen moves just left of every screen;
`--offline` keeps a look pass off EOS where .env sets it up);
`./uni coop` plays a host and a joiner (`--menus`: each starts through the game's own menus, its coop.gd's
`_start_host` / `_start_join`). Read the PNGs to check that what you changed looks right.
