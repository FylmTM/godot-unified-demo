# Crypt Crew

[![ci](https://github.com/FylmTM/godot-unified-demo/actions/workflows/ci.yml/badge.svg?branch=main&event=push)](https://github.com/FylmTM/godot-unified-demo/actions/workflows/ci.yml?query=branch%3Amain+event%3Apush)

The demo game of [unified](https://github.com/FylmTM/godot-unified): co-op games with deterministic rollback netcode,
the rules written in Odin, Godot as the host for rendering, audio, UI and the editor. Crypt Crew is a top-down co-op
dungeon crawler for 1–4 players, and the answer to "what does a real game built on unified look like?".

> [!NOTE]
> **In development.** Today up to four heroes (Knight, Barbarian, Mage, Rogue) walk Floor 1, the first floor of the
> crypt, carry and throw its barrels and crates, and are hunted by its skeletons: packs asleep in its rooms, surges
> rising from its graves. A hero at 0 HP goes down and rises beside the party; the whole party down restarts the floor.
> The heroes' attacks come next. The art is posed in a look-dev scene too (`./uni tool lookdev
> --window --shots`). What the game becomes, and in what order, is [`docs/plan.md`](docs/plan.md).

## Play it

You need git, curl and a C toolchain for Odin's linker: clang on macOS and Linux, Visual Studio Build Tools on
Windows. The first `./uni` downloads the pinned Odin; each command fetches what else it needs (Godot, Box3D) the
first time. Nothing is installed by hand. On Windows, run `uni.cmd` instead of `./uni`.

```sh
git clone --recursive https://github.com/FylmTM/godot-unified-demo
cd godot-unified-demo
./uni run                            # play it in a window
./uni run -- --host-port 7777        # host a game on the LAN...
./uni run -- --join 127.0.0.1:7777   # ...and join it from a second window
./uni help                           # every command
```

**Controls.** Move with WASD, the arrow keys or a pad's left stick; aim with the mouse or the right stick (a hero
that isn't aimed faces where it walks). Interact (E, the right mouse button, or a pad's A) picks up the barrel or crate
in front, glowing faintly, and puts it down again; Attack (the left mouse button, Space, or a pad's right trigger or
X) throws what you carry. Esc, or Start on a pad that plays, pauses the game for everyone. Couch co-op:
the first player's first input claims their device (the keyboard and mouse, or a pad), and any other pad pressing
Start joins as another player.

## How it's built

- `simulation/crypt_crew/`: the deterministic simulation, the game's rules (Odin). Everything the game is lives in
  one block of plain data that rollback copies, restores and checksums.
- `simulation/extension/`: the GDExtension that runs the simulation inside Godot and turns its state into views.
- `simulation/headless/`: the same simulation without Godot, for tests, sync-tests, replays and benchmarks.
- `simulation/tests/`: the rule tests, unified's standard rollback and network scenarios, and the determinism lint.
- `game/`: the Godot side (the project is the repo root, `project.godot`): scenes, views and UI. GDScript shows the
  simulation and never changes it; input and commands are the only way in.
- `assets/`: the art packs the game uses (`CREDITS.md`); how they become the game's look is `docs/ART.md`.
- `tools/`: this game's `uni` CLI. `unified/`: unified, as a git submodule.

## The view contract

What the sim shows Godot and what Godot sends back, each declared in `simulation/extension/`:

- `View_Hero` (`frame.odin`, GDScript `ViewHero`, its scene `game/views/hero.tscn`): a hero, keyed by its player,
  posed at its feet and turned to its facing (a local hero's from its newest input). Its velocity in its own frame
  (x to its right, y ahead) picks the gait; its class picks the character; its action and the game time it started
  pose a one-shot (a pick-up, a throw, going down); `carrying` says it holds a prop, `grace` that it just rose and
  takes no damage (it blinks).
- `View_Prop` (`frame.odin`, `ViewProp`, `game/views/prop.tscn`, pooled): a barrel or crate, keyed by its handle,
  posed at the bottom of its body and turned with it. Its kind picks the model; `held_by` names its carrier; `aimed`
  says a local hero's Interact would grab it now (the rules' own `grab_target`), which the view highlights.
- `View_Minion` (`frame.odin`, `ViewMinion`, `game/views/minion.tscn`, pooled, shown once its spawn is verified): a
  skeleton, keyed by its handle, posed at its feet and turned to its facing; its phase (rising, asleep, chasing,
  swinging, dying) and the game time it began pose its clip.
- `Data_Hud` (`hud.odin`, `Unified.data.hud`): each slot's hero (player, HP, class, whether it is local), the minions
  alive, the kills and the co-op pause.
- `Input_Values` (`input.odin`, `Unified.local_input(local)`): the mouse's aim, from the keyboard player's hero to
  where the cursor points on the floor, set by `game/play/play.gd` on the session's `input_wanted`.

## Benchmarks

CI runs the simulation's benchmarks on Linux x64, Linux arm64 and Windows x64 for every push to `main` (macOS joins
when development is done): the
[latest push run on `main`](https://github.com/FylmTM/godot-unified-demo/actions/workflows/ci.yml?query=branch%3Amain+event%3Apush)
has each platform's numbers in its summary. Locally: `./uni bench`.

## License

The code is licensed under either of [Apache License 2.0](LICENSE-APACHE) or [MIT license](LICENSE-MIT), at your
option. Art, sound and music keep their own licences (all CC0), listed with their sources in `CREDITS.md`.

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as
defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.
