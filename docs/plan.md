# The plan

What is decided about Crypt Crew and not built yet. As each part lands, its facts move into the code, the README and
the doc comments, and leave this file; when the game is done, this file is gone.

## The game

A top-down co-op dungeon crawler for 1–4 players: adventurers go down a crypt full of skeletons, relight its
braziers, and haul its treasure up to the lift.

- **A floor.** Light the braziers while skeleton surges come for you; the lit braziers open the vault. Then carry the
  hoard back to the lift: it has two handles, so two heroes carry it at walking speed and one alone drags it, while
  the crypt wakes behind them. The lift is the save point; each hero picks a boon and the party descends.
- **A run.** A hub between runs (the lobby), three floors, and a boss vault: 20–30 minutes. A run saves at every lift
  and continues from the menu. A player can join or rejoin at any time.
- **Failure.** A downed hero ragdolls (today it lies in its death pose until revived). When the whole party is down,
  the floor restarts from the last save.
- **Heroes.** Four classes (the Profile): Knight (sword arc, shield charge, block), Barbarian (cleave; grabs and
  throws props, elites and allies), Mage (bolt, fireball with a physics blast), Rogue (crossbow that lands where the
  shooter saw the target, dodge roll). Heroes shove and throw each other; they never damage each other.
- **Enemies.** Skeleton minions as the crowd (about 500 alive), Skeleton Warriors (shielded), Skeleton Rogues
  (flankers), Skeleton Mages (ranged, summoners), and a boss. Blasts and charges knock minions back too, through their
  own velocity (a minion has no physics body).
- **Depth.** Difficulty levels (the Setup); an endless arena mode (also the stress and benchmark scene); progress
  across runs (unlocks, best floors, gold hauled) that each player brings into a session through their Profile; each
  floor in 2–3 authored layouts, the run's seed picking the layout and placing spawns, props, traps and loot.

## The look and sound

The look is decided and lives in `docs/ART.md`. Still to come: a cutaway of walls between the camera and the heroes
(milestone 8). Sound: Kenney's (CC0) effects; music: CC0 tracks, picked by the developer from candidates.

## What it shows of unified

Still to show, each where it belongs in the game, with a line in the README pointing at the file that does it: Box3D
sensors, kinematic paths and ragdolls under rollback; rewards shown when confirmed; MultiMesh crowds; debug draws,
recording and replay with seek, F3 notes; and every way of testing (below). What it shows already is the README's.

## How it's built

- **Sim:** elites are Box3D bodies; the rule numbers get presets per difficulty and a quick preset for tests.
- **Ragdolls** drawn on the KayKit skeleton from the bones' rotations.

## Milestone 4: the crowd at scale

About 500 skeletons alive, drawn as one MultiMesh, and the benchmark rows that prove the sim holds them. Decided:

1. **The bake:** each minion clip's bone matrices baked into a texture, the vertex shader skinning a merged, lighter
   mesh (a KayKit minion is 9 meshes and about 5,000 triangles), rather than per-vertex positions. Step 4.
2. **Where 500 fit:** the arena (built, reached by the Setup: `floor=arena`); the endless mode around it stays
   milestone 7's. A floor's cap comes from its walkable area (built: Floor 1 about 110, the arena 500).
3. **Sim speed** (built: the director counting free rows, the 1 m grid with `sim.grid_box` for wider queries, far
   minions' steering every 4 ticks, the surge a quota raised a few a tick, one radial knock for blasts, clamped).
4. **Crowd rules** (built: queueing, a stagger while knocked). A surge grows with the surges faced on its floor; the
   long ramp of a run or of the endless arena is milestone 7's.
5. **Bench rows:** today's kept; crowd_idle, crowd_chase and crowd_fight on the arena through the Setup (built);
   target frame p99 at most 3 ms on the developer's machine, half the library's line (after step 3 every row is
   under it: crowd_chase about 2.7 ms, crowd_fight 2.4, the queue's rings keeping the crowd moving round its heroes).
6. **The bake tool** lives here first and moves into unified's `tools_godot` by the milestone's end. Crowd shadows
   (built: kept, from the arena's frame times in step 5).
7. **From unified:** `View_Policy.ages` for the crowd's clip times (step 5), scenarios and reference runs on a Setup
   (the crowd's scale tests: built).

Steps: 1 the arena, held crowds and honest rows, 2 the sim at 500, 3 the crowd's rules, 4 the bake and its look-dev
shots and 5 the minions a MultiMesh (done); 6 the tool lifted into unified, the README, the reviews.

## How it's tested

`docs/testing.md` (milestone 9) maps each layer to its command and files, with a replay regression for each fixed F3
note, `uni coop --crash`, and the F3 → `uni feedback` → regression loop as a walk-through.

## Milestones

| # | What lands |
|---|---|
| 4 | The crowd at scale (about 500, baked animation), its benchmark rows |
| 5 | Combat depth: abilities, elites, downed and revive, loot shown only when confirmed |
| 6 | Physics set pieces: joints, plates, the lift, boons picked at it, traps, ragdolls, the hoard haul |
| 7 | The run: the hub, three floors with their layouts, the boss, the run's save at each lift, difficulty, progress across runs, endless arena |
| 8 | Polish: effects, audio, music, lighting, accessibility |
| 9 | The testing showcase complete, `docs/testing.md` |
| 10 | macOS in CI, release builds, videos, the final README |

## Needed from unified

Each becomes an issue on FylmTM/godot-unified when a milestone needs it:

- A Linux x64 zip from `uni release` on Linux. (`uni release` itself works in a game repo since unified 830b012:
  macOS arm64 and Windows x64 zips from the game's export_presets.cfg, the unified-release skill; the demo has no
  export preset yet, milestone 10's.) Milestone 10.
- Rendering a recorded session to video (Godot's movie writer at a fixed frame rate), for the videos. Milestone 10.
- `uni drive pad` and `uni drive type` with a device (a second pad's own events), so a play-check drives a couch as
  the walk's tool scripts do (`UnifiedTool.pad_button`). Later.
- A `uni drive` option to boot to the menu (the main scene loaded by the engine, no session flag), so a suite step
  checks real boot, which today is checked by hand. Later.
- A friends list and platform invites, behind an account service (EOS's login today is anonymous): the join code is
  the invite until then. Later.
- LAN discovery (a host's beacon and a list of the games on the network), so a pad player joins without typing an
  address. Later.
- A typed end reason (`UnifiedSession.end_reason`: no online play, lobby not found, full, closed, another build, the
  host left, the link lost), so the game writes its own sentence for each end instead of showing the library's
  detail. Later.
- Later, filed when it hurts: a shared app layer for games; composing a level from room scenes; the real-UDP net
  suite for game repos; a doc-comment lint a game's tests can run.
