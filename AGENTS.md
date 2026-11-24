# Working on Crypt Crew

Crypt Crew (this repo, `godot-unified-demo`) is unified's demo game: a top-down co-op dungeon crawler for 1–4 players,
and the answer to "what does a real game built on unified look like?". It is also unified's testing ground (Workflow,
below). What is decided and not built yet is `docs/plan.md`.

## Roles

- The developer decides design questions. Explain options, recommend one, and ask; don't settle a design question
  silently. Small reversible tuning is fine. Say what you changed.
- Engagement, in order of preference: explain in chat and ask; a one-off `.html` page for something too large for
  chat; a Markdown doc.
- **Design, then build, then review.** Every design task (a milestone, a system, the look) gets two independent
  designers, one on Opus and one on Fable, at high effort; their proposals are merged and the open questions go to
  the developer. Every change to code, scenes, CI or docs gets two independent reviewers on the same two models
  before it is pushed (a typo or a one-line tuning tweak excepted). Clear bugs and quality findings are fixed without
  asking; a finding that would change a decision goes to the developer.

## The bar

This repo is shown to people as the example of a game on unified. Everything in it is exemplary:

- **Clean and typed.** Odin follows unified's rules for names and pitfalls (`unified/.claude/rules/odin.md`).
  GDScript follows `unified/.claude/rules/godot.md` (typed end to end, sim data dispatched by class, no `preload()`
  in play-scene scripts, `.uid` files committed), members in the Godot style guide's order, signals up and calls
  down, no absolute node paths. Neither rules file loads on its own here: read the one you need.
- **Organized.** One system per file in the sim; one scene per thing in Godot, its script beside it. A reader finds a
  thing where its name says it is.
- **Documented for a reader exploring the code.** Every `.odin`, `.gd` and shader file opens with a short header: what
  it is and why it is shaped this way. Every public Odin declaration has a doc comment. Comments say why, and how it
  works under the hood, enough to orient a reader; none narrates what a line plainly does.
- **Nothing half-done on `main`.** No dead or commented-out code; a workaround or a TODO links the godot-unified issue
  or the `docs/plan.md` item it waits on.

## Rules

- **Deterministic sim.** `simulation/crypt_crew` runs inside rollback netcode. Follow unified's rules
  (`unified/AGENTS.md`, Non-negotiables; `unified/docs/gameplay.md`, the patterns that survive rollback). The
  determinism lint in `uni test` enforces f32 only, no `core:math`, no `map`, and dmath's `min`/`max`/`clamp` (the
  builtins are banned, even on integers). By convention, which no lint sees: a float→int conversion that can
  overflow goes through `dmath.to_i32_clamped`, and randomness comes only from a stream kept in the state or a roll
  keyed by what it is for. The state block is pointer-free and padding-free (explicit `_pad` fields).
- **Rule numbers in `tuning.odin`.** Numbers a designer will tune are named constants there, never inline in rules.
  A level's own numbers are its markers' properties.
- **The Input is held state; every one-shot is a command.** Prediction repeats an input and the relay replaces a late
  one, so a one-shot never goes in `Input`: presses are `sim.buttons` edges, everything else a `Command_*`. A hero is
  owned by a `sim.Player`, never an input slot.
- **The view never changes the sim.** `simulation/extension` and `game/` show the state; input and commands are the
  only way in. Animation is a function of view data (what a hero is doing and since when), so a rollback or a replay
  seek always shows the right frame.
- **Assets.** Free CC0 packs only (KayKit, Kenney, CC0 music), and only the files the game uses, each pack's licence
  beside them and a line in `CREDITS.md`. The look and the art pipeline are `docs/ART.md`: read it before touching
  anything visible.
- **No names of the games we take ideas from**, in the repo or in the game.
- **Fast.** Builds take seconds and tests run in seconds; a slowdown in `uni bench` is a bug to explain.

## Workflow

- **Changes go straight to `main`**: `./uni verify` passes, the reviews are done, then commit and push. No PRs, no
  issues: rewrite `docs/plan.md` as work lands, and drop what is done once the code and README say it.
- **CI** (`.github/workflows/ci.yml`; its header says what runs when). A red push run on `main` is fixed before
  anything else lands. A red nightly canary means unified's `main` broke this game: fix it in unified, or file it on
  godot-unified; it doesn't block work here.
- **The testing ground.** Before a unified change is done, it runs here: locally, check the branch out in `unified/`
  and run `./uni refresh` and `./uni verify` (then put the submodule back); or in CI,
  `gh workflow run ci.yml -f unified_ref=<branch or full commit SHA>`.
- **`unified` (FylmTM/godot-unified) is alpha, and we grow it as we go.** What the game needs from it becomes an
  issue on FylmTM/godot-unified (what, where it hurt, a proposed shape), worked around here meanwhile, with a comment
  at the workaround that links the issue (so a bump can find and drop it).
- **Updating `unified` is its own commit**: bump the submodule on purpose, then `./uni refresh` and `./uni verify`,
  never as a side effect of another change.
- **Never disturb the developer's main screen or keyboard.** A game window an agent opens starts muted on the leftmost
  screen and never takes focus (the commands below). The editor always takes focus: open it only when asked.

## Commands

Godot-side changes: `./uni test --suite godot`. The game in a window: `./uni run --mute --screen left --background`;
a host and a joiner in two windows: `./uni coop --lan --window`; driven by an agent: `./uni drive start` (then its
verbs, `./uni drive -h`). A changed level: `./uni bake`.

## Docs

One home per fact: README.md (what the game is, how to play, how it works, the view contract), `docs/ART.md` (the
look and the art pipeline), `docs/plan.md` (what is decided and not built yet). History lives in git. Commit messages
end with the co-author line.

<!-- unified: begin: managed by `./uni refresh`, edit outside it -->
This game is built on unified, the pinned `unified/` submodule. Before writing code or running tools, read
`unified/docs/agent-guide.md`. Everything runs through `./uni` (`uni.cmd` on Windows; `./uni help`); run `./uni verify`
before handing work back.
<!-- unified: end -->
