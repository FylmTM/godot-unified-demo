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
- Throw: a press throws at a fixed speed (no charge).
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
- The mouse aims for whoever holds the keyboard, never within 0.5 m of the hero, and not while game input is off, nor
  while the dev UI holds the keyboard (godot.input_blocked, added to unified for it). (How devices are claimed and pads
  join is milestone 3's, below.)
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
- Views: flashes and the grace blink run on the shown game time; a chaser that isn't moving stands. "Skeletons" is the
  prediction (the felled count is milestone 3's, from the State). `View_Hero.carrying` and `View_Prop.held_by` are
  gone.
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
- The replay regression `replays/lan_pair` is a host's recording of a two-player LAN session (what it holds now is
  milestone 3's, below). A session ended by the app quitting keeps its recording since unified f9ccbaa.
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

The look and sound:

- Faces: Kenney Mini Square for everything, Kenney Future for the game's name on the title.
- Pack folders `assets/kenney/ui/`, `fonts/`, `interface_sounds/`; only the Double PNGs of the brown family
  (`button_brown`, `panel_brown_corners_a` the parchment, `panel_brown_dark` for HUD plates and toasts, darkened to 0.6
  and 90 % opaque, `banner_hanging`). The focus is a gold StyleBoxFlat frame that pulses (Game), not a pack piece. The
  theme was made once by a throwaway script and is edited as text since.
- Sounds: `select_002` (the focus moves), `click_002` (a press), `confirmation_002` (New game), `error_004` (a dialog),
  `maximize_003` and `minimize_003` (a join, a leave). Picked by name, not by ear: worth a listen.
- The title's Quit is a plain button: the red one is for confirmations (`button_red` is not vendored); toggles are
  On/Off choices (the brown checkboxes are not vendored either). Dim captions are 26 px at 75 %.
- The tagline "Down into the crypt, one to four heroes." is placeholder copy.
- A big interface size never runs anything off the view: every centred panel (the pause menu, Play together, the
  dialogs), the title's column and the HUD's hero plates shrink to fit (`FitToView`, about their middle, left middle
  and top left). The toasts, the co-op pause's banner and the link plate keep to the lane between the HUD's plates
  and the counts (`Lane`), the toasts at most two there while it is narrow, never reaching the banner, the banner's
  text a size smaller there ("Paused by" on its own line when the name won't fit beside it); the join cards
  hang below the counts and the session panel. A long name is cut before its "+1" (`NameLabel`: the HUD plates, the
  Players rows, "Paused by", the toasts), so guests stay told apart.
- The interface is never drawn below 60 % of its canvas (`Settings.UI_SCALE_FLOOR`): a 720p window at 80 % draws it as
  90 %, so the HUD's smallest text stays readable (the floor, rather than bigger HUD text everywhere).
- A greyed Start on hero select keeps the screen's focus without wearing the focus frame. A prompt's glyphs sit with
  their ink's middle on the row's (a pad's shoulder caps sat low). A library detail's path wraps after a separator
  (a zero-width space after each slash), not mid-name.
- Portraits are rendered by `./uni tool render_portraits --window` (256 px, square, head and shoulders, idling,
  mipmapped) and committed; the app checks hold each class to a square one. The suite doesn't re-render (it needs a
  renderer).

The app's frame:

- The user data folder is `crypt_crew` (`config/use_custom_user_dir`): on Windows `%APPDATA%/crypt_crew`.
- An export opens borderless fullscreen (`display/window/size/mode.template=3`), the default the Video setting
  matches, so there is no windowed first frame.
- The play scene loads on a worker thread while the title is up (Game), collected at the switch and at a quit.
- A run whose session quits the app at its end (`--quit-at-end`) skips the menu, so no sound outlives the quit.
- `LibraryCheck` is kept from the Fable design (the Opus one left it to milestone 10).
- Every button's sound and hover-takes-focus live in Game, hooked from `_enter_tree`; a button is the game's when its
  scene is under `res://game/` (the library's dev UI has neither). Hovering gives the focus, so the mouse and a pad
  never show two highlights. Sfx only plays.
- Pads press and back out: `ui_accept` and `ui_cancel` carry the pad's A and B in `project.godot`.
- Modals (Dialog, Connecting) share a `Modal` base that takes back a wandering focus and returns it where it was; with
  none left, the screen's default (the `default_focus` group). The title takes the focus only when nothing has it.
- The screen stack (`MenuStack`) keeps a covered screen hidden with its focus and frees a popped one; each screen names
  its first focus and its prompt bar's hints. A covered screen, or one under a modal, takes no input.
- The Dialog asks questions too (`Game.ask`, which takes the answer's callable; anything shown over an open question
  answers it no first). Questions that affect others ("End the game for everyone?", "Quit to desktop?") open on Stay;
  the dialog shows its own prompt bar while the menus' hide.
- A dialog that explains says it in the app's sentence, the library's words small under it; a game that ends with a
  DISCONNECTED detail uses that detail as the reason, unless it is the plain "session ended".
- A link in trouble in play is `LinkStatus`, a plate: catching up shows after 0.5 s; reconnecting at once with "Leave
  game", which takes the focus only on an up or down press while nothing has it. The game's input stays on.
- Connecting is only for starts: it shows after 0.3 s (a quick start or failure never flashes it), and Esc or Cancel
  leaves at once: the flow is on the menu, that start's goodbye is dropped, and a start queued over it goes on.
- Toasts sit at the top, in the lane, three at most ("Sexton +1 joined (Mage)", "is back", "left"), on their own
  layer (Game's Notices, 5) under the play scene's menus (10) and the app's overlays (50). The party's own seats
  arriving at the start are no news; the class is the HUD data's, remembered so a leaver's is still known.
- Settings are JSON (`user://settings.json`), not a ConfigFile (a damaged ConfigFile is an engine error no check
  could exercise). A file that doesn't parse is kept as `.bad`, told once in a dialog naming the folder as the
  player's system names it; `read_problem` holds the parser's words. `--settings-path=` names another file.
- Settings and the save write through one helper (UserFile): beside the file, checked, then moved over it; a failed
  write is printed and the session keeps its copy; a missing file is read from its `.tmp`. Two read problems at boot
  are told one after the other.
- Pause and the couch's join ignore their keys while the game's input is off.
- The party's guests are seated again each frame (up to 60) while add_local_player says -1: since unified 830b012 it
  does while a start waits for the last session's goodbye. A pad's mid-game join can't meet that (the play scene
  exists only while a session runs).
- A hold's joint is live whenever a hero's `held` is set (every way a prop or a body goes lets go first), so
  update_holds needs no guard under unified 830b012's live-ref asserts; hands.odin says so.
- A node that listens to the session's or Game's signals does it through `Game.listen`, which drops the connection as
  the node leaves the tree: a menu closing or the app quitting never hears a signal it can't answer (online_check
  over EOS caught Invite friends hearing join_code_changed at quit).
- Real boot (the main scene loaded by the engine) was checked by hand under `uni drive`; no suite step can (the walk
  is a `-s` script, the drive step starts with `--autostart`): plan.md, Needed from unified.

Settings, bindings and prompts:

- Video: Window, V-Sync, Frame limit (off, 60, 120, 144, 240), 3D resolution 50 to 100 %, Anti-aliasing (off, 2x,
  4x), Interface size 80 to 130 % (applied when its slider is let go), Show FPS. Audio: Master, Interface, Mute in the
  background. Gameplay: Screen shake 0 to 100 %, Control hints (Briefly, Always, Off), Pause when the window is in the
  background, the player's name. Controls: the bindings, the pads' glyphs (Auto, Xbox, PlayStation, Switch) and a
  move-stick dead zone (10 to 50 %, default 25 %; the aim stick keeps 20 %), those two under the gamepad scheme only.
- Rows read their control from the property (a ranged number a slider in percent, a bool or an enum a choice stepped
  with left and right, a press or a click on either half); a row lights up while the focus is anywhere in it
  (`FocusRow`). A slider doesn't take the wheel (the wheel scrolls the tab).
- The settings panel hangs from the view's edges and each tab scrolls in what is left, with room for the focus frame
  and a scroll bar's place always kept. Q and E, or a pad's shoulders, switch tabs (`menu_tab_prev`, `menu_tab_next`).
- Prompt glyphs are Kenney Input Prompts' fonts (the Opus design), not its PNGs: crisp at any size, in a label's
  colour. Four families (keyboard and mouse, Xbox, PlayStation, Switch; an unknown pad is Xbox). The glyph maps are
  baked into GlyphMap resources by `./uni tool bake_glyphs` (the pack's maps stay vendored as their source, and the
  app checks hold each baked map to it). `Prompts` is an autoload between Sfx and Game.
- A key's glyph is its label on the player's layout when that is a Latin letter or digit (AZERTY's Z), else the
  physical key's; bindings stay physical keys. Numpad digits and operators take the main keys' glyphs; the Menu key
  shows its name, as any binding the fonts lack does, in brackets.
- A prompt glyph sits in a box of its row's height and overflows it (the prompt fonts' lines are twice a glyph).
- Rebindable: on the keyboard the four moves, attack and grab; on a pad attack and grab (the stick and D-pad move,
  fixed; no "Swap sticks"). Two slots per action per scheme, one scheme per machine. Reserved: Esc, Enter, numpad
  Enter, F1, F3; a pad's Start, Back, Guide and D-pad. A pad slot takes a button or a trigger past half.
- Bindings' one rule: no action is left without a binding in a scheme. Clearing the last is refused; binding another
  action's only key into an empty slot is refused; into a full slot it swaps. A refusal shakes the slot and the tab
  says why. Reset resets the scheme shown. The Controls tab opens on the scheme of the device used last.
- A listening slot: the prompt bar shows Cancel and Clear (`bind_cancel`: Esc, Start; `bind_clear`: Delete,
  Backspace, Back); a click outside cancels, and a mouse button binds only when clicked on the slot.
- Bindings are stored in `settings.json` (`controls.bindings`) as tokens, an action's kind only where it differs from
  `project.godot`; an empty list is no binding, only a scheme absent from the file is the project's; the file's tokens
  are held to `can_bind`.
- "Grab" is the player's name for `interact` (the sim's Input and the level's props keep the id).

Hero select and the couch:

- Hero select's first seat is the device that opened it; a pad takes the next free seat with its Start or A. Back from
  ready takes the ready back, back again gives the seat up (the first seat's goes back). Once every taken seat is
  ready, the first seat's accept starts (or Start clicked).
- The keyboard and mouse sit only in the first seat: they are the first player's. The mouse works that seat through
  its card's arrows and action line, which never take the focus (`mouse_only`, exempt from the app checks' focus rule).
  A free seat invites a connected pad ("[Start] Join" in its glyphs), or asks for one.
- A seat card is one size whatever it shows (two lines for a long name, "Ready!" over the portrait); the seats scale
  down together at 130 %, as the join and drop cards do; hero select's buttons sit bottom left. The seat card and the
  join and drop cards are one widget (`SeatCard`).
- On hero select the backdrop's camera comes round to the crew; each seated pick steps forward and strikes its stance.
  Its sounds: a step, a ready or its taking back, a seat taken or given up; Start confirms.
- Sticks step once per push, each pad's own (`StickSteps`). A pad that disconnects on hero select gives its seat up
  (the first seat passes to the next, keeping its pick and ready); in play its card closes.
- Any is resolved locally only for a single-player game or a host (each Any becomes the first class no seat picked); a
  join passes Any through for the host's sim to resolve, a joiner's couch guests too, and a mid-game pad's join stays
  Any. The remembered pick stays Any.
- Each taken seat is a place in the party, its local index: the remembered picks (`hero_picks`, four) go by it, and a
  pad joining mid-game takes the lowest free index with that place's pick preselected. A guest is named after the
  first player, "<name> +1", "+2", cut to the name limit, so two machines' guests never share a name.
- The player's name is never read from the system: a first run picks one of the game's own (Sexton, Lantern, ...) and
  saves it; a tool run's is "Adventurer". It is stripped and cut to `UnifiedSession.NAME_MAX` bytes on a character's
  boundary. The name field starts editing only when asked (a click, or accept); Enter applies, Esc puts it back.
- The first player alone plays with every device; a pad's Start joins unless it is the device the first player last
  played with (that Start pauses). The Couch decides in `_input`, before Prompts, from game actions only. With a guest
  in, the first player is fixed to that device. Alone, the mouse aims only while the keyboard and mouse were used
  last, and the cursor hides while a pad leads.
- Only a pad joins mid-game: its Start opens its card on the HUD (A joins, B backs out); at four the couch is full (no
  hint, a toast). Drop out is the pad's Back (`drop_out`): a card asks, A drops out, B stays, a Start never confirms.
- The HUD's plate: portrait, name and class above the HP bar (Kenney's small red bar, every bar one length, the number
  on it), the hints below for a few seconds after a join or a change of device (Control hints). The full HP comes from
  the extension (`Hud_Hero.hp_max`). The join hint speaks to the first idle pad, in its family.
- `UnifiedProfile` became reference-counted in unified (f2c01c7): a joining pad's Profile leaked.

Saves and pauses:

- The save is Fable's: the Setup is a new game or a save (version, floor, surges, kills; SAVE_VERSION 1). `Game.save`
  gives one only once a surge has risen this session, holding the floor the party was on (`saved_floor`) and the kills
  at the rise (`saved_kills`). A Setup of another version starts a new game; no arrival reads the Setup (the party by
  slot is milestone 7's run). VERSION "4", the reference run re-pinned, `uni bench` unchanged.
- `kills` counts every skeleton felled, a dev kill included. `paused_by` is set by the pause and cleared by the resume,
  whoever sends it; a pauser who leaves stays named until someone resumes.
- The HUD shows the surge, the skeletons up and the felled from the State (`Data_Hud`: `surges`, `kills`,
  `paused_by`), so a late joiner and a continue start from the right counts.
- One slot, `user://save.json`; one that doesn't read, or of another version, is moved to `save.bad.json` and the
  title says so once. Under `--no-settings` the slot lives in memory.
- Continue (the title's first focus, with the save's line) goes through hero select, as every start does. New game
  over a save asks first; so does hosting a new crypt over one.
- A joiner keeps the host's newest save in memory (its starting Setup too, when the host continued); when the game
  ends without it leaving, "Continue on your own" takes that save into its slot (asking when that holds its own) and
  continues it through hero select.
- The pause menu is made when it opens, with its own stack and prompt bar. It is alone or online by whether the
  single-player pause took (asked on open), not by the mode: a LAN host with nobody joined yet is online (no
  single-player pause; Pause for everyone shown). Online and running, its first button reads "Back to the
  game"; Pause for everyone is its own button, reading Resume for everyone (focused) while anyone has paused. Its back
  and pause presses resume only from the keyboard or a pad that plays.
- Opening the game to friends while paused alone sends the co-op pause at once; when the game is single again while
  paused, the resume is sent; alone, the status reads "Resume when you're ready."
- The co-op pause's banner hides under the pause menu, cuts a long name, and shows "[Esc] Menu" in the first player's
  glyphs. Over a replay the menu says "Replay paused" and offers Resume and Leave only.
- Leaving asks first alone or hosting (what is saved); a host with others ends it for everyone; a joiner leaves at
  once. Quit asks the same.
- The focus-loss pause (on by default) opens the pause menu, single player only, once the window has had the focus (a
  tool run's never has).
- The Players list: this couch's players by local index first, then the others ("online"); each guest here with Drop
  out, a row without one keeping its room.
- Moves held under the pause menu reach nobody; when it closes, a held button waits for its release and a held
  direction reads at once (unified's `game_input`, 7d982a9).

Playing together:

- EOS lobbies are wired as unified's examples do (`eos.lobby({})`) in the extension and the headless binary. No SDK in
  the repo; the build copies it when `.env` points at it.
- Play together is one screen: Host online, Host on this network, Join with a code, Join an address, Rejoin last game.
  Rows that can't be used are greyed, take no focus, and `online_problem`'s sentence says why; the first enabled row
  has the focus. Rejoin offers the last code or address joined (`Settings.last_join`, saved once in).
- Hosting with a crypt saved asks which (Continue your crypt, or A new crypt, which asks first). Every host and join
  goes through hero select ("Host a crypt", "Join <code>").
- Hosting online is start_single, then open_online once the crypt is up: the same path as Invite friends. The crypt
  plays at once; "Getting a code..." until the code comes; a lobby that fails leaves the game alone with a toast. A LAN
  host is host_direct on `Game.lan_port` (7777; checks set their own).
- A start that fails comes back to the screen it was asked from (what was typed kept), the dialog over it; start_failed
  comes before the dialog. The end-reason enum is later (plan.md).
- The code field: a framed cell per `join_code_length`, letters of `join_code_alphabet`; typing (lower case taken as
  upper), Backspace (back first on an empty cell), a paste (Ctrl+V or Paste, trimmed, through `clean_join_code`); on a
  pad left/right move the cursor (past either end the focus moves on) and up/down step a cell, repeating while held
  (0.4 s, then 0.09 s). The cursor's cell wears the pulsing focus frame; the prompt bar follows the focused control.
- Join with a code opens empty; Join an address opens with the last address selected, and its first Esc goes back. An
  address joins on LAN_PORT when it names no port and is always handed on as `host:port` (unified resolves names); one
  the network can't find says "Couldn't find <host> on the network.", the library's words under it.
- One clipboard seam on Game: a `--no-settings` run (tool, drive, coop) keeps its own in memory, so no run touches the
  player's. Copy says "Copied" on its button; the code of an online host or invite the player started is copied once,
  as it comes, without a word (never for a session a flag started).
- The session panel (under the crypt's counts, growing with its text): the code or address ("Getting a code...",
  "Closed" after Stop inviting; a joiner, `Game.join_target`, or "A friend's game" for an adopted session), how many
  play (roster_changed; unified tracks the roster per session since 947b982), a slow link's round trip. No clicks.
- Invite friends (the pause menu, alone or hosting): Invite online / on this network, the code large, Copy, Stop
  inviting; inviting again opens it the way it was hosted. Game keeps `inviting`, so "Closed" shows only after Stop
  inviting. A failed opening says why on the screen, once (a toast only while the game takes input).
- Stop inviting then Invite online shows the same code: unified's close_online keeps the lobby (a player who drops
  may come back) and only hides the code, so reopening reposts it (online_check: one lobby made, left once at quit).
- EOS verified on the developer's machine (the demo's own product, `.env` in place): `uni coop`, `--menus`,
  `--rejoin` and `--crash` over EOS (Direct P2P, no desync; the joiner's Any became a Barbarian, its couch guest
  "Friend +1", the co-op pause both ways, Continue on your own), `UNIFIED_EOS_RELAYS=force uni coop` relayed (54 ms
  round trip, no desync), and `uni tool online_check` (the pending code, the copy, Stop inviting, inviting again).
  There, the walk's code join that fails waits about 20 s for EOS to find no lobby.
- A host whose start fails can't be forced in a check (Odin's UDP bind reuses a taken port on Windows): the
  failed-start path is checked through joins and a failed open. The pending code is checked only by online_check.

Checks:

- The walk is the look pass too: `uni tool --window --shots --offline --size WxH ui_walk -- --ui-scale=X` (unified
  sizes and places the window; the walk sets the interface size, which its 130 % parts go back to). Its clicks scroll
  a row into view first. It checks, at 130 %: the pause menu inside the view, the title's column refitting, four
  plates inside the view with each guest's "+1", no toast over a plate, the counts, the panel or the banner, and a
  host's join card clear of the counts and the panel at a scale of at least 0.8. In a window a click parks the cursor
  outside it after: left where the click was, it hovered the next screen's button into the focus (a flake at 720p,
  80 %).
- The walk's failed code join waits 3 s where online play can't start and 30 s where it can (the lobby service looks
  first); its failing join by address has one shot, 25_join_failed (the walk's last part had one just like it).
- `uni drive pad` and `uni drive type` with a device moved from milestone 3 to later (plan.md): the walk drives
  several pads itself (`UnifiedTool.pad_button`), and no play-check of this milestone needed a second pad's events
  from outside.

- `ArtChecks` takes TTF and Ogg files and counts what the theme uses; `AppChecks` holds the autoload order, the
  theme's variations, a HUD that takes no click or focus, menu buttons that take the focus, every button's sound.
- The walk drives pads with unified's `UnifiedTool.pad_button(button, device)` and `pad_axis` (745e023).
- The short scenarios' run crosses a surge (`the_suite_runs_cross_a_save`), so unified's save checks cover Game.save
  under rollback, churn and a late join.
- `replays/lan_pair` (the host's recording, ticks 2 to 2858, about 45 s; recorded again for milestone 4's State layout
  and levels): a Knight host and a Barbarian joiner (both asked for Any), each grabbing, carrying and throwing a prop
  twice; eight skeletons raised (dev) and attacked by both; the joiner's co-op pause and the host's resume; the host a
  Mage and the joiner a Rogue (dev), both attacking; every skeleton killed (dev); the host downed (dev); three surges.
- `uni coop --host-profile/--join-profile` (unified b06ba4f) gives each side its Profile; coop.gd checks each class
  against its flag (a joiner asking Any plays a class the host doesn't), names its joiner "Friend", works both pause
  menus, and the joiner continues on its own after the host leaves. With `--menus` each side goes through the menus
  (`_start_host`, `_start_join`), `--rejoin` through the title's Rejoin; the joiner's panel and a couch guest on its pad
  1 ("Friend +1") are checked across the two processes.
- `online_check` hosts online from the menus where online play can start (the pending code, the copy, Stop inviting,
  inviting again); elsewhere it says why and passes.

## Milestone 4: the crowd at scale

Decided with the developer (docs/plan.md, Milestone 4), one line each:

- The crowd's bake is bone matrices in a texture, skinned in the shader, not per-vertex positions.
- 500 skeletons live on the arena, reached by the Setup now; a floor's cap comes from its walkable area: MAX_MINIONS
  640, the cap per floor (Floor 1 111, the arena 500).
- Sim speed: one 1 m grid with `sim.grid_box` for wider queries, far minions' steering every 4 ticks, the director
  counting free rows, surges a quota raised a few a tick, one clamped radial knock for blasts and charges.
- Crowd rules: queueing and a stagger while knocked (step 3).
- Bench rows: Floor 1's kept; crowd_idle, crowd_chase, crowd_fight on the arena through the Setup; target frame p99
  at most 3 ms; CI publishes them in its existing bench step.
- The bake tool starts in the demo and moves into unified's tools_godot by the milestone's end; shadows decided from
  shots and frame times.
- From unified: `View_Policy.ages` (step 5) and scenarios on a Setup (the crowd's scale tests).

Calls made in step 1:

- A held crowd is a Setup field, `crowd` (None, Idle, Chase, Fight; `--setup floor=arena,crowd=fight`), which the
  rules and the scripted player read (since unified f438281 the script gets the Setup; State.crowd is gone): idle heroes stand still, chasing ones walk, fighting ones walk holding
  Attack (let go a tick each half second, so a throw's press lands) and press Interact in play's bursts (grabs,
  throws and prop hits at 500); under any crowd the script sends no dev command and no pause, heroes take no damage (a
  wipe would empty the floor), and the floor's packs aren't placed. A save never holds one. bench_prepare re-places
  the crowd at the row's count; init places it at the floor's cap, so the scenarios play it without a bench.
- A held crowd is allowed in any build, a public one too: a sandbox (invulnerable heroes in a crowd Setup are harmless
  in co-op); milestone 7's endless mode brings the arena's real rules.
- While a population is held, dev_spawn_minions spawns nothing (so Floor 1's row holds exactly its 40, as before the
  per-floor cap let the script's spawns add to it), and an idle crowd's felled come back asleep, at the graves out of
  the spawns' sight (CROWD_IDLE_CLEAR), never as chasers.
- crowd_idle's heroes stand still instead of walking out of sight: no place in the arena keeps 500 sleepers out of
  sight of heroes walking for ten seconds. Its sleepers start CROWD_IDLE_CLEAR (12 m) from every spawn.
- A new game starts on `Setup.floor` (Floor 1 unless set), which a save already named; the World builds every level's
  floor up front (`Floor`, indexed by Level_Id), so a level change builds nothing.
- CROWD_DENSITY is 0.4 per walkable square metre: Floor 1's walkable floor holds 111 (was 40), the arena's 1,526 m² the
  MINION_CAP of 500. Floor 1's benchmark row keeps 40 (BENCH_FLOOR_MINIONS) so it compares across milestones.
- The walkable area is summed in the demo from `nav.Mesh`'s public fields (`island_area` in world.odin) instead of
  asking unified for `nav.island_area`: a dozen lines on data the mesh already exposes. Ask for it if a second game
  needs it.
- The arena (`game/levels/arena.tscn`): a 48 m by 40 m hall, walls north, west and east, low cover south (the camera's
  side), a colonnade of eight decorated pillars around an open floor, four shadowed braziers (Floor 1 has two), three
  unshadowed lanterns on the south barrier's columns, twelve graves along the rim and three inside the colonnade (west,
  east, south of the middle) with KayKit grave markers behind them, ten props, no packs (its skeletons all rise).
- The arena's inner graves: from the middle every rim grave is 31 to 43 m of field cost away (the field's path over
  the mesh's triangles runs longer than the straight 18 to 22 m), past SURGE_FAR's 30, so a party in the middle saw no
  surge; the three inner ones are 10 to 17 m. The level gained graves; SURGE_FAR stays.
- A brazier's bowl casts no shadow (the part, so Floor 1 too): its own fire just above it threw a cross across the
  floor. The four shadowed brazier fires stay until step 4 measures the arena's shadows (the reviewers found the cube
  maps about 80 % of its draw calls).
- A held crowd's places are drawn uniformly over the walkable floor's area (`floor_point`: a polygon by its share of
  the area, then a point in it) from a stream keyed by the seed, SEPARATION apart and clear of the props (a minion
  placed inside a prop's footprint is pushed out onto its neighbour on the first tick). Drawing over the grid's
  rectangle placed only 72 to 79 of Floor 1's 111.
- `uni bake --nav` failed on an error line: `Game` preloads the play scene on a worker thread at boot, and the bake's
  tool script quit mid-parse. `Game` now preloads only while the menu is the current scene (a `-s` tool run has none).
- Bench, the developer's machine, quiet: crowd_fight is at the 3 ms line (3.17 ms p99 here, 3.37 to 3.51 in the
  reviewers' reruns), crowd_chase over it (4.88 ms here, 5.5 to 5.9 in theirs: the crowd packing around the heroes);
  step 2's speed work and step 3's queueing are for both.

Calls made in step 2 (the sim at 500):

- The minion grid's cells are 1 m (`#assert(MINION_GRID_CELL >= SEPARATION)`), up to 16,384 of them (a 125 m floor);
  blows, bursts, bolts and thrown props walk a box of cells over their reach (`minions_near`, a bolt's over its
  tick's segment), so they find exactly what a walk of the table finds (a test compares the two at every reach the
  rules ask). `minion_near` (an arrival's clearance) stays a walk of the table: it runs first in the tick, before any
  pass has rebuilt the grid for this tick (the grid is scratch: after a rollback it holds another timeline), and an
  arrival is rare.
- Separation's test is a crush on open floor (sixty sleepers within 2 m pushed apart past SEPARATION less 0.1 m in
  10 s, no hero to wake them): a crowd chasing heroes who stand still still packs onto them (closest pairs about
  1 cm apart, step 3's queueing), so no test can hold that crowd apart yet.
- A far chaser's steering is sliced: beyond STEER_NEAR (3 m, straight line) of its target it steers every
  STEER_TICKS (4) by its index and walks its facing (state) between; within 3 m every tick. It pays about 6 % of the
  crowd rows' re-sim means; a test walks Floor 1's cap round its corners and finds no step off the floor or through a
  wall or low cover.
- Separation reads its neighbours where the moves began (World.starts, scratch copied before the pass), not
  half-moved (earlier rows had already moved): no minion's push depends on the table's order, and it measured about
  4 % cheaper on the crowd rows' re-sim means (a compact array instead of 60-byte rows).
- The obstacle push is culled, not flipped: each tick marks the grid cells an obstacle's reach touches (World.in_way,
  scratch) and a minion in an unmarked cell skips the loop. It computes exactly what it did (the pins didn't move); a
  flip (each obstacle walking its nearby minions after the moves) would push in another order and need the grid
  rebuilt after the moves.
- Floor 1's row after step 2, A/B against step 1's build on a quiet machine (3 runs each, alternating, 3000 ticks):
  step means equal (19.6 to 19.9 us), re-sim means 315 against 310 us (+1.6 %), p99s within each other's spread.
  The few microseconds are the 1 m grid's cells: Floor 1's grid has about 1,300 to clear and file twice a tick, where
  the 3 m grid had about 150; left as it is.
