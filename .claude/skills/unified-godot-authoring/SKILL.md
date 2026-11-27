---
name: unified-godot-authoring
description: Writing the Godot side of a unified game without the editor - scenes, scripts, resources, levels, input maps and UI as text, or made by a throwaway GDScript run with `uni tool <path>` through Godot's own API; the .tscn text that works, the typed-GDScript traps the validate step reports, UI-game rules and the check loop. Use when creating or changing a game's scenes, levels, input actions, HUD or menus.
---

# Authoring the Godot side without the editor

Nothing needs the editor. Write a small change as text (scenes, `.tres`, scripts, `project.godot`). Anything
repetitive or verbose, such as a level of many pieces or the input map, is made the way the editor makes it: by
Godot's own API from a **throwaway GDScript** run against the project. The rules for the files themselves are below.
Checking and running the game is the `unified-godot` skill.

## Rules for the files

- Godot 4 (the version unified pins), the standard (non-.NET) build. Check APIs against the 4.x docs, not Godot 3:
  what you remember mixes them.
- GDScript is typed: every declaration has a type (`untyped_declaration` is an error, and every tool-script run fails
  on a warning). Members in the order of Godot's style guide: signals, enums, constants, exports, vars, `@onready`
  vars, virtuals, public, private.
- Godot writes a `.uid` file next to every new script and shader: commit it with the file.
- Never edit `.godot/`: it is Godot's cache. An asset's `.import` file is its import settings, which Godot writes
  and the game commits: change a setting in its `[params]` (new files take theirs from `project.godot`'s
  `[importer_defaults]`), keep its `uid`, and the next `uni` command re-imports it.
- `res://unified/tools_godot/` is unified's tool scripts (the submodule): changed in unified, never in a game.
- A tool script (`-s`) is compiled before the autoloads exist: it never names a script that uses an autoload (reach
  those through the scene tree). Scripts the play scene loads never `preload()`.
- A menu that loads the play scene in the background (`ResourceLoader.load_threaded_request`) skips it headless
  (`DisplayServer.get_name() == "headless"`): Godot's headless (dummy) renderer stores textures without a lock, so
  the loading thread's textures and the main thread's collide now and then (`Parameter "t" is null`, a texture
  leaked at exit). The scene switch loads it instead.
- Sim data is typed end to end: an event handler dispatches by class (`if event is EventRockHit: var hit := event
  as EventRockHit`) with `state: UnifiedSession.EventState`, never on `event.kind`; nested data is read as its class
  (`for p: DataHudPlayer in Unified.data.hud.players`), never with `.get("field")`. A view's data is its root
  script's `var data: ViewCard` (the kind's class), set before `_ready` and anew on each change: react in its setter
  (old value against new), and from another script read it typed (`var card_data: ViewCard = node.get(&"data")`).
- GDScript is the view layer only: it reads the sim and never writes it (input and commands are the only way in).
  Anything performance-critical is Odin.
- After editing a level scene, `./uni bake`, and commit the scene and its `.level` together.

## Throwaway scripts

A script extends `UnifiedTool`, does its work in `_run()`, and `expect()`s that it saved. Keep it outside the game,
in your scratchpad, and run it with `./uni tool <path/to/script.gd>`: a path ending in `.gd` is run against the
project and never joins it (`./uni tool -h`). What it puts in `result` is printed on the result line, the way to read
a value out of Godot. The examples below each run as they are; copy one, change it, run it:

- `scripts/make_level.gd`: a level of boxes and ramps, each a `StaticBody3D` with its `CollisionShape3D` and its
  `MeshInstance3D` sharing one material, under a `NavigationRegion3D` that opts into `uni bake --nav`, and a marker.
  Then `./uni bake --nav`. What a level may hold (shapes, metadata, markers, navigation) is in
  `unified/src/level/README.md`, Authoring.
- `scripts/add_actions.gd`: input actions in `project.godot` (`ProjectSettings.set_setting("input/<action>", ...)`
  and `ProjectSettings.save()`), for keys, mouse buttons and joypads. A joypad event needs `device = -1`, or it
  hears the first joypad only.
- `scripts/make_panel.gd`: a Control scene, a centred panel with unique names (`%Title`, `%Start`).

(`scripts/` is beside this file, in `.claude/skills/unified-godot-authoring/`.) What to know when writing one:

- `PackedScene.pack(root)` saves only the nodes whose `owner` is the root: set it on every node you add.
- A tool script is a `SceneTree`: it already has `root` (and its other members). A member of that name is a parse
  error. Name the scene you build `scene`.
- Build rotations in code (`Basis(Vector3.RIGHT, deg_to_rad(15))`) rather than typing basis numbers.
- `ResourceSaver.save` needs the directory: `DirAccess.make_dir_recursive_absolute(path.get_base_dir())`.
- Godot adds a `unique_id` to every node it saves: a re-saved scene diffs noisily, harmlessly.
- The scene's mesh is the view, and the shapes are what the sim collides with. A shape Godot draws no mesh for (a
  `ConvexPolygonShape3D` wedge, a `HeightMapShape3D`) gets a small `@tool` script on its `MeshInstance3D` that builds
  an `ArrayMesh` from the sibling shape, so the two never drift apart.

## Text that works

A hand-written scene is format 3, with resources before nodes. An `ext_resource` is referenced by `path` with a short
`id`; a `sub_resource` lives in the file. The root node has no `parent`, and its children take `parent="."` or
`"Panel/Rows"`. `unique_name_in_owner` makes a node `%Name` to its scene's scripts. A full-window HUD with a label in
the top right corner:

```
[gd_scene format=3]

[ext_resource type="Script" path="res://game/ui/score.gd" id="score"]

[sub_resource type="StyleBoxFlat" id="backing"]
bg_color = Color(0.1, 0.1, 0.12, 0.85)

[node name="Score" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("score")

[node name="Points" type="Label" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -168.0
offset_top = 8.0
offset_right = -8.0
offset_bottom = 40.0
grow_horizontal = 0
theme_override_styles/normal = SubResource("backing")
text = "0"
```

Its script reads the label with `@onready var _points: Label = %Points`. Styles can be built in GDScript too
(`StyleBoxFlat.new()`), which is easier to get right without seeing them.

**`Transform3D` in text is row by row:** `Transform3D(x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z, ox, oy, oz)`,
where `x`, `y` and `z` are the basis axes. The GDScript constructor `Transform3D(x_axis, y_axis, z_axis, origin)`
takes the axes themselves, as columns. A turn of +15° about x is `Transform3D(1, 0, 0, 0, 0.966, -0.259, 0, 0.259,
0.966, ...)` in text.

## Typed GDScript: what validate stops on

Every warning is an error. These are the ones that catch everybody:

- **A local named like something inherited or global**: `floor` ("has the same name as a built-in function"),
  `name` ("shadowing an already-declared property"), `ready` (a signal). Name it after what it holds:
  `floor_index`, `piece_name`.
- **A Variant where a type is needed**: an Array or Dictionary element, `get()`, or an untyped return. `x as float`
  on a Variant is "Casting "Variant" to "float" is unsafe", and `look_at(a[0])` is "requires the subtype". Assign it
  to a typed local first (`var tilt: float = piece[3]`).
- **An unused private (`_name`) member**, an `@onready` one included: "declared but never used in the class".
  Delete it.
- **Integer division** (`int / int`). Divide floats, or `@warning_ignore("integer_division")` where truncating is
  meant.
- **A void function used as a value** (`if not check()`): a parse error.

## UI games

- The root and every full-window Control that is not meant to catch clicks take `mouse_filter = 2` (ignore). The
  default stops the click there, so `_unhandled_input` never sees a right click.
- Keep the project's `window/stretch/mode="canvas_items"` (the template sets it): the UI then scales with the window.
- Rebuild a panel only when what it shows changes: key it on exactly those values. A rebuild between a press and its
  release loses the click, and that only shows in one run of several.
- Look at a screenshot before trusting the default theme: deckbuilder's HP bars showed no fill until they had a style
  of their own (`add_theme_stylebox_override(&"fill", ...)`).
- Never write to a Theme, or a StyleBox or Font it holds, every frame (a pulsing focus ring, say): each write emits `changed` and re-themes every
  Control under it (milliseconds of process time a frame; `uni tool -- --frames` shows it as scene process, not
  draw). Animate a node's `modulate`, a material, or a node of its own instead.

## The check loop

Validate after every change, then play-check with `uni drive` screenshots: the `unified-godot` skill. On top of it:

- `./uni drive eval <expression>` reads engine state that `state` and `find` don't give, such as a node's rect or a
  property. Write GDScript strings in it with single quotes.
- A UI game gets a walk early: `game/tools/ui_walk.gd`, a `UnifiedTool` that plays the menus and flows with real
  clicks (`click`, `click_at`), as `unified/examples/deckbuilder/game/tools/ui_walk.gd` does. The godot suite runs
  it as its `walk` step. Run it 5 or more times in a row (`./uni tool ui_walk`): a lost click shows in one run of
  several.

## Writing files on Windows

Windows PowerShell 5.1 corrupts text: `Set-Content -Encoding utf8` writes a BOM, `>` writes UTF-16, and double-quoted
strings eat backticks. Python's text mode writes CRLF. Write files with the Write and Edit tools, or with a script.
