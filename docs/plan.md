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

KayKit's free packs (CC0): Adventurers (the heroes), Skeletons (the enemies), Character Animations (one rig and clip
library for both), Dungeon Remastered (the crypt kit), Halloween Bits and Forest Nature (the hub). Kenney (CC0) for
the UI, input prompts, fonts, particles and sound effects. Music: CC0 tracks, picked by the developer from
candidates. Dark crypts lit by torches: fog, glow and particles on KayKit's flat-shaded style.

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

## Milestones

| # | What lands |
|---|---|
| 1 | Assets: the used subset imported, the animation library, the crypt kit as part scenes with collision, a look-dev scene |
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
- Check that a view can read the shown game time between ticks (animation needs it); add it if not. Milestone 2.
- Later, filed when it hurts: a shared app layer for games; composing a level from room scenes; the real-UDP net
  suite for game repos; a doc-comment lint a game's tests can run.
