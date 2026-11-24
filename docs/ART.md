# Art

How Crypt Crew looks, where its art comes from, and the rules that keep it consistent. The game's checks
(`game/tools/art_checks.gd`, in `./uni test --suite godot`) hold the rules below about files, scenes and import
settings; the look itself is judged from the look-dev shots.

## The look

Dark crypts lit by fire: warm pools of torchlight against a cool, dim ambient, so a room reads as shapes and the fires
as the places to be. KayKit's flat-shaded, palette-textured style is kept as it is: no normal maps, no texture detail
added, matte surfaces. Glow is for what gives light (fire, magic, the skeletons' eyes) and nothing else.

Readability comes first, in this order: heroes, enemies, what can be picked up or moved, the room. A hero must read
against any floor and in any crowd, so each carries a soft light of its own; a wall is only ever background.

`game/lookdev/lookdev.tscn` is where the look is decided: the crypt and hub stages, every character posed, and the
camera's shots. `./uni tool lookdev --window --shots` takes the shots into `.out/shots/lookdev/` and reports what each
one costs the renderer (draw calls, objects, primitives).

## Scale and space

One unit is one metre, KayKit's own: a hero is about 2.4 m tall, and every pack shares that scale. The kit's grid is
4 m, with 2 m half steps: a wall is 4 m long, 4 m high and 1 m thick, centred on its grid line; a large floor tile is
4 by 4. The walking surface is y = 0 everywhere: a floor part sinks its model so its flat top sits there (a tile's
relief, rocks or a decoration, is walked through). Characters face +Z.

## Where things live

- `assets/<vendor>/<pack>/`: other people's art, exactly as the pack ships it (names and bytes unchanged:
  `.gitattributes` keeps git from touching their line endings), with the pack's licence as `LICENSE.txt` and a row in
  `CREDITS.md`. Only files the game uses are here: the checks fail on one nothing uses. Godot's `.import` file sits
  beside each.
- `game/materials/`: one material per pack texture (KayKit gives each pack one palette atlas, and each hero its own),
  plus the skeletons' glowing eyes. Every model's mesh draws with its pack's.
- `game/characters/`: the heroes and skeletons as scenes (`heroes/`, `skeletons/`), `character_rig.gd`, the shared
  `rig_animations.tscn`, and `clips.gd`, the clips the game plays.
- `game/levels/parts/<kit>/`: the kit parts levels are built from (`crypt/`, `hub/`).
- `game/fx/`: fire, its flicker, the light a hero carries, the highlight on the prop a hero would grab, a hit's
  flash, and the fights' one-shot effects (sparks, a bolt's burst, dust, the crossbow's tracer: a glowing beam).
- `game/environments/`: each place's Environment (fog, glow, ambient, tonemap).
- `game/lookdev/`: the look-dev scene and its stages.
- `game/ui/theme.tres`: the interface's one Theme (The interface, below); `game/menu/backdrop.tscn`: the menus'
  graveyard.

Everything outside `assets/` is the game's own.

## Adding an asset

1. Copy the file from the pack unchanged into its pack's folder (`assets/kaykit/dungeon/`), with its `.bin` for a
   `.gltf`; a new pack gets a folder, its licence as `LICENSE.txt`, and a `CREDITS.md` row.
2. Use it from a scene: a kit part, a character, a stage; a font or a piece of the UI pack from the theme, a sound
   from `game/app/sfx.tscn`. `./uni test --suite godot` imports it and checks it.
3. A new pack's material gets its shared material in `game/materials/` and a line in `project.godot`'s
   `[importer_defaults]`, which maps the pack's material name to it. The map is by name across every pack: a new
   pack whose material shares a name with an earlier one's gets that one's atlas, which the checks report.

## Import

Godot's own importer, with what differs from its defaults in `project.godot`'s `[importer_defaults]`, which seeds
each new file's `.import`:

- **Materials:** each pack's material name maps to its shared material (`_subresources`), so every model of a pack
  draws with one material we own, and its embedded texture is discarded (`gltf/embedded_image_handling`).
- **Textures:** lossless and without mipmaps (Godot's defaults), and never switched to VRAM compression
  (`detect_3d/compress_to`): a palette atlas is swatches of flat colour, which compression bands and mipmaps blend
  into their neighbours. The UI pack's pieces import the same way: a 720p window draws them at two thirds of their
  size, which needs no mipmaps.
- **No tangents:** nothing uses a normal map.
- **Fonts and sounds** keep Godot's defaults.

The clip files (`assets/kaykit/animations/`) import as animation libraries rather than scenes: their `.import` names
the `animation_library` importer, and the rest of its settings are Godot's defaults. An `.import` is where a file's
settings change; Godot fills in the rest, and the file is committed.

## Characters

A character scene (`game/characters/heroes/knight.tscn`) is a `CharacterRig`: the pack's model as `Model`, the
weapons under `HandR` and `HandL` (BoneAttachment3Ds on the `handslot.r` and `handslot.l` bones of the model's
skeleton), and the shared `AnimationPlayer` (`rig_animations.tscn`, every clip library). Every KayKit character shares
the Rig_Medium skeleton (`CharacterRig.BONES`), so every clip plays on every character. The heroes' materials draw
both sides of a face: their capes and cloaks are single sheets, seen from behind as much as from the front.

| Class | Model | Right hand | Left hand |
| --- | --- | --- | --- |
| Knight | Knight | one-handed sword | badge shield |
| Barbarian | Barbarian | two-handed axe | |
| Mage | Mage | staff | open spellbook |
| Rogue | Rogue (hooded) | two-handed crossbow | |
| Skeleton minion | Skeleton Minion | blade | |
| Skeleton warrior | Skeleton Warrior | axe | large shield |
| Skeleton rogue | Skeleton Rogue | blade | blade |
| Skeleton mage | Skeleton Mage | staff | |

## Animation

The animation player is in manual mode and never advances on its own: `CharacterRig.pose(clip, seconds)` sets the
whole pose. A view computes `seconds` from the simulation's state (what the character is doing and since which
tick), so after a rollback or a replay seek it shows exactly the frame the state says. `clips.gd` names every clip
the game plays (`Clips.WALK`, `Clips.KNIGHT_SLASH`) and which loop (`Clips.LOOPING`): `pose()` wraps those itself,
and a one-shot holds its last frame. The checks pose every clip on every character.

## Kit parts

A part is one piece of a kit as levels place it, never scaled. Floors and walls sit on the grid (a wall's origin on a
grid line, a floor's edges on them), turned in 90° steps; everything else stands anywhere, at any angle.

- **Collidable:** the root is a `StaticBody3D` with its `unified_category` and box or cylinder shapes, the model under
  it. The categories: floor (1), wall (2: blocks walking, sight and shots; its collider stands at least 1.4 m high,
  above the shots' flight), low cover (4: blocks walking only, so it can be shot over; its model is at most 1.5 m
  tall and its collider at most 1.1 m, so a bolt's orb clears it, a model's taller trim left out; anything chest-high
  is a wall). Shapes are simplified and never reach past the model, except a floor's: one box under the model's whole
  footprint, its top at y = 0, reaching below the thin tile. The level exporter turns them into the sim's static
  world (`unified/src/level/README.md`); a placed part never overrides its category. A part may hide a piece of its
  model: the doorway hides its door leaf, because a door is a body of its own.
- **Decor:** a `Node3D` root with no body: a mounted torch, a candle or a lantern with its fire. Plain decor with
  nothing added is placed straight from its glTF.

Heavy furniture (large barrels, kegs, stacked crates, tables) is scenery: parts that never move. What the
simulation moves (small barrels, boxes, chests, coins) is never a part: a body in a level scene would be baked into the
static world. It is placed in a level as a marker and shown by its view. A brazier is a part, a 3 m stand that blocks
shots like a wall; whether it burns is the game's, so its fire is shown apart.

## Stages and navigation

The look-dev stages (`game/lookdev/crypt_stage.tscn`, `hub_stage.tscn`) are built like levels: structure under a
`NavigationRegion3D` that `uni bake --nav` bakes from the static colliders, decor and props beside it. Each walks in
one piece: its floor bakes into one navigation island, so no gap narrower than an agent cuts the floor in two. The
tops of walls and furniture bake into islands of their own, which nothing reaches. Tall decor without a body stays
out of the walkable floor (or becomes a part with one). `kit_stage.tscn` places every part once. Each stage's `.level` is committed beside it: the sim plays none of them, and they are baked to prove the
kit exports.

## Lighting

The crypt (`game/environments/crypt.tres`): a near-black background, a cool ambient, AgX tonemapping, SSAO, glow from
a threshold of 1 (so only fire, magic and eyes bloom), and a thin fog. A fire (`game/fx/fire.tscn`) is additive
particles over a warm OmniLight3D whose energy and position drift (`Flicker`, seeded by its position, so neighbours
never pulse in step). The braziers' fires cast shadows, which ground everything near them; wall torches, candles and
lanterns don't, because a shadowed light redraws a cube map every frame and a room affords a few. Each hero carries
an unshadowed light (`game/fx/hero_light.tscn`). The hub (`hub.tres`, and the hub stage's `Moon`) is moonlit: a weak,
cool, shadowed directional light, lanterns for warmth.

The renderer is Forward+ with 4× MSAA and debanding (`project.godot`).

## The interface

One Theme, `game/ui/theme.tres`, is the project's (`gui/theme/custom`), so every menu, overlay and HUD control has it
with no code; it is a file, edited as text or in Godot's theme editor. It is drawn from Kenney's UI Pack Adventure,
its brown family only: the parchment panel with metal corners for what asks the player something, the dark panel
(darkened, nearly opaque) for plates over the world, the brown button with ink lettering, the hanging banner for a
moment's title. The focus, the pad's cursor, is a gold frame drawn just outside the control, pulsing slowly: the one
bright thing on a menu. Lettering is Kenney Mini Square, and Kenney Future for the game's name on the title; type
variations name each use (`Title`, `Heading`, `HudText`, `Dim`, and `Ink`, `InkHeading`, `InkDim` on parchment).

The canvas is 1920×1080 (`window/size/viewport_*`; the window opens at 1280×720, an export fullscreen, and the canvas
stretches to the window): the pack's Double PNGs draw at their own size there, so they stay sharp up to 1440p.
Layouts hang from the centre and the corners, so a wider screen only gains room. The HUD comes after everything in the
readability order: plates in the corners, nothing over the middle, and none of its controls takes a click or the
focus.

The menus stand over a graveyard at night built from the hub kit (`game/menu/backdrop.tscn`), lit as the hub is, with
the four heroes idling at its gate. The interface's sounds are Kenney's Interface Sounds, played by `Sfx`
(`game/app/sfx.gd`); `Game` gives every button of the game its press sound and the focus moving its select sound, so
no screen plays one by hand.
