# The plan

What is decided about Crypt Crew and not built yet. As each part lands, its facts move into the code, the README and
the doc comments, and leave this file; when the game is done, this file is gone.

## The game

A top-down co-op dungeon crawler for 1–4 players: adventurers go down a crypt full of skeletons, relight its
braziers, and haul its treasure up to the lift.

- **Camera and controls.** A fixed 3/4 angle that zooms to frame every local hero; twin-stick (move, and aim with the
  mouse or the right stick). One shared camera, so couch co-op needs no split screen.
- **A floor.** Light the braziers while skeleton surges come for you; the lit braziers open the vault. Then carry the
  hoard back to the lift: it has two handles, so two heroes carry it at walking speed and one alone drags it, while
  the crypt wakes behind them. The lift is the save point; each hero picks a boon and the party descends.
- **A run.** A hub between runs (the lobby), three floors, and a boss vault: 20–30 minutes. A run saves at every lift
  and continues from the menu. A player can join or rejoin at any time; where a newcomer's hero appears mid-floor is
  decided with milestone 2's design.
- **Failure.** A downed hero ragdolls and can be revived by holding interact beside them. When the whole party is
  down, the floor restarts from the last save.
- **Heroes.** Four classes (the Profile): Knight (sword arc, shield charge, block), Barbarian (cleave; grabs and
  throws props, elites and allies), Mage (bolt, fireball with a physics blast), Rogue (crossbow that lands where the
  shooter saw the target, dodge roll). Heroes shove and throw each other; they never damage each other.
- **Enemies.** Skeleton minions as the crowd (about 500 alive), Skeleton Warriors (shielded), Skeleton Rogues
  (flankers), Skeleton Mages (ranged, summoners), and a boss. Blasts and charges knock minions back too, through their
  own velocity (a minion has no physics body).
- **Depth.** Difficulty levels (the Setup); an endless arena mode (also the stress and benchmark scene); progress
  across runs (unlocks, best floors, gold hauled) that each player brings into a session through their Profile; each
  floor in 2–3 authored layouts, the run's seed picking the layout and placing spawns, props, traps and loot.
- **Couch co-op** from the first playable: a pad presses Start to join; local and online players mix.

## The look and sound

The look is decided and lives in `docs/ART.md`. Still to come: a cutaway of walls between the camera and the heroes
(milestone 8). Sound: Kenney's (CC0) effects; music: CC0 tracks, picked by the developer from candidates.

## What it shows of unified

Every capability a game uses, each where it belongs in the game: rollback and prediction; late join and rejoin;
EOS lobbies and LAN; opening a single-player game to friends; couch co-op; Box3D characters, bodies, joints,
sensors, kinematic paths and ragdolls under rollback; shots resolved where the shooter saw the target; levels baked
from Godot scenes with a navmesh; level changes; events played when predicted and rewards shown when confirmed;
scene views, pooled views and MultiMesh crowds; the co-op and the single-player pause; Setup, Profile, save and
continue; dev commands, debug draws, the dev UI, recording and replay with seek, F3 notes; and every way of testing
(below). Each feature gets a line in the README pointing at the file that does it.

## How it's built

- **Sim:** one package, a file per system, the tick body as the table of contents. Minions are plain rows walking
  the navmesh (no body each); elites, props and heroes are Box3D. Rule numbers in `tuning.odin`, with presets per
  difficulty and a quick preset for tests.
- **Animation from state:** a hero's view carries its action and the tick it started; Godot blends locomotion from
  speed and seeks one-shots to the action's age, so rollback corrections and replay seeks land on the right frame.
- **The crowd:** pooled animated scenes first, then one MultiMesh animated from a texture the minion clips are baked
  into.
- **The crowd's mesh:** a KayKit minion is 9 meshes and about 5,000 triangles; the crowd draws a merged, lighter one.
- **Ragdolls** drawn on the KayKit skeleton from the bones' rotations.
- **App layer:** the game's own, written fresh (menus as scenes, one Theme from Kenney's UI pack, input prompts that
  follow the device, rebinding, settings, saves, hero select).
- **Online:** the demo's own EOS product (the developer creates it; `.env` per `unified/docs/EOS.md`).

## How it's tested

`docs/testing.md` (milestone 9) maps each layer to its command and files: rule tests on headless runs; unified's
standard scenarios (rollback every tick, players coming and going, bad networks, a late joiner); a pinned reference
run checked on every CI platform; replay regressions recorded from real play, including each fixed F3 note; a
scripted bot playthrough; the Godot suite (its steps: `./uni test -h`); `uni coop` with rejoin and crash; and the
F3 → `uni feedback` → regression loop as a walk-through.

## Milestone 2: the design

The first playable, as decided (two designers merged; the calls are in `docs/review.md`). Built in steps, each green
on `./uni verify`; this section goes once the code and README say it.

**Shape.** 64 Hz (`TICK_HZ`); every time constant is seconds that are whole ticks (`X_TICKS :: u32(X_S * TICK_HZ)`).
`Game :: sim.Game(State, Input, World, Event, Command, sim.No_Setup, Profile, PLAYERS)`; one level, Floor 1
(`game/levels/floor_1.tscn`, built: markers `hero_spawn` (slot), `grave`, `pack` (count), `prop` (kind)). The sim
package is one system per file: game (descriptor, `Zone`, `tick` as the table of contents), tuning (every rule number,
`@(rodata)` tables `CLASS_SPECS`, `MINION_SPEC`, `PROP_SPECS`), input, state, events, world (categories, `World`,
places from markers, `world_create`/`destroy`, `extra`, `init`, `enter_level`, `restart_floor`), presence, heroes,
health, attacks (shared machinery) plus a file per class (knight, barbarian, mage, rogue), bolts, hands, props,
minions, director, pause, dev, script.

**Input** (held state only): `move_x, move_z: i8` (world XZ: the camera never turns), `buttons: bit_set[Button; u8]`
(`Attack`, `Interact`; milestone 5 appends), `seen: sim.Seen` (the crossbow's rewind), `aim: dmath.Dir2` (none: keep
facing; an idle pad stick faces its move). Attack is read held (repeats on the class cooldown); Interact by its press
edge. Commands: `Command_Set_Paused`, `Command_Dev_Spawn_Minions`, `Command_Dev_Set_Class`, `Command_Dev_Hurt`.
`Profile {class: Class}`, `Class :: enum u8 {Any, Knight, Barbarian, Mage, Rogue}`: `Any` (the zero) resolves on
arrival to the first class no present hero plays; a returning hero keeps its class; `--profile class=mage` picks one.

**Heroes** are `physics.Character`s (limp for down, rides the lift later, presses plates, carries with joints): radius
0.45, a 2.2 m capsule, class `max_speed`, no jump; `speed_scale` drops while attacking or carrying; position and
velocity read back into the block after the step. Facing is the aim, else the move. Categories: the kit's floor 1,
wall 2, low 4; hero 8, prop 16; 32 kept for elites. Shots hit `WALL | PROP` and fly over low cover.

**Minions** are rows with no body (`MAX_MINIONS` 128, `MINION_CAP` 40 alive now; milestone 4 raises both): position,
velocity, knock, nav polygon, target, a phase (`Rise`, `Idle`, `Chase`, `Attack`, `Dying`) and when it began. They
walk Floor 1's navmesh (`nav.Fields` per hero polygon, `nav.steer`, `nav.move`, never off the mesh), keep apart over a
`sim.Grid` (ties by index), are pushed out of heroes and resting props (one-way), and get knocked back through a
decaying velocity of their own. Retargeting is sliced (`sim.due`). In reach they wind up (telegraphed), then strike if
the hero is still in reach and in front. Dying is a phase in the row (milestone 4's MultiMesh can't linger a view);
the row is freed after `DEATH_S`. Packs sleep until a hero comes in sight; surges rise at graves between near and far
of the party, picked by keyed rolls (the clock decides, no command); a cap; `bench_prepare` holds a population.

**Props** are dynamic Box3D bodies made from `prop` markers in marker order (`barrel`, `crate`, `heavy_crate`; specs
measured from the models). Every hero carries (friendslop's `hands.odin`, cut down): Interact grabs the nearest prop in
a cone (one pure proc that `fill_frame` also calls for the highlight), a motor joint holds it in front at chest height
(the doorway's lintel is 2.75 m), Attack while holding throws it at a fixed speed along facing (a velocity, so every
mass flies alike), ignoring its thrower until clear. A fast thrown prop damages and knocks back each minion it meets
once. Props never hurt heroes.

**Attacks** start at once (the clip) and land a windup later (the effect), from the class spec: Knight's sword arc
(narrow, quick), Barbarian's cleave (wide, slow, big knock), Mage's bolt (a `Bolt` row swept per tick against minions
and `physics.world_cast_ray_closest` against walls and props), Rogue's crossbow (hitscan where the shooter saw it:
`sim.seen_rewind` capped by `MAX_REWIND_S`, the shooter's eye moved back by its velocity, minions tested at
`pos - vel * rewind`, bodies by `physics.world_cast_ray_closest_rewound`; a view-only tracer). Strikes resolve after
`physics.step`. Damage is integer; `damage_minion` and `damage_hero` are the only writers of their transitions.

**A hero at 0 HP** goes down: limp, its carry dropped, minions stop targeting it, for `RESPAWN_S`; then it rises beside
the party with `SPAWN_GRACE_S` of grace. All present heroes down: `restart_floor` (every body destroyed in a fixed
order, the level rebuilt from markers, heroes at their spawns). Milestone 5 swaps the timer for revive.

**Joining.** A joiner, a rejoiner and a respawn all arrive beside the party (`arrival_spot`): the lowest-slot hero
up anchors a ring of eight spots, the first on the mesh, connected, in clear sight and clear of minions wins; else the
anchor's own spot; with nobody up, the slot's `hero_spawn`. Couch: a pad pressing Start joins as another local player
(drift's pattern).

**Tick order.** presence, pause (return), dev commands, respawn, facing, hands, start attacks, holds, move heroes,
director, target, move minions, `physics.step`, read back, resolve strikes, bolts, thrown props, age throws, age
minions, wipe check. Each group in a `sim.zone`.

**Views.** `View_Hero {class, action, action_started, velocity (local), down, carrying, hp}` posed by
`CharacterRig.pose` from `UnifiedSession.shown_time`: a one-shot at its age, else locomotion picked from velocity in
the facing's frame (idle, walk, run, backwards, strafes), one clip at a time (a layered upper body is polish). The
local hero's yaw comes from its newest input (`Frame.local_inputs`). `View_Minion {phase, since}` pooled,
`Appear.Verified` (a mispredicted riser must not flash). `View_Prop {kind, held_by, aimed}` pooled. Bolts a MultiMesh
kind. Effects on EMITTED (hits, tracer, bursts, spawns), counts on CONFIRMED. The play scene (`game/play/play.tscn`)
holds the session, `Level` (level_root), `Views` (view_root), the camera rig (fixed 3/4 angle framing the local heroes,
zoom by spread), the crypt environment, effects and the HUD. Mouse aim: the cursor's ray on the y = 1.2 plane minus the
local hero's shown position, through input values.

**Tests.** A rule test file per system on `headless.Run` (each ends synced); the standard scenarios; a stateless script
that exercises everything (moves, aims, attacks in bursts, grabs and throws, slot 0's pause; `scripted_profile` gives
slot k class k + 1); a bot (`tests/bot.odin`) that fights and throws; a bench row (four heroes, a held surge, the
floor's props); the reference run pinned at the end; one recorded replay regression; `game/tools/coop.gd` checks a
joiner arrives beside the host.

## Milestones

| # | What lands |
|---|---|
| 2 | First playable: one floor, the four classes' basic attacks, minions, props, carry and throw, couch and LAN play, where a joiner appears |
| 3 | App layer: theme, input prompts, rebinding, settings, saves, hero select, EOS, open to friends, both pauses |
| 4 | The crowd at scale (about 500, baked animation), its benchmark rows |
| 5 | Combat depth: abilities, elites, shots where seen, downed and revive, loot shown only when confirmed |
| 6 | Physics set pieces: joints, plates, the lift, boons picked at it, traps, ragdolls, the hoard haul, the party wipe |
| 7 | The run: the hub, three floors with their layouts, the boss, save and continue, difficulty, progress across runs, endless arena |
| 8 | Polish: effects, audio, music, lighting, accessibility |
| 9 | The testing showcase complete, `docs/testing.md` |
| 10 | macOS in CI, release builds, videos, the final README |

## Needed from unified

Each becomes an issue on FylmTM/godot-unified when a milestone needs it:

- `uni release` as a public command (it is unified's own tool today), and able to build a Linux x64 zip on Linux.
  Milestone 10.
- Rendering a recorded session to video (Godot's movie writer at a fixed frame rate), for the videos. Milestone 10.
- Later, filed when it hurts: a shared app layer for games; composing a level from room scenes; the real-UDP net
  suite for game repos; a doc-comment lint a game's tests can run.
