# tools/

Developer tools: automated tests, picture renderers for checking animation, the release script, the generator for
Pip's weapon frames, and a model of the netcode. None of this ships in the game: `export_presets.cfg` excludes
`tools/*` from exports.

The `.gd.uid` file next to each GDScript is Godot metadata: the script's unique ID, written by Godot. Commit them;
don't edit them.

Back to the [project README](../README.md).

In the commands below, `<godot>` is your Godot 4.7 console executable (for example
`Godot_v4.7.2-stable_win64_console.exe`), run from the repository folder. The GDScript tools all extend `SceneTree`
and are run with `-s <script>` (or `--script`), which runs the script instead of the game. Arguments after `--` reach
the script through `OS.get_cmdline_user_args()`.

## At a glance

| File | Kind | Needs a window? | In one line |
|---|---|---|---|
| [sim_test.gd](#sim_testgd) | test | no | Checks the shared movement and combat simulation. |
| [fruit_test.gd](#fruit_testgd) | test | no | Checks fruit physics in the yard. |
| [eco_test.gd](#eco_testgd) | test | no | Runs the yard for 20 minutes and checks that everything happens. |
| [invite_test.gd](#invite_testgd) | test | no | Checks that invite codes round-trip. |
| [cloth_test.gd](#cloth_testgd) | test | no | Dashes a robed body and checks the cloth keeps up without stretching. |
| [figure_poses.gd](#figure_posesgd) | renderer | yes | One pose of the 3D figure, saved as a PNG. |
| [figure_strip.gd](#figure_stripgd) | renderer | yes | A filmstrip of one move of the 3D figure. |
| [pip_feet_check.gd](#pip_feet_checkgd) | renderer | yes | Pip at ground level, to check his feet sit on the ground. |
| [release.sh](#releasesh) | script | no | Builds and publishes a new version on GitHub. |
| [make_weapon_frames.py](#make_weapon_framespy) | asset generator | no | Makes Pip's sword, bow and slingshot frames from his sheet. |
| [netcode_model.py](#netcode_modelpy) | model | no | Simulates the netcode over bad connections and counts corrections. |

---

## sim_test.gd

Headless checks of the shared simulation (`Sim`, with the world from `WorldLayout`).

```
<godot> --headless --path . -s tools/sim_test.gd
```

It prints `ok` or `FAIL` for each check, then "N failed", and exits with 1 if anything failed. The checks:

1. Walking into the low step near the spawn (at 6, -6) never goes inside it, and stops beside it on the ground.
2. Jumping while walking into it ends standing on top.
3. Walking off the far side lands back on the ground.
4. Dashing into a tall pillar never goes inside it.
5. Determinism: two runs of the same 600 inputs agree exactly.
6. For fists, club and sword: attacking with no movement keys stays in place; swinging while walking steps forward.
7. Walking right turns the body to face right; `FACE_CAM` faces the camera heading.
8. Holding attack faces the camera heading, not the skewed line to a close crosshair point.

Helper functions: `check(ok, what)`, `run(state, buttons, yaw, ticks)` (steps a state), `inside_any(state)` (is the
player overlapping a box).

## fruit_test.gd

Headless checks of fruit physics in `Ecology`.

```
<godot> --headless --path . --script tools/fruit_test.gd
```

1. Hitting the apple tree three times drops fruit. Each fruit's path ends at rest, it hasn't moved 10 s after landing,
   its path has no jumps (no step over 0.6 m in a tick), and it rests outside every pillar, trunk and dummy.
2. A person walking into a fallen fruit kicks it the way they walk; it rolls more than 0.5 m and comes to rest
   smoothly.
3. A melee blow (`Ecology.hit_fruit`) launches it: it pops up more than 0.2 m, lands more than 1 m away from the
   swing, and rests outside everything.
4. A fruit rolled straight at a pillar bounces off and stops outside it.

Prints "N failed" and exits with the number of failures as its code. Helpers: `check`, `smooth(segs, from, to)` (the
biggest step along a path), `inside_something(p)`.

## eco_test.gd

Runs the server's yard (`Ecology`) for 20 simulated minutes with no players near, and hits the first fruit tree once
at 30 s. Then prints how many of each event kind happened and how many of each worm and bird phase.

```
<godot> --headless --path . -s tools/eco_test.gd
```

It passes (`ECO OK`, exit code 0) if at least one `fruit_fall`, `worm`, `bird` and `tree_hit` event happened;
otherwise `ECO FAIL` and exit code 1. (Its header comment also mentions a run with a player standing by a tree; the
code only runs with no players.)

## invite_test.gd

Checks the invite-code functions in `scripts/main.gd` (`invite_code` and `decode_invite`, loaded with
`load("res://scripts/main.gd")` because main.gd has no `class_name`).

```
<godot> --headless --path . -s tools/invite_test.gd
```

For five address and port pairs (including `0.0.0.0:0` and `255.255.255.255:7777`) it encodes, decodes the code in
lower case, and checks that the result matches. It also shows that a plain address is not taken for a code. Exits with
the number of failures.

## figure_poses.gd

Renders a close-up of the 3D figure (`FigureAvatar`) in one pose and saves it as a PNG, with small markers: red for the
right hand, green for the left hand, yellow for the weapon's grip point (it should sit in the hand). Needs a window
(no `--headless`), because it renders.

```
<godot> --path . -s tools/figure_poses.gd -- out.png <pose> [view_degrees] [no-markers]
```

- `out.png`: where to save (default `user://pose.png`).
- `pose`: one of `idle`, `sword`, `slash`, `slashwind`, `thrust`, `club`, `bash`, `smash`, `smashhit`, `bow`,
  `bowdraw`, `bowrelease`, `sling`, `slingdraw`, `jab`, `cross`, `kick` (the `POSES` table: weapon, combo step, how far
  through the move, how far drawn). Unknown names fall back to `idle`.
- `view_degrees`: camera angle around the figure (default 30; 0 is straight in front).
- `no-markers`: hide the markers.

It sets `fig.instant = true` so the pose appears without spring smoothing, renders 12 frames, saves and quits.

## figure_strip.gd

Renders a filmstrip of one whole move of the 3D figure, posed tick by tick at 60 fps (springs and all), saving every
Nth frame. Needs a window.

```
<godot> --path . -s tools/figure_strip.gd -- <out_prefix> <weapon> <combo> [view] [every]
```

- `out_prefix`: file name start; frames are saved as `<out_prefix>_000.png`, `<out_prefix>_004.png`, and so on.
- `weapon`: 0 fists, 1 club, 2 sword, 3 bow, 4 sling.
- `combo`: which move of the combo (0, 1, 2); ignored for bow and sling, which draw to full, hold 20 ticks and release.
- `view`: camera angle in degrees (default 60). `every`: save every Nth tick (default 4).

Set the environment variable `STRIP_DEBUG` to anything to print the attack counter and hand positions every 3 ticks.

## pip_feet_check.gd

A visual check for Pip (`Avatar`): Pip at the origin, a camera level with the ground looking at him, and a thin red bar
along the ground line. His feet should sit exactly on the screen's middle row. Needs a window.

```
<godot> --path . -s tools/pip_feet_check.gd -- out.png
```

Renders 30 frames, saves (default `user://pip_feet.png`) and quits. It does not call `animate()`, so Pip shows the
first idle frame facing the camera.

## release.sh

Publishes a new version of the game so every player gets it automatically. A Bash script: run it in Git Bash.

```
tools/release.sh 0.3.0 "What changed, one line"
```

Step by step:

1. Finds Godot: the `GODOT` environment variable, or by default
   `/c/Users/Jacob Maddux/dev/tools/godot-export/Godot_v4.7.2-stable_win64_console.exe`. Reads its version (for example
   `4.7.2`, padded to three parts).
2. Writes the new version into `version.txt`.
3. Runs `git add -A` and commits as `Release v0.3.0: <notes>` (no error if there is nothing to commit). Note that
   this commits **everything** in the working folder, not only `version.txt`.
4. Deletes the old build, then exports with the "Windows Desktop" preset from `export_presets.cfg`:
   `export/windows/MultiplayerGame.exe` plus `MultiplayerGame.pck` (`--export-release`), and the update pack
   `export/game.pck` (`--export-pack`). Stops with "export failed" if any file is missing.
5. Zips `export/windows/*` into `export/MultiplayerGame-windows.zip` with PowerShell.
6. Runs `git push`, then `gh release create v0.3.0` with the zip and `game.pck`, titled "Multiplayer Game 0.3.0". The
   notes are your one line, short instructions for players, and a last line `godot: <version>`.

Needs: Git Bash, the GitHub CLI (`gh`) logged in with rights to the repository, PowerShell, and Godot with the
Windows export templates installed.

Running games then see the release: `scripts/updater.gd` compares the tag with the running version, checks the
`godot:` line against its own engine version, downloads `game.pck` and offers **Restart now**; `scripts/boot.gd` loads
it on the next start. If the Godot versions differ, players are sent to the download page instead.

## make_weapon_frames.py

Builds Pip's weapon animation frames from his own sprite sheet. Python 3 with **NumPy** and **Pillow**
(`pip install numpy pillow`).

```
python tools/make_weapon_frames.py
```

It reads `assets/pip/pip-spritesheet.png` and `pip-spritesheet.json`, and writes `assets/pip/pip-weapons.png` and
`pip-weapons.json` (same JSON layout as the main sheet). It prints how many rows and frames it made.

- **Sword:** every club animation (`c_swing`, `c_back`, `c_smash`, `wc_swing`, `wc_back`, `rc_swing`, `ac_swing`) is
  copied with the club recoloured (`swordify`): the club is found exactly by its colours, which appear nowhere else on
  Pip; the end at the hand becomes a leather grip and a gold guard, the rest a steel blade, and the tip runs on a few
  pixels. The new animations are named `s_swing`, `s_back`, `s_smash`, `ws_swing`, `ws_back`, `rs_swing`,
  `as_swing`.
- **Bow and slingshot:** drawn onto Pip's punch pose. His fist is found per direction (`fist`: the pixels that move out
  between the guard frame and the punch), and the weapon is drawn there in his outlined pixel style (`draw_bow`,
  `draw_sling`): three draw frames (`bowDraw`, `slingDraw`) and two release frames (`bowShot`, `slingShot`). Seen from
  behind, the weapon is drawn behind him.

Only the five drawn directions (S, SE, E, NE, N) are made; the game mirrors the other three. Run it again whenever
Pip's main sheet changes.

## netcode_model.py

A model of the game's netcode (`scripts/net.gd` and `scripts/sim.gd`) in plain Python 3, no packages. It plays two
minutes of random movement over a bad connection, with the same basic rules: 60 Hz, unreliable inputs with the last 8
repeated, the server applying inputs in order (waiting up to 8 ticks for a missing one), snapshots every 2 ticks with
an ack, float32 rounding, and client-side replay. It counts how often the client's prediction disagreed with the
server.

```
python tools/netcode_model.py
```

It prints one line per connection (30 ms ping / 5 ms jitter / 0% loss, 80 / 20 / 1%, 150 / 40 / 3%, 250 / 80 / 5%):
the number of corrections in two minutes and the biggest one in centimetres. The expected result is 0 corrections.

What it does not model: combat, collision with pillars, the server's per-player jitter buffer, and the adaptive
interpolation delay. Its catch-up rule (three inputs per tick when more than four are queued) is also different from
`net.gd` (two per tick when the queue is three past the buffer target), and its docstring says "inputs resent x4"
although the code repeats 8. It is a check that prediction and reconciliation agree, not a full copy of the netcode.
Functions: `step(s, btn, yaw)` (movement on flat ground) and `run(lat_ms, jit_ms, loss, ticks, seed)`.

## magic_test.gd

`Godot --headless --path . --script tools/magic_test.gd`: the shared simulation's magic. Every step of the wizard's tower
is reachable with one jump from the step below; the teleport reaches 18 m (five dashes), lands short when you aim at
nearer ground, lands on tops, goes up into the sky, and never ends inside a pillar; staff spells cost mana; wand spells
use recharges (golem 10 s, teleport 4 s, stun 5 s); a stun holds you 3 s; the shield stays up while held, costs its
mana once and stops mana coming back; levels at 3, 8 and 18 kills unlock spells; frost slows to half speed.

## golem_test.gd

`Godot --headless --path . --script tools/golem_test.gd`: golems catch a walking player and hit them on the move, a
sprinting player gets away, they notice enemies 24 m off but not 27 m, they leave players alone without PvP, they
crumble at 0 health and their summoner can't hurt them; one titan at a time, whose slam crushes everyone round it;
(0.8.0) one leaps at someone 4.5 m off and comes down on them, three after one target spread round it, and with
nothing to fight they stand guard round their summoner.

## net_magic_test.gd

`Godot --headless --path . --script tools/net_magic_test.gd`: the server's magic, run offline (an `OfflineMultiplayerPeer`;
it prints harmless "not inside tree" RPC errors). PvP; a held shield soaking a slash (12 mana) and a fireball (44),
then shattering and letting the rest through; kills levelling the staff and wand (sword kills don't count); the stun's
area; a meteor and its burning ground; a gravity well dragging someone in and bursting; an arcane storm's bolts; your
own blasts never hurting you; the staff being one of a kind.

## make_costumes.py

`python tools/make_costumes.py` (also run by make_garb_sheets.py): paints Pip's seven costumes over both sheets frame
by frame (`assets/pip/garb/<sheet>-<look>.png`) and their accent sheets (`-accent.png`: only the accent pixels, as
grey shades, tinted with the player's colour in the game). Each frame is read for his head, torso, legs, boots, arms
and hands, then garments are painted over those regions in 3-4 tone ramps lit from the upper left, with his dark
outline on every new edge. Looks: brawler, knight, barbarian, ranger, scout, wizard, shadow (the hooded robe).

## carry_sheet.py

`python tools/carry_sheet.py <folder>`: contact sheets of Pip carrying each weapon in all 8 directions (idle, walk,
run, dash, air), placed by the same rules as the game. For checking the carried weapons by eye.

## make_garb_sheets.py

`python tools/make_garb_sheets.py`: paints the wizard garb onto Pip's sheets frame by frame (`assets/pip/garb/`:
`<sheet>-wizard.png`, `<sheet>-shadow.png`), records where his hands are in every frame (`garb/pip-hands.json`), and
draws the weapons he carries (`assets/pip/carry/`, with `carry.json`: each sprite's grip and the staff's and wand's
orb). The robe is one solid garment from his shoulders to the floor, shaped from his torso and legs in that frame and
widening to the hem, painted over his clothes in three tones with folds beside his legs; sleeves down his arms to the
hands; the wizard's cloak as darker side panels (the whole back from behind), a rope belt and a soft pointed hat; the
dark robe's hood a rounded cowl with his face in its shadow. Run it after changing the sheets.

## rehost_test.gd

`Godot --headless --path . --script tools/rehost_test.gd`: host on UDP 7777 (7797 if another program has it), leave,
host again; a guest joins, leaves and joins again; host -> leave -> join -> leave -> host. The host and the guest live
in their own branches of the tree with their own multiplayer.

## garb_check.gd

`Godot --headless --path . --script tools/garb_check.gd`: hangs a robe (WizardGarb) from a still body for 2 s, then
runs with it at 10 m/s, printing the height of each row of the back strand: it should step evenly down to the floor.

## make_outfits.py

`python tools/make_outfits.py`: recolours Pip's two sprite sheets into outfits 1-3 (`assets/pip/outfits/`): the tunic,
trousers, scarf and hair moved to new colours (blue and gold, green and red, crimson and teal), skin and outline kept.
The host plays outfit 0 (the original); guests get 1, 2, 3 in the order they join. Outfits 4 (grey) and 5 (dark
violet-black) are the wizard garb's robes (scripts/wizard_garb.gd): Pip's sheets switch to them while he carries the
staff or the wand.

## npc_test.gd

`Godot --headless --path . --script tools/npc_test.gd` (v0.10.0, offline, prints harmless RPC errors): the Duel
Stone's pool before and after the first level-up, one challenger at a time, challengers and players hurt each other
whatever PvP says, a challenger kill levels the staff and a fallen challenger leaves, a swordsman closes in and fights,
an archer (v0.11.0: aims where you stand, with spread and a tell) hits some shots but never every one, standing or strafing, Thunderhorn's health (1.7x for two, 2.4x for three), each spell's effect on him
(lightning 1/4, meteor and earth spikes x1.5, earth spikes stop a charge, fireball burns, frost slows, stuns shorten,
gravity wells can't move him), victory, and defeat then restart alone and with two players (levels kept).

## boss_test.gd

`Godot --headless --path . --script tools/boss_test.gd` (v0.11.0, offline, prints harmless RPC errors): Static (an orb
hit adds a stack and 6 damage, the meter holds 2.5 s then drains, a shield blocks it, six stacks stun 7 s with no
moving, jumping, dashing or attacking, no stacks during it, the meter empties after; five when enraged; snapshots
carry it); homing orbs (10/15/20/24 by players, split evenly, a still player is hit by most, a sprinting, turning,
dashing one by few); the Storm Leap over six simulated fights (2-5 leaps, at least 25 s apart; no bonus leaps when
players are hurt); the landing ring hits a grounded player and misses one who jumps it; the rush (a side-dash makes
him miss; standing, you're hit for 30, thrown more than 10 m, knocked down 2.3 s, then up and moving); targeting
(with two players the one hurting him gets more attention but not all; a stunned, low-health player is left alone).


## cloth_test.gd

`<godot> --headless --path . --script tools/cloth_test.gd`: v0.12.0. Hangs the wizard's robe and cloak from a still body,
then dashes it (24 m/s for 0.15 s), snaps it 1.5 m sideways (a net correction) and dashes again, at 60 and 30 fps. Every
cloth point must stay within its rest length of the point above it, and the hem must trail the body by under 0.7 m
(without the v0.12 carry it trailed over a metre and whipped back).
