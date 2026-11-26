---
name: unified-release
description: A playable build of a unified game (`uni release`, macOS arm64 and Windows x64 zips) - building one locally, online-capable or not, with or without the dev UI, how a build works (version stamp, export, payload checks, zip, smoke test), and the rules the game's export_presets.cfg, project.godot and .gdextension must follow. Use when the developer asks for a playable build, a zip for a tester or a public build, and when changing export_presets.cfg, the version keys or a .gdextension's dependencies.
---

# A playable build

`./uni release` builds this host's package of the game (macOS arm64 on a Mac, Windows x64 on Windows) into
`.out/release/`: a zip a tester unpacks and plays. Linux builds are not made yet.

```
./uni release                       # <game>-dev-<sha>-<platform>.zip
./uni release --version <x.y.z>     # stamped with a release's version: <game>-v<x.y.z>-<platform>.zip
./uni release --no-eos              # no EOS: single player and LAN only (what a machine without the SDK builds)
./uni release --no-devui            # without the dev UI (-nodevui.zip): a public build
```

Playtest builds keep the dev UI (F3 notes are how a tester reports a problem); a public build drops it. A game that
imports `unified:eos` needs `UNIFIED_EOS_SDK` and the five `UNIFIED_EOS_*` IDs (`.env`, `unified/docs/EOS.md`), or
`--no-eos`. Online-capable packages are made on a developer's machine: a CI runner has neither the SDK nor the IDs.

## How a build works

- **The version.** The repo's `project.godot` says `dev` and the presets `0.0.0`. `uni release` stamps the version
  (`--version`, else `dev-<sha>`) into `application/config/version` (which the game can show) and the presets'
  numeric version keys (a release candidate's numbers: `0.2.0-rc.1` puts `0.2.0` there; `dev-<sha>` puts `0.0.0`),
  for the export only. It puts the files back byte for byte after the export, and on any failure. A run that was
  killed (Ctrl-C) leaves the originals in `.out/release/restore/`; the next `uni release` puts them back first.
  Never commit a stamped `project.godot` or `export_presets.cfg`.
- **The steps**, each failing the build on any error line: the release extension (`--no-devui` builds it without the
  dev UI), Godot's headless import and export, ad-hoc codesign on macOS (the universal template thinned to arm64), a
  check that the export carries the version and every library the extension needs, a zip that unpacks to one folder
  of its own name with the game inside, its `.sha256` (LF line endings, so `shasum -a 256 -c` works on macOS), and a
  headless smoke test of the unpacked zip.
- **Downloads.** Godot is the pinned editor in the per-user cache (`./uni setup` prints where; or `UNIFIED_GODOT` at
  exactly that version); the export templates go to Godot's standard folder, only this platform's files, pulled out
  of the official archive by range requests and checked against unified's `pins.cfg`.

## Rules for the game's export

- `export_presets.cfg` has presets named `macOS` (architecture `universal`: the official template has no arm64-only
  binary) and `Windows Desktop` (`application/modify_resources=false`: no rcedit needed). `project.godot` sets
  `application/config/version` and each preset its version keys (`application/short_version` and
  `application/version` on macOS, `application/file_version` and `application/product_version` on Windows):
  `uni release` fails if one is missing. The template game's presets follow these rules; keep them.
- `application/bundle_identifier` is the game's identity on macOS: a reverse domain of the developer's, letters,
  digits, `-` and `.` only (no `_`). The template's `com.example.<game>` is a placeholder: set it before shipping.
- The presets export Godot resources only (`all_resources`): files the game reads raw (`FileAccess`, e.g. `.level`
  files) must match the presets' `include_filter`, or the export silently leaves them out. `exclude_filter` keeps
  `unified/tools_godot/*` and `game/tools/*` out of the package, never the whole of `unified/`: a running game loads
  `unified/godot_runtime/` (the crowd's clip table and skinning include).
- The smoke test runs a single-player session with unified's own flags (`-- --autostart --ticks N --quit-at-end`),
  nothing of the game's: it requires the extension's `unified: extension initialized` line, the session's result
  line at tick N, exit 0 and no `ERROR` lines. A main scene that starts a session of its own must leave
  `--autostart` to the library (`UnifiedSession.running` is true by the time its scripts are ready).
- Runtime libraries the extension needs ship through the `.gdextension` `[dependencies]` section; `uni release`
  fails if one is missing from the export. `uni build` writes the section from what the extension links (Box3D, the
  EOS SDK): never edit it by hand.
- Online: when the extension imports `unified:eos`, a build fails unless the game build compiled each EOS ID into the
  extension (as `-define`s; logs show them redacted) and the export ships the EOS SDK library: testers' machines
  have no EOS config. With `--no-eos` none of that, and the build fails if the export still holds an EOS SDK library.
- Release binaries contain the build machine's source paths (from bounds-check and assert locations): they reveal
  only the repo's file layout and the work folder, and keeping bounds checks on in release is worth more.
