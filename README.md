# Crypt Crew

[![ci](https://github.com/FylmTM/godot-unified-demo/actions/workflows/ci.yml/badge.svg?branch=main&event=push)](https://github.com/FylmTM/godot-unified-demo/actions/workflows/ci.yml?query=branch%3Amain+event%3Apush)

The demo game of [unified](https://github.com/FylmTM/godot-unified): co-op games with deterministic rollback netcode,
the rules written in Odin, Godot as the host for rendering, audio, UI and the editor. Crypt Crew is a top-down co-op
dungeon crawler for 1–4 players, and the answer to "what does a real game built on unified look like?".

> [!NOTE]
> **In development.** Today up to four heroes (Knight, Barbarian, Mage, Rogue) walk Floor 1, the first floor of the
> crypt; skeletons, attacks and props come next. The art is posed in a look-dev scene too (`./uni tool lookdev
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
that isn't aimed faces where it walks). Attack: the left mouse button, Space, or a pad's right trigger or X. Interact:
E, the right mouse button, or a pad's A. Esc pauses the game for everyone. Couch co-op: a pad pressing Start joins as
another player, and the keyboard and mouse stay the first player's.

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
