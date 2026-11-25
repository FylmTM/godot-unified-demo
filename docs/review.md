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
- The hero view poses a one-shot at its age (`CharacterRig.pose` clamps a one-shot's time to its ends), else a gait
  with a phase per player (its key) and a margin between stand, walk and run.
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
- Props, step 2: barrel 30 kg (a 12-sided cylinder, 1.0 by 1.02 m), crate 20 kg (1 m cube), heavy crate 60 kg (1.5 m
  cube), sizes measured from the models; carrying slows to 0.85 of the class's speed (0.65 with a heavy crate). Every
  hero carries and throws every kind, the heavy crate too.
- Grab reach: 1 m from the capsule to the prop's side, a 50° cone either side of the facing (or 0.25 m in any
  direction); a hold puts the prop's centre 1.4 m above the feet, 0.1 m clear of the capsule, its force capped at 3×
  its weight.
- Throw on Attack's press (not held, so an attacker holding Attack doesn't throw what it just picked up): 11 m/s along
  the facing plus 3.5 m/s up, set as a velocity, letting go 0.25 s into a 0.5 s action; the prop ignores its thrower
  until 2.5 m clear or 1 s. No input reaches the hands while a throw winds up.
- Actions: a pick-up lasts 0.625 s, a throw 0.5 s. The hero view starts the pick-up clip 0.25 s in and the throw clip
  0.4 s in (past its draw-back), so the arm comes through at the release. No KayKit clip holds a load, so a carrying
  hero walks with plain gaits.
- The grab highlight is an additive warm overlay on the prop's meshes (`game/fx/highlight.tres`).
- Props hit at 3 m/s or faster emit `Event_Prop_Impact` (the world's hit threshold), for a thud later.
- `game/tools/art_checks.gd` now holds `game/levels/*.tscn` to the stages' placement rules (no category or script
  override, unscaled, floors and walls on the grid).
- Minions, step 3: radius 0.4 m, 3.2 m/s chasing, 30 HP; a swing reaches 0.8 m past both circles, winds up 0.5 s,
  lands only within 60° of the facing it locked on, for 10 HP, and the whole attack takes 1 s. Rise 1.5 s (the view
  plays the clip's last 1.5 s), death 2 s. A minion without a target picks one at once, then every 0.25 s (sliced).
- Minions are pushed out of every hero's capsule and every prop held or slower than 1 m/s (a footprint circle per kind:
  barrel 0.5 m, crate 0.6, heavy crate 0.9); the circles come from the block at the start of the minions' pass, not
  from after the step (scratch kept across ticks would break rollback).
- Director: packs within 1.6 m of their marker (keyed rolls naming tick 0 and the marker, so a restart puts them back),
  waking at 9 m in sight (walls block, low cover doesn't); surges every 20 s from 6 s in, 3 + 2 per hero present, at
  graves 10 to 30 m of path from the party (no such grave: no surge), capped at 40 alive.
- Down: 4 s, then a rise beside the party with 2 s of grace (the view blinks). A wipe is every hero present down on
  one tick; with one hero, any downing is a wipe.
- Arrival: the anchor is the lowest-slot hero up that didn't itself arrive this tick, so a session's first players
  each take their own spawn; ring spots must be reachable in a straight line over no wall or low cover, tested 0.5 m
  above the floor.
- `View_Hero` has no `down` field: `action == Down` says it (the death clip held). `Data_Hud` carries kills and the
  minions alive.
- An extra dev command, `dev_kill_minions` (every live minion takes a killing blow through `damage_minion`); the
  script raises minions (slot 1) and kills them (slot 2) now and then, so the scenarios cross spawns and mass deaths
  whatever the attacks reach.
- The benchmark row: "floor 1: four heroes against a held surge among the props", 40 minions held at graves.
- Review fixes, steps 2 and 3: a downed hero isn't limp: its velocity is zeroed and its drive holds it still with no
  move (the death pose rests on the floor at its feet). A leaver ends its throws' ignores at once (end_throws_by),
  paused ticks included.
- Director rolls name state, never the tick: each raised minion's rolls are keyed by the session's count of raised
  minions (`State.rises`, never reset); `surges` counts the session's surges too. A grave is out of sight at 10 m in a
  straight line from every hero up, and within reach at 30 m of path from the nearest.
- Packs: laid out in world_create on rings 1 m apart (the first of 12 turns where every member stands on the floor
  within 0.3 m and 0.9 m from the rest), the same for every seed; a pack that doesn't fit fails the level. A pack wakes
  as a whole, on sight or on a hit to any member (`Minion.pack`).
- Arrival: two rings (2.5 m, then 5 m), each spot also clear of heroes and props by 0.1 m; with none, the slot's
  hero_spawn (never inside the anchor).
- A swinging minion keeps its target and needs sight (a wall-blocked ray misses); grabbing needs no wall between chest
  and prop; `hands_target` gates on the hands being free (up, not throwing, not holding).
- `dev_hurt` with player 0 hurts the sender's own hero (the stateless script downs heroes that way, all four every
  third round, so the scenarios cross a wipe); `dev_kill_minions` deals MINION_HP to each.
- Views: flashes and the grace blink run on the shown game time; a chaser that isn't moving stands. The HUD counts kills
  from CONFIRMED `EventMinionDied` (from when the HUD began: a late joiner's count starts at 0); "Skeletons" stays the
  prediction. `View_Hero.carrying`, `View_Prop.held_by` and `State.kills` are gone.
- The minion grid is laid over the mesh's extent in world_create (at most 1024 cells of 3 m: 96 m by 96 m).
- Attacks, step 4: Knight 18 damage, 1.8 m, 50° either side, 0.25 s windup, 0.5 s cooldown; Barbarian 30, 2.3 m, 80°,
  0.44 s windup, 1 s cooldown, knock 9; Mage bolt 14 m/s for 1.5 s (21 m), 20 damage plus an 8-damage burst within
  1.5 m (walls shield it), 0.625 s cooldown; Rogue crossbow 25 m, 30 damage, 0.75 s cooldown, look-back capped at
  0.125 s. A hero attacking moves at 0.6 of its speed. Attack is read held; a hero carrying a prop throws instead.
- A blow, a bolt and a shot shove the props they strike (a velocity change, so every mass alike); what they strike is
  under the flight rules below. The Mage's bolt ignores `Input.reach` (it flies its full range); the crossbow never
  pierces.
- Thrown props: faster than 4 m/s while their throw runs, each minion they meet takes 25 and a knock of 7, once per
  throw (at most 6), and the prop keeps 0.7 of its velocity per hit; a prop's bottom higher than 1.8 m passes over.
- `Event_Minion_Hit` and `Event_Minion_Died` carry a `source` (blow, bolt, crossbow, prop, dev). The minion grid's cells
  are 3 m (the cleave's reach and a minion's radius fit a 3 by 3 query).
- Views: each attack clip is timed so its blow, sampled from the clip (the hand's fastest moment), lands at the class's
  windup, which the extension hands the views as constants. Every bolt draws as the same violet orb, BOLT_RADIUS wide
  (a colour per caster waits on per-instance colour in the MultiMesh). The Rogue's shoot clip stands side-on, so the
  rig turns a quarter while the Rogue shoots (the crossbow along the facing), and its release is the recoil (0.375 s
  into the clip), not the raise.
- The crossbow's tracer is a glowing additive beam (a gradient across a flat quad) that fades in 0.15 s; Kenney's
  dotted trace texture is gone.
- `tests/bot.odin` fights the nearest skeleton (melee walks up, Mage and Rogue stand off at 7 m); in every other 2 s
  window it picks up a prop within 1.6 m that no wall hides (out of it, it gives up) and throws what it carries at the
  nearest skeleton, or anywhere; slot 0 raises skeletons every 10 s. The playthrough checks each slot plays its
  Profile's class and counts every hit of every tick.
- Close-out, step 5: `game/tools/coop.gd` checks, on each side, the joiner's hero arrives within the farther arrival
  ring and a metre of the host's (`Unified.constants.arrival_ring`, the sim's); the joiner stands 3 s first, so the
  host sees it where it arrived. The host then raises four skeletons (a dev command) and swings until a hit is
  confirmed.
- The replay regression `replays/lan_pair` is the host's recording of a two-player LAN session driven by two
  `uni drive` instances, about 90 s: Knight and Barbarian, then Mage and Rogue, three throws, kills, surges and a dev
  down. A session ended by the app quitting keeps its recording since unified f9ccbaa.
- The reference run is pinned at 2400 ticks with its snapshot at 1200: it crosses the script's first wipe and several
  surges.
- Review fixes, steps 4 and 5 (VERSION "2"): bolts in flight go with a floor restart (`enter_level`). An attack ends in
  `start_attacks` once its duration ran, before the press is read, so a held attack repeats every cooldown (it was
  every cooldown and a tick).
- A blow strikes whatever touches the hero, in any direction: within STRIKE_TOUCH (0.15 m) of its capsule
  (STRIKE_BACK, 0.5 m from its centre, never fired: minions are pushed out to 0.85 m). Props too; a blow shoves only
  props it sees chest to chest (no wall between) whose height overlaps a skeleton's.
- A thrown prop stops hurting once its hits slow it under PROP_HIT_SPEED (checked before each hit): from a throw's
  11 m/s that is three hits, so PROP_HITS_MAX (6) binds only a faster prop. A burst at a minion is centred where the
  orb met it (the sweep counts its radius); only a wall or a prop pushes it back by BOLT_RADIUS. A class change ends
  an attack of the old class.
- What flies over what: bolts and shots fly at FLIGHT_HEIGHT 1.35 m and meet what stands into the ray (SHOT_FILTER
  now holds low cover too, so geometry decides). Low cover's colliders top out at LOW_COVER_TOP 1.1 m and walls'
  start at 1.4 m (art checks); BOLT_RADIUS is 0.2 m (was 0.25), so the orb clears low cover and resting barrels and
  crates by at least 5 cm, and a heavy crate (1.5 m), a held or a flying prop is met.
- Parts judged by their models: the column (a 1.4 m post) is a wall; the barrier's column and corner pieces, the
  coffin and the grave markers are low, their colliders lowered to 1.1 m (the post caps, candles and cross tops above
  are trim the orb may graze). The levels and the look-dev stages' navigation are re-baked.
- Views: an attack clip whose blow comes later than the windup (Mage, Barbarian) plays its lead-in slowed over the
  windup, so it moves from the first tick. Between held attacks the clip holds its last frame until the cooldown ends
  (the view, from `Unified.constants.class_cooldowns`), not by stretching the duration, which would slow the hero
  longer. Effect pools hold 48 (a cleave or a burst into a full crowd). The tracer starts at the drawn crossbow.
- Rewind under rollback: unified zeroes a scripted input's Seen (`sim.scripted_player_input`: a script saw no screen),
  so no standard scenario can stamp one; the crossbow test, a sync-tested Run with seen 5 and 14, runs the rewind
  under rollback in the default tier.

## Milestone 3: the app layer

Decided by the developer from the two designs:

- Font: Kenney Fonts (CC0), keeping the CC0-only rule.
- Friends: the join code is the invite (Copy, Rejoin last game); a friends list and platform invites wait on an
  account service (plan.md, Needed from unified).
- Pauses: single player (couch included) pauses from the menu; online the menu is an overlay and "Pause for everyone"
  its own button; anyone resumes; the State gains `paused_by`.
- Save: floor, surges faced, skeletons felled, saved at each surge; one slot, written by the host or single player; a
  joiner keeps it in memory and gets "Continue on your own".
- Canvas base 1920×1080 with the UI pack's Double art; the window stays 1280×720.
- Audio settings: Master and Interface now; Music and Effects with their content (milestone 8).
- Player 0's device: free while alone, fixed only while a couch guest is in.
- The flow autoload is `Game`, with `quit_app(exit_code)` (UnifiedTool looks it up by that name).
- Library gaps are built in unified when a step needs them, not worked around.

Step 1, the app's skeleton, calls made on the way:

- Faces (the review's call): Kenney Mini Square for everything, Kenney Future for the game's name on the title.
- Pack folders `assets/kenney/ui/`, `fonts/`, `interface_sounds/`; only the Double PNGs, of the brown family:
  `button_brown`, `panel_brown_corners_a` (parchment), `panel_brown_dark` (HUD plates and toasts,
  darkened to 0.6 and 90 % opaque so they sit behind the crypt), `banner_hanging`. The focus is a gold frame
  (a StyleBoxFlat), not a pack piece. The theme was made once by a throwaway script and is edited as text since.
- Sounds: `select_002` (the focus moves), `click_002` (a press), `confirmation_002` (New game), `error_004` (a
  dialog), `maximize_003` and `minimize_003` (a join, a leave). Picked by name, not by ear: worth a listen.
- The user data folder is `crypt_crew` again through `config/use_custom_user_dir` (the window title is now "Crypt
  Crew"): on Windows `%APPDATA%/crypt_crew`, no longer under `Godot/app_userdata/`. Nothing was there to move.
- `Game.start_single()` is the menus' one start for now; the design's start request (kind, code, Setup, party) comes
  with hero select, when it has more than one field.
- The title is one screen with no screen stack yet; the stack comes with the settings screen (step 2).
- Toasts already announce joins and leaves by name (from CONFIRMED events; the first local player's own join is no
  news); step 3 adds the class.
- The HUD is restyled into plates (each local hero's class and HP as text, the skeletons up and felled, the "Paused"
  banner, the join hint); the HP bar comes with step 3's hero plates, which also need the heroes' full HP from the
  extension.
- Esc still sends the co-op pause in every mode until step 4's pause menu; the walk checks the banner.
- The tagline "Down into the crypt, one to four heroes." is placeholder copy.
- Hovering a button gives it the focus, so the mouse and a pad never show two highlights.
- The play scene loads on a worker thread while the title is up (Game), collected at the switch and at a quit.
- A run whose session quits the app at its end (`--quit-at-end`: the godot suite's session step) skips the menu:
  going back to the title played sounds that outlived the quit (a leak the step failed on).
- `LibraryCheck` is kept from the Fable design (the Opus one left it to milestone 10).
- `ArtChecks` takes TTF and Ogg files and counts what the project's theme uses; `AppChecks`
  (`game/tools/app_checks.gd`) holds the autoload order, the theme's variations, a HUD that takes no click or focus,
  menu buttons that take the focus, and every button's named sound.
- `coop.gd` now checks the joiner lands on the title with a dialog once the host has left.

Step 1's review fixes, calls made on the way:

- Pads press and back out: `ui_accept` and `ui_cancel` carry the pad's A and B in `project.godot`.
- Every button's sound and hover-takes-focus live in Game, hooked from `_enter_tree` with one walk of the tree as it
  stands, guarded against a second connection. A button is the game's when its scene (its own, or its owner's) is
  under `res://game/`: the library's dev UI builds its controls in code, so it has neither. Sfx only plays.
- Modals (Dialog, Connecting) share a `Modal` base: the focus wandering outside is taken back, and the control it
  went to is where it returns; with none left, the screen's default (the `default_focus` group: New game). The
  title takes the focus only when nothing has it. `Focus.trap` is gone; the modal's button names itself (".") as
  every neighbour in its scene.
- A link in trouble in play is `LinkStatus`, a plate (not Connecting): catching up shows after 0.5 s; reconnecting
  shows at once with "Leave game", which takes the focus only on an up or down press while nothing has it. The
  game's input stays on. Connecting is only for starts, so Esc cancels only then.
- Cancel hides Connecting at once; a new start waits for the goodbye (Game ignores a start while the flow isn't MENU).
- Settings are JSON (`user://settings.json`), not a ConfigFile: Godot reports a damaged ConfigFile as an engine
  error, which no check could exercise. A file that doesn't parse is kept as `.bad` and the reason is
  `Settings.read_problem` and a printed line, not a warning (uni fails a run on any game warning). `--settings-path=`
  names another file; the app checks round-trip one.
- An export opens fullscreen through `display/window/size/mode.template=3` (borderless fullscreen), the default the
  Video setting matches, so there is no windowed first frame.
- Toasts sit low in the middle, clear of the HUD's corners and its Paused banner, and go when the flow is back at
  the menu.
- The dialog's body is the library's reason as a sentence ("Online play is not available in this build."), the
  generic sentence only without one; a disconnect keeps the app's sentence and shows the library's words small
  under it, since only they say which it was (until step 5's end reason).
- The title's Quit is a plain button: the red one is for confirmations (`button_red` is no longer vendored).
- The focus frame pulses (Game, on the theme's shared stylebox); Dim captions are 26 px at 75 %.
- Real boot (the main scene loaded by the engine) is checked by hand under `uni drive` (no flags: New game wired and
  focused; `--join`: Cancel focused under Joining). No suite step can: the walk runs as a `-s` script, and the
  library's drive step starts with `--autostart`. A drive step option to boot to the menu would be unified work.
- Pause and the couch's join ignore their keys while the game's input is off; so does the couch's device claim.

Step 2, settings, bindings and prompts, calls made on the way:

- Prompt glyphs are Kenney Input Prompts' fonts with their glyph maps (the Opus design), not its PNGs (the Fable
  one): four fonts and four maps cover every bindable key, crisp at any interface size and in a label's colour. Four
  families: keyboard and mouse, Xbox, PlayStation, Switch (no Steam Deck: an unknown pad is drawn as Xbox). The maps
  are read as files, which a Godot export leaves out unless its filter names them (plan.md, Needed from unified).
- `Prompts` is an autoload (`prompts.tscn`, the fonts as its exports) between Sfx and Game.
- Rebindable: on the keyboard the four moves, attack and interact; on a pad attack and interact (its stick and D-pad
  move, fixed; no "Swap sticks"). Two slots per action per scheme, one scheme per machine. Reserved: Esc, Enter,
  numpad Enter, F1, F3; a pad's Start, Back and Guide. A pad slot takes a button or a trigger past half.
- A slot listening: Esc or a pad's Start cancels; Delete, Backspace or a pad's Back clears it. A binding another
  action held swaps; Reset resets the scheme shown.
- Bindings are stored in `settings.json` (`controls.bindings`) as tokens, the whole list of an action's kind only
  where it differs from `project.godot` (`key:<physical key name>`, `mouse:1`, `button:2`, `axis:5+`).
- The Controls tab opens on the scheme of the device used last, and has the pads' glyphs (Auto, Xbox, PlayStation,
  Switch) and a move-stick dead zone (10 to 50 %, default 25 %; the aim stick keeps project.godot's 20 %).
- Video: Window (windowed, fullscreen), V-Sync, Frame limit (off, 60, 120, 144, 240), 3D resolution 50 to 100 %,
  Anti-aliasing (off, 2x, 4x), Interface size 80 to 130 %, Show FPS. Audio: Master, Interface, Mute in the
  background. Gameplay: Screen shake 0 to 100 % (the hurt shake scales by it) and Control hints on the HUD. Pause on
  focus loss waits for step 4's pause menu, the player's name for step 3's profile.
- Rows read their control from the property (a ranged number a slider shown in percent; a bool, On or Off, and an
  enum a choice stepped with left and right, a press, or a click on either half); their labels are in the tab scenes.
  Each tab scrolls (a bigger interface size still fits); Q and E, or a pad's shoulders, switch tabs (new actions
  `menu_tab_prev`, `menu_tab_next`).
- The screen stack (`MenuStack`) keeps a covered screen hidden with the focus it had and frees a popped one; each
  screen names its first focus (also the modals' default) and its prompt bar hints.
- A settings file that didn't read is told once, as a dialog on the menu (Game), then forgotten.
- The first player alone plays with every device; a pad's Start joins unless it is the device the first player last
  played with (moved, aimed, attacked or grabbed with; that Start pauses); with a guest in, the first player is fixed
  to that device, and every device again once alone. Milestone 2's "the first input claims a device" is gone.
- The HUD's hints sit on each hero plate (Move, Aim, Attack, Grab) in that player's device's glyphs; the join hint is
  "[Start] Join the game", in the idle pad's own family.
- A prompt glyph sits in a box of its row's height and overflows it, since the prompt fonts' lines are twice a glyph.
- The walk drives several pads with unified's `UnifiedTool.pad_button(button, device)` and `pad_axis` (745e023).

Step 2's review fixes, calls made on the way:

- A pad's join is decided by the Couch in `_input`, before Prompts sees the press; the Couch keeps the device the
  first player last played with from game actions only (its seed is the menus' last device). The join hint speaks to
  the first idle pad, in its family; the Couch says which (`idle_pad_changed`).
- Alone, the mouse aims only while the keyboard and mouse were used last, and the cursor hides while a pad leads.
- Bindings' one rule: no action is left without a binding in a scheme. Clearing the last is refused; binding a key
  that is another action's only one into an empty slot is refused; into a full slot it swaps. A refusal shakes the
  slot and the Controls tab says why. An empty list in the file is no binding; only a scheme absent from the file is
  project.godot's. The file's tokens are held to can_bind. The pad's D-pad is reserved too.
- "Grab" is the player's name for `interact` (the action's id stays, as the sim's Input and the level's props name
  it).
- The glyph maps are baked into GlyphMap resources (`game/ui/prompts/`) by `./uni tool bake_glyphs`; the pack's maps
  stay vendored as their source, and the app checks hold each baked map to its source.
- A key's glyph is its label on the player's layout when that is a Latin letter or digit (AZERTY's Z), else the
  physical key's (a Cyrillic layout shows W, as its keys are printed too: the fonts draw only Latin); bindings stay
  physical keys. Headless runs, which have no layout, show the physical key.
- A binding the fonts lack shows its name in brackets in the text's size and colour, not a blank key cap with its
  name over it (one label can't draw a glyph and text over each other; the name reads as well).
- Numpad digits and + - * / . take the main keys' glyphs; numpad Enter is reserved; the Menu key has no glyph in the
  pack, so it shows its name.
- The settings panel hangs from the view's edges (a margin above, the prompt bar's room below); the tab scrolls in
  what is left, with room inside for the focus frame and a scroll bar's place always kept, so nothing shifts.
- Toggles are On/Off choices, like every other choice; the brown checkboxes are no longer vendored.
- A row lights up while the focus is anywhere in it (`FocusRow`): one sign of the focus for a choice, a slider and a
  binding slot. A slider doesn't take the mouse wheel (the wheel scrolls the tab); Interface size applies when its
  slider is let go.
- A listening slot: the prompt bar shows Cancel and Clear (new actions `bind_cancel`: Esc, Start; `bind_clear`:
  Delete, Backspace, Back); a click outside the slot cancels, and a mouse button binds only when clicked on the slot.
- The pads' glyphs and the dead zone show only under the gamepad scheme.
- A covered screen, or one under a modal, takes no input: a screen acts only while the focus is in it.
- The settings dialog names the folder the bad file is kept in as the player's system names it; `read_problem` holds
  only the parser's words.
- `UnifiedProfile` is an Object, so a joining pad's Profile leaked; the Couch frees it after the join. A
  reference-counted Profile is in plan.md's Needed from unified, for step 3.
- The walk runs 17 s (was 9): the couch's joins wait for each guest to be in the session, and the stuck-key check
  waits for the hero to settle.

