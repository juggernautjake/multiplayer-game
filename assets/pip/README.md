# assets/pip/

The sprite sheets for **Pip** ("Pip the Peasant"), Jacob's pixel-art character from his Pip project
(`04-games/pip`, outside this repository). In the game, Pip is one of the two looks the host can choose for every
player (the other is the 3D figure). Only `scripts/avatar.gd` loads these files, through its `SHEETS` constant.

Back to [assets/](../README.md) or the [project README](../../README.md).

## How the sheets are laid out

Both sheets share one layout, described by their JSON files:

- **Cells** are 64 x 64 pixels. Each **row** is one animation seen from one direction; each **column** is a frame.
- The **anchor** is pixel (32, 58) in every cell: the point where Pip's feet touch the ground. `Avatar` offsets the
  sprite so that this point sits on the player's position.
- **Directions:** five are drawn (S = facing the camera, SE, E, NE, N = back to the camera). The other three are
  mirrored: SW from SE, W from E, NW from NE. `Avatar._dir_for` picks the view from the camera angle and flips the
  sprite for the mirrored ones.
- Each entry in `animations` has: `name`, `group` and `label` (for Jacob's sheet viewer), `dir`, `row`, `frames`,
  `durationsMs` (one duration per frame, in milliseconds), `events` (all empty so far), `loop`, and `facesCamera`.
- In the game, Pip is drawn at 0.04 m per pixel, so he stands about 1.8 m tall.

## pip-spritesheet.png

Pip's main sheet: 1344 x 12800 pixels (21 columns by 200 rows of 64 x 64 cells), RGBA with transparency. It holds 65
animations in 200 rows: the movement, combat and carrying animations are drawn in all five directions, while 30
animations (the emotes, fidgets, sleeping, lying in bed and so on) have a single row facing the camera. `Avatar` uses
whatever direction exists when the one it wants is missing. Hand-drawn; it comes from Jacob's Pip project, not from a
script here.

## pip-spritesheet.json

The frame data for `pip-spritesheet.png` (layout above). Groups and the animations in each:

| Group | Animations |
|---|---|
| Moving | `idle`, `walk`, `run`, `dash` |
| Jumping | `jumpStart`, `air`, `land` |
| Ground combo | `jab`, `cross`, `kick`, `wjab`, `wcross`, `runAtk` |
| Air combos | `airPunch`, `airKick`, `dive`, `flyKick` |
| Wooden club | `c_swing`, `c_back`, `c_smash`, `wc_swing`, `wc_back`, `rc_swing`, `ac_swing` |
| Moods & rest | `huff`, `pant`, `sleep`, `sitGround`, `e_happy`, `e_excited`, `e_sad`, `e_angry`, `e_cry`, `e_tired` |
| Make yourself at home | `sitDown`, `sitIdle`, `standUp`, `lieDown`, `lieIdle`, `lieSleep`, `getUp`, `pickUp`, `putDown`, `carryIdle`, `carryWalk`, `carryRun` |
| Avatar | `scratch`, `lookAround`, `think`, `listen`, `wave`, `hum` |
| Idle fidgets | `f_candy`, `f_nose`, `f_pick`, `f_sing`, `f_jig`, `f_juggle`, `f_yawn`, `scratchQ` |
| Talking | `hop`, `shy`, `proud`, `laugh` |

The game uses only some of these today (chosen in `Avatar._pick`): `idle`, `walk`, `run`, `dash`, `jumpStart`, `air`,
`land`, `jab`, `cross`, `kick`, the seven club animations, and `lieDown` / `lieIdle` for a knocked-out player. The
rest are ready for later (emotes, sitting, carrying and so on).

## pip-weapons.png

Pip's weapon frames: 448 x 3520 pixels (7 columns by 55 rows of 64 x 64 cells). **Generated** by
`tools/make_weapon_frames.py` from the main sheet; don't edit it by hand, run the script again instead.

- Sword: every club animation with the club repainted as a sword.
- Bow and slingshot: Pip's punch pose with a bow or slingshot drawn at his fist.

## pip-weapons.json

The frame data for `pip-weapons.png`, written by `tools/make_weapon_frames.py` in the same layout as the main sheet.
All 11 animations are in the group "Weapons":

| Animation | Frames | What it shows | Used for |
|---|---|---|---|
| `s_swing`, `s_back`, `s_smash` | 6, 6, 7 | standing sword slash, backslash and thrust (from the club's swing, backswing and smash) | sword combo |
| `ws_swing`, `ws_back` | 5, 5 | the same while walking | sword while moving |
| `rs_swing` | 5 | running swing | sword at a run |
| `as_swing` | 6 | swing in the air | sword while jumping |
| `bowDraw`, `bowShot` | 3, 2 | drawing the bow (string further back each frame, arrow loaded) and the release | bow |
| `slingDraw`, `slingShot` | 3, 2 | pulling the slingshot's pouch back and the release | slingshot |

While a bow or slingshot is being drawn, `Avatar` picks the draw frame from how far it is drawn rather than from the
clock.

## .import files

`pip-spritesheet.png.import` and `pip-weapons.png.import` are Godot metadata, written by the editor: they tell Godot
to import each PNG as a lossless texture without mipmaps and record the texture's unique ID. Commit them; don't edit
them by hand.

## outfits/

Recoloured copies of both sheets made by `tools/make_outfits.py`: `-1` blue, `-2` green, `-3` crimson (guests, in the
order they join), and `-4` grey and `-5` dark violet-black: the robes of the wizard garb, used while Pip carries the
staff (grey) or the wand (dark).
