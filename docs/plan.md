# The plan

What is decided about Crypt Crew and not built yet. As each part lands, its facts move into the code, the README and
the doc comments, and leave this file; when the game is done, this file is gone.

## The game

A top-down co-op dungeon crawler for 1–4 players: adventurers go down a crypt full of skeletons, relight its
braziers, and haul its treasure up to the lift.

- **Depth.** Each floor in 2–3 authored layouts, the run's seed picking the layout and placing spawns, props, traps
  and loot.

## The look and sound

The look and the sound are decided: the look lives in `docs/ART.md`, the sound in `game/app/sfx.gd`, `game/play/sounds.gd`
and `game/app/music.gd`. Still to come: the music's tracks for its contexts (title, hub, floor, the King, the Pit,
results: CC0, picked by the developer from candidates); Music plays silence over the room's tone until then.

## What it shows of unified

Still to show, each where it belongs in the game, with a line in the README pointing at the file that does it: debug
draws, recording and replay with seek, F3 notes; and every way of testing (below). What it shows already is the
README's.

## How it's tested

`docs/testing.md` (milestone 9) maps each layer to its command and files, with a replay regression for each fixed F3
note, `uni coop --crash`, and the F3 → `uni feedback` → regression loop as a walk-through.

## Milestones

| # | What lands |
|---|---|
| 9 | The testing showcase complete, `docs/testing.md` |
| 10 | macOS in CI, release builds, videos, the final README |

## Needed from unified

Each becomes an issue on FylmTM/godot-unified when a milestone needs it:

- An occlusion option for `physics.world_explode` (a blast's impulse only on shapes a ray from its centre reaches
  past a mask's shapes), so a blast is Box3D's own and walls shield what is behind them: the fireball applies its
  impulse per body meanwhile, a prop, an elite, the hoard, a ragdoll's bones, a barricade
  (`simulation/crypt_crew/fireballs.odin`, blast_bodies). Later.
- Navigation that can close an edge (`nav.field(fields, goal, closed: sim.Bits)`), so minions route round a shut gate
  or a standing barricade rather than crowd against it, and the bot's walk to Floor 1's passage plate needs no detour
  by the gate's front (`simulation/tests/bot.odin`, gate_front). Later.
- A packed bones view field (`godot.Bones(N)`, a PackedFloat32Array), if the ragdoll's bone Array shows in a frame's
  cost (`simulation/extension/frame.odin`, View_Ragdoll). Later.
- `uni release` on a fresh checkout: its strict import fails on the error lines Godot prints while it loads the
  project theme before the theme's textures are imported (exit 0). Run unified's tolerant import (`ensure_imported`)
  first, as every other command does. CI's release job runs `./uni bake --check` first meanwhile. Milestone 10.
- `uni bake --check` on macOS: headless Godot reports a leaked RID at exit (`RendererDummy` ... `DummyShader`) and
  bake fails on that line, though every level is current. Milestone 10.
- A Linux x64 zip from `uni release` on Linux (the demo's macOS arm64 and Windows x64 zips are `./uni release`'s,
  built and played in CI). Later.
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
- Verified session data: a `Data_*` value from the newest verified tick, beside the prediction's, so a HUD can start
  what must be final from it. The purse starts from the predicted HUD data once and counts confirmed pickups after
  (`game/play/purse.gd`). Later.
- Per-instance colour on a MultiMesh view, so one kind draws its instances in more than one colour: a skeleton
  Mage's bone bolts are a kind of their own meanwhile (`MultiView.Bone_Bolt`, `simulation/extension/frame.odin`).
  Later.
- Later, filed when it hurts: a shared app layer for games; composing a level from room scenes; the real-UDP net
  suite for game repos; a doc-comment lint a game's tests can run.
