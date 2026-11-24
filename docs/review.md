# For the developer's review

Small calls made without asking, and loose ends worth a look, collected for the end-of-development review. Each line
says what was decided or noticed and where. Delete a line once it is reviewed; delete the file when it is empty.

## Repo and CI

- The repo has GitHub Issues and outside PRs enabled, and the README takes no stance on them (the workflow uses
  neither). Turn them off, or point people at godot-unified's issues?
- The repo's Actions policy is GitHub's default (any action). unified's allows GitHub-owned actions only, pinned by
  SHA; ci.yml already pins by SHA, so tightening the setting costs nothing.
- Not yet exercised in CI: the nightly canary (first runs once unified's `main` moves past the pin) and a manual run
  with `-f unified_ref=...`.
- `.claude/settings.json` and `ols.json` come from unified's `uni refresh` (the "starters"; the agent's direct write
  of settings.json was blocked by the permission check).
- The game's name is `crypt_crew` (a game name must be an identifier); the window title (`project.godot`,
  `config/name`) still says `crypt_crew` until the app layer (milestone 3) sets "Crypt Crew".

## unified, changed on the way

- Game repos' `uni` shim was committed without its executable bit by every repo made on Windows (uniportal, unicells,
  unifusion, uniblock): a Linux or macOS clone couldn't run `./uni`. `init` now stages it executable, `refresh` fixes
  the index's mode, `vet` fails until then, so each of those repos gets the fix at its next unified bump.
- The starters a game gets (`.claude/settings.json`, `ols.json`) carry no permissions: the format hook only. unified's
  own `.claude/settings.json` still allows `uni drive *` without a prompt, which includes `drive eval` (any GDScript,
  so any command, in the running game). Narrow it to the safe verbs, or keep it?
- `odinfmt.json` is now kept at a game's root (the editor's format-on-save used a different style otherwise).
  `ols.json` and `odinfmt.json` at the root may end up in a Godot export: check at the release milestone.
- The format hook builds odinfmt on the first edit in a fresh repo (up to a minute once) instead of skipping it.
- `uni`'s import check now notices a changed `.import` (an asset's import settings), and unified's Godot rule no longer
  says never to edit one: a game sets its import settings there and commits them.

## Milestone 1: the art

- Rogue class is the hooded Rogue model with the two-handed crossbow (the pack textures its crossbows with the rogue
  atlas; the hood reads well from above). The Ranger and the bare-headed Rogue are not committed.
- World scale is KayKit's native (heroes about 2.4 m, a 4 m grid).
- The forest pack was dropped: its trees, bushes and grass looked wrong in the graveyard, and its rocks would have been
  walk-through decor in the play area. The hub is Halloween Bits only.
- The open-grave floor tile was dropped: its pit can't be walked over, and a floor that isn't flat needs its own design.
- No pack has a brazier: a column holding an unlit torch head (3 m) is the stand, a part that blocks shots like a wall;
  its fire is shown apart, since lighting braziers is the floor's goal.
- Large barrels, kegs, stacked crates and tables are scenery parts that never move; small barrels, boxes, chests and
  coins are what the sim will move.
- Collision categories: floor 1, wall 2, low cover 4, with low cover's model at most 1.5 m tall (graves and fences are
  walls; the hub's grave markers and skull are low cover parts now, not walk-through decor).
- Lighting: the braziers' fires cast shadows; wall torches, candles and lanterns don't (cost). Each hero carries a soft
  unshadowed light, prototyped in look-dev now rather than with the hero view. Crypt ambient raised, fog thinned.
- The side of a room toward the camera is low cover in the look-dev crypt, so walls never hide the heroes; a wall
  cutaway is a milestone 8 item.
- Clip loops live in `clips.gd` (`Clips.LOOPING`) and `CharacterRig.pose()` wraps them, rather than in each clip
  file's `.import`, which made those files about 1 MB of Godot's per-clip defaults.
- Textures are lossless without mipmaps (palette atlases); far floors may shimmer slightly in motion. Revisit if it
  shows in play.
- `godot-bindings` (unified's suite) failed its views timing test ("events arrive CONFIRMED ... never a frame late")
  in three of four runs while two other Godot jobs loaded the machine, and passed on an idle one. A timing test that
  flakes under load; not investigated further.

## Milestone 2: the first playable

- Joiners, rejoiners and respawns appear beside the party, not at the floor's start (the shared couch camera needs
  it). A hero at 0 HP goes down for a few seconds, then rises beside the party; the whole party down restarts the floor.
- Every hero carries and throws props (the hoard needs any two); the Barbarian's specialty comes with abilities.
- Heroes walk through crowds unslowed; minions yield to heroes and props. Minions appear only once verified.
- Throw: a press throws at a fixed speed (no charge). Classes are auto-assigned before menus exist.
- Minion death is a phase in the sim (so milestone 4's crowd can animate it), not a view linger.
- Mage bolts draw as a MultiMesh; one clip at a time for heroes (a layered upper body is polish).
- Shots land where the shooter saw them from milestone 2, not 5.
- unified gained `UnifiedSession.shown_time`, and `uni doc` fetches Box3D (it failed on physics in a game without it).
- Heroes, step 1: one `HERO_HP` (100) for every class for now; class speeds Knight 5, Barbarian 4.5, Mage 4.75, Rogue
  5.5 m/s (`tuning.odin`). The capsule floats 0.15 m on its pogo spring (`HERO_POGO_REST` 0.6), so its centre is
  1.25 m above the feet. A hero weighs about 80 kg (`HERO_DENSITY` 66) with a 4000 N drive (`HERO_GROUND_FORCE`):
  full speed in about a tenth of a second.
- `Action` has only `None` until the attacks land, so the hero view poses gaits only; one-shots at their age come with
  the first action (`CharacterRig.pose` already clamps a one-shot's time to its start). Gaits get a phase per player
  (its key) and a margin between stand, walk and run.
- Bindings: attack is the left mouse button, Space, a pad's right trigger or X; interact is E, the right mouse button
  or a pad's A; pause is Esc or a playing pad's Start.
- Devices (`game/play/couch.gd`): the first player reads every device until their first game input claims one (a pad,
  or the keyboard and mouse); an unclaimed pad's Start joins it as another player with class Any; a pad joining while
  the first player reads every device moves them onto the keyboard and mouse (undone if the session refuses the
  joiner). The mouse aims for whoever holds the keyboard, never within 0.5 m of the hero, and not while game input is
  off, nor while the dev UI holds the keyboard (godot.input_blocked, added to unified for it).
- A returning hero plays its Profile's class when it wishes for one, and the class it played when its wish is Any.
- `Input.reach` (in 0.25 m steps; 0: no point) rides in the Input from now, sampled from the mouse's distance or the
  stick's push times 10 m (`PAD_REACH`), scripted, and read by no rule yet: throws and ground-targeted casts will.
- The script changes each slot's class with `Command_Dev_Set_Class` every 384 ticks (Any among them), so the scenarios
  roll back over a class change.
- The camera: 55° pitch, field of view 35°, 18 to 28 m from the heroes' middle (1.2 m further per metre of spread),
  eased at 5/s, cut on a jump past 12 m. Walls still hide heroes behind them until the cutaway (milestone 8).
- `hero_spawn.gd` got `class_name HeroSpawn`, so the camera finds the spawns it frames before a hero is in.
- A hero's view warp is its own `Hero.warp` (which takes the old body's count when a body is made again) plus its
  body's `physics.body_warp`.
