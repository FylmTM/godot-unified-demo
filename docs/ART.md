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
  flash, and the fights' one-shot effects (sparks, a bolt's burst, dust, the crossbow's tracer: a glowing beam, a
  picked-up coin's glint).
- `game/environments/`: each place's Environment (fog, glow, ambient, tonemap).
- `game/lookdev/`: the look-dev scene and its stages.
- `game/crowd/`: the skeleton minions drawn as one crowd: the bake (`crowd_bake.gd`, `crowd_clips.gd`), what is baked
  (`minion_crowd.gd`), the baked mesh, bones and clip table, and the crowd's shader and material (Crowds, below).
- `game/ui/theme.tres`: the interface's one Theme (The interface, below); `game/menu/backdrop.tscn`: the menus'
  graveyard; `game/ui/portraits/`: the heroes' portraits, rendered by `./uni tool render_portraits --window`.

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

## Crowds

The skeleton minions are drawn as a crowd: one MultiMesh of a baked minion (the play scene's `Minions`,
`game/crowd/minion_crowd_view.gd`), each instance posed by its custom data, so hundreds cost one draw call a pass and no
node each, and cast their shadows like the scene minion. `game/crowd/minion_crowd.gd` says what is baked: the minion
scene (`skeletons/minion.tscn`, its blade included; the scene stays for the bake and the look-dev's cast), the clips a
minion plays, in the order an instance names them, the rate each is baked at, and how far its meshes are lightened.
Where in a clip an action starts (the rise, the swing's blow) is the crowd view's.

- **The mesh:** the scene's visible meshes and its blade merged into one surface in the skeleton's bind space, its
  bones and four weights a vertex in `CUSTOM0` and `CUSTOM1`, the eyes marked in `UV2` (one material: the palette, the
  eyes' glow; not the vertex colour, which an instance's colour would multiply). Each mesh but the eyes is lightened to
  the coarsest of Godot's own LODs for it within the minion's LOD error, the importer's simplifier (it moves no vertex
  and keeps the seams, so the palette atlas stays exact).
- **The bones:** every frame of each clip as the bones' skinning matrices (the bone's pose times its bind, what Godot
  skins by), three RGBA float texels a bone, a row a frame, posed through `CharacterRig.pose()`: the crowd poses as the
  scene does. A clip whose bones turn fast between keys is baked at four times its keys' rate, since the shader blends
  two frames' matrices linearly where the scene turns along an arc.
- **The shader** (`crowd_minion.gdshader`, its header the custom data a crowd's view writes): an instance's custom
  data is its clip, the seconds into it and the seconds since it was struck; it skins with four bones blended between
  two frames, loops or holds as `pose()` does, flashes after a hit and sinks the dying out of sight (deeper than the
  death clip's last pose's top, which the bake measures) before their row is freed. Its material is made by
  `MinionCrowd.material()`, every value from where it lives: the palette and roughness from `skeleton.tres`, the eyes
  from `skeleton_glow.tres`, the flash from `hit_flash.tres`, the sink's end from the sim's DEATH_S.

`./uni tool bake_crowd` re-bakes: after the minion's model, weapon, clips or import settings change, the bake's
parameters (`minion_crowd.gd`'s recipe), or the bake's code (`crowd_bake.gd`). The checks hash what the bake is made
from (Godot's version included) and fail while the committed bake is stale; they also make the mesh and the matrices
again and compare, and pose every clip on the minion scene against the crowd's CPU skinning of a sample of its vertices
(every seventh and each bone's farthest), at the frames and where the blend between two strays most. The look-dev
scene's parity stage (`crowd_parity`, `crowd_parity_game`) stands each clip as the scene minion and as the crowd side by
side at the same time, with a flashing and a sinking crowd minion at the row's ends.

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
`NavigationRegion3D` that `uni bake --nav` bakes from the static colliders, decor and props beside it. Each walks in one
piece: its floor bakes into one navigation island, so no gap narrower than an agent cuts the floor in two. The tops of
walls and furniture bake into islands of their own, which nothing reaches. Tall decor without a body stays out of the
walkable floor (or becomes a part with one). `kit_stage.tscn` places every part once. Each stage's `.level` is committed
beside it: the sim plays none of them, and they are baked to prove the kit exports.

## Lighting

The crypt (`game/environments/crypt.tres`): a near-black background, a cool ambient, AgX tonemapping, SSAO, glow from
a threshold of 1 (so only fire, magic and eyes bloom), and a thin fog. A fire (`game/fx/fire.tscn`) is additive
particles over a warm OmniLight3D whose energy and position drift (`Flicker`, seeded by its position, so neighbours
never pulse in step). The braziers' fires cast shadows, which ground everything near them; wall torches, candles and
lanterns don't, because a shadowed light redraws a cube map every frame and a room affords a few. A brazier's bowl
casts no shadow: its own fire burns just above it and would throw the bowl's shape across the floor. Each hero
carries an unshadowed light (`game/fx/hero_light.tscn`). The hub (`hub.tres`, and the hub stage's `Moon`) is moonlit: a weak,
cool, shadowed directional light, lanterns for warmth.

The renderer is Forward+ with 4× MSAA and debanding (`project.godot`).

## The interface

One Theme, `game/ui/theme.tres`, is the project's (`gui/theme/custom`), so every menu, overlay and HUD control has it
with no code; it is a file, edited as text or in Godot's theme editor. It is drawn from Kenney's UI Pack Adventure,
its brown family only: the parchment panel with metal corners for what asks the player something, the dark panel
(darkened, nearly opaque) for plates over the world, the brown button with ink lettering, the hanging banner for a
moment's title. The focus, the pad's cursor, is a gold frame drawn just outside the control, pulsing slowly: the one
bright thing on a menu. Lettering is Kenney Mini Square, and Kenney Future for the game's name on the title; type
variations name each use (`Title`, `Heading`, `HudText`, `Dim`, `Gain` for a pickup's gold "+N", and `Ink`,
`InkHeading`, `InkDim` on parchment).

The canvas is 1920×1080 (`window/size/viewport_*`; the window opens at 1280×720, an export fullscreen, and the canvas
stretches to the window): the pack's Double PNGs draw at their own size there, so they stay sharp up to 1440p. Layouts
hang from the centre and the corners, so a wider screen only gains room. Interface size (Settings, Video: 80 to 130 %)
scales the canvas over that base; a panel sized from the view (the settings) keeps its heading and Back on screen at
every size, its content scrolling; a centred panel, or the title's column, taller than the view less the prompt bar's
room shrinks to fit (`FitToView`), and the toasts keep to the lane between the HUD's plates. The HUD comes after
everything in the readability order: plates in the corners, nothing over the middle, and none of its controls takes a
click or the focus.

Control prompts are Kenney's Input Prompts fonts, one per family (keyboard and mouse, Xbox, PlayStation, Switch);
each font's glyph map (`<font>_map.txt`, vendored as the pack ships it) is baked into a GlyphMap in `game/ui/prompts/`
by `./uni tool bake_glyphs`. A glyph takes its label's colour, cream over the world and ink on parchment. A prompt font
sets its glyph in the middle of a line twice its height, so a glyph sits in a box of its row's height and overflows it
(`game/ui/widgets/action_prompt.tscn`). The settings screen is the parchment panel with the brown buttons as tabs, a
choice for every on/off and every option, and an ink slider with a cream knob; a row lights up while the focus is in it.

The menus stand over a graveyard at night built from the hub kit (`game/menu/backdrop.tscn`), lit as the hub is, with
the four heroes idling at its gate; on hero select the camera comes round to the crew, centred and high above the
seats, and each seat's pick steps forward from the line and strikes its class's stance (Any stays back).

A hero's portrait is rendered from its scene as the game poses it, head and shoulders, idling, on a transparent
background (`game/tools/render_portraits.gd`), with mipmaps so it stays clean drawn small: it changes when the hero
does, and it sits in the brown frame wherever a hero is shown (`PortraitFrame`). Hero select's seats and the HUD's
join and drop cards are one card (`game/ui/widgets/seat_card.tscn`), one size whatever it shows: parchment while
choosing, a green wash and "Ready!" over the portrait once ready, faded while the seat is free; its glyphs are its own
device's. The HUD's hero plates lead with the HP, a red bar over a dark track with the number on it, every bar one
length; the player's name and the class sit above it, the device's controls below. Toasts are small dark plates at the
top, between the hero plates and the counts, on a layer of their own under the menus. The pause menu is the parchment
panel in the middle over a dimmed crypt (the toasts dimmed with it), its prompt bar in the corner like the title's;
the co-op pause's banner hangs below the HUD's top row, between its plates, and hides under the menu. A question or an
explanation is the dialog: its heading, a sentence, the library's own words small under it, its answers, its own
prompt bar replacing the menu's. Play together and its screens, and the pause menu's Invite friends, are the same
parchment panel; a row that can't be used is greyed, the reason under the rows; a code is one portrait-framed cell per
character, the cursor's cell wearing the pulsing focus frame while the field has the focus. The session panel is a
dark plate under the crypt's counts that grows with what it says; the Connecting modal is the parchment panel over the
title; a link in trouble in play is a small dark plate in the lane.

The interface's sounds are Kenney's Interface Sounds, played by `Sfx` (`game/app/sfx.gd`); `Game` gives every button
of the game its press sound and the focus moving its select sound, so no screen plays one by hand; hero select plays
its seats' own (a step, a ready, a seat taken or given up).
