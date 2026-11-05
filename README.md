# Multiplayer Game

A 3D online multiplayer action game in **Godot 4.7** (GDScript, no C#). Several people play together in one shared world:
one of them hosts (their PC runs the game and the server at once), the others join with an invite code. Playing alone
is just hosting with nobody else.

This first stage is the foundation everything else stands on:

- a server that several people can join (or a host who plays and serves at once; solo is just hosting alone);
- an open plane in 3D with solid pillars and steps to jump on (collision is part of the shared simulation), each
  player a simple character with a name;
- movement: WASD, sprint (Shift), jump (Space), dash (Q, the first ability: predicted, with a cooldown);
- camera: third person over the shoulder or first person (V), mouse-wheel zoom, crosshair;
- tier-one melee and ranged combat (fists, club, sword, bow, slingshot), weapons and ammo to pick up, practice dummies;
- two looks for the players, picked by the host: Pip, Jacob's pixel-art sprite character
  (`scripts/avatar.gd`: walk and run cycles that follow speed, jump, dash, every weapon), or a rigged 3D figure
  (`scripts/figure_avatar.gd`);
- a small "living yard": fruit trees and oaks, fruit that grows and falls, worms that move into fallen fruit, and
  birds that come to eat the worms;
- netcode built for fast action, with no lag felt on your own moves and no rubber-banding;
- automatic updates: the game downloads new versions from GitHub by itself.

Contents:

1. [Controls](#controls)
2. [Combat](#combat)
3. [Download and play (Windows)](#download-and-play-windows)
4. [Getting started (from the source)](#getting-started-from-the-source)
5. [Playing with a friend](#playing-with-a-friend)
6. [How it fits together](#how-it-fits-together)
7. [How the netcode works](#how-the-netcode-works)
8. [Repository layout](#repository-layout)
9. [Files at the top level](#files-at-the-top-level)
10. [Running the tests](#running-the-tests)
11. [Making a release](#making-a-release)
12. [Contributing / conventions](#contributing--conventions)
13. [Roadmap (next foundations)](#roadmap-next-foundations)

## Controls

| Key | Action |
|---|---|
| Mouse | orbit the camera around you (action-RPG style, like Valheim / Dark Souls) |
| WASD, Shift, Space, Q | move relative to the camera (you turn to face the way you walk), sprint, jump, dash |
| Left mouse | attack the way you face (in place, or stepping into it if you're moving); click again for the combo; hold to draw a bow or slingshot, let go to shoot. While you hold it, your character turns toward the crosshair |
| Right mouse | aim: face where the camera looks, zoom in, finer mouse |
| E | pick up the weapon you're standing at (ammo is picked up by walking over it); next to a fallen fruit with no weapon in reach, eat it (+8 HP) |
| 1-5 / Tab | fists, club, sword, bow, slingshot (the ones you have) |
| V, mouse wheel | first / third person, camera distance |
| F2 | host only: switch everyone between Pip (sprite) and the 3D figure |
| Esc | menu: resume, mouse sensitivity, look (host), leave |

The first click after the mouse is released (for example after closing the Esc menu) only grabs the mouse again; it
does not also swing.

## Combat

Tier-one weapons, 6-10 damage a hit. Each melee weapon is a three-move combo: fists jab / cross / kick, club
bash / backhand / overhead smash (with a ground shockwave), sword slash / backslash / lunging thrust. The bow and
slingshot draw while held (longer draw: faster, harder), and use arrows and rocks you pick up; spent ones can be
picked up again. Practice dummies near the spawn show each hit, the total and damage per second. You keep what you
carry when knocked out (3 s on the ground).

Two looks, picked by the host for everyone: Pip (Jacob's sprite character, with sword, bow and slingshot frames made
from his sheet by `tools/make_weapon_frames.py`) or the rigged 3D figure (`scripts/figure_avatar.gd`: IK arms and
legs, keyframed attacks, live bow string and slingshot bands; `tools/figure_poses.gd` renders a pose sheet).

More detail, all taken from `scripts/weapons.gd` (the single source of the numbers):

| Weapon | Moves (damage) | Notes |
|---|---|---|
| Fists | jab (6), cross (6), kick (7) | always owned; the kick is the finisher |
| Club | bash (7), backhand (7), smash (9) | slow (you move at 55% speed mid-swing); the smash's shockwave hits anyone within 2.3 m of the impact for half damage |
| Sword | slash (8), backslash (8), thrust (10) | the thrust lunges forward and reaches 3.3 m |
| Bow | 6-10 by draw | full draw takes 45 ticks (0.75 s); arrows |
| Slingshot | 6-8 by draw | full draw takes 20 ticks (1/3 s); rocks |

Other rules worth knowing:

- Pressing attack again within 18 ticks (0.3 s) of a move ending chains the next move of the combo; late in a move's
  recovery you can also cancel straight into the next move.
- Weapons lie at fixed spawn points near the start and come back 20 s after someone takes them. Ammo you shoot can be
  picked up where it lands; dropped ammo disappears after 60 s, and at most 40 dropped things lie around at once.
  You carry at most 60 arrows and 60 rocks.
- Melee hits are lag-compensated: the server rewinds other players to where the attacker saw them (up to 0.5 s back),
  so a hit that looked right on your screen counts.
- Hitting a fruit tree three times knocks ripe fruit down; swings and walking into fallen fruit send it rolling.

## Download and play (Windows)

Step-by-step for hosts and guests, with Tailscale and port forwarding: [docs/how-to-host-and-join.pdf](docs/how-to-host-and-join.pdf).

1. Go to <https://github.com/juggernautjake/multiplayer-game/releases/latest> and download
   `MultiplayerGame-windows.zip`.
2. Unzip it and run `MultiplayerGame.exe`. Windows SmartScreen may warn about an unknown app: click **More info →
   Run anyway**.
3. **Play / Host** starts a game (alone, or friends join you). Its invite codes show at the top left, and the best one
   is copied to the clipboard. **Join a friend**: paste their invite code, then click Join a friend.

Once installed, the game keeps itself up to date: each time it starts it checks GitHub for a newer release, downloads
it in the background, and shows a **Restart now** button in the menu. See [Making a release](#making-a-release) for
how that works.

## Getting started (from the source)

1. Download **Godot 4.7** (standard, not .NET) from <https://godotengine.org/download>. It's a single program, so no
   install is needed: unzip it anywhere.
2. Open Godot, choose **Import**, and pick `project.godot` from this repository (Code → Download ZIP, or `git clone`).
3. Press **F5** (Play). In the menu:
   - **Play / Host** starts a game on your PC that friends can join. The screen shows the invite codes to give them.
   - **Join a friend**: paste the host's invite code (or type an address), then Join.

To test two players on one PC, go to **Debug → Customize Run Instances**, set 2 instances, and press F5. Host in one
window and join `127.0.0.1` in the other.

When you run from the editor the updater does not download anything (the menu says "running from the editor:
updates come from git").

## Playing with a friend

The host's PC listens on **UDP port 7777**. An invite code (like `34CP1-P07KE`) is the host's address and port
packed into ten letters and digits; the host's screen lists one per way of reaching it:

| Where your friend is | Which invite code |
|---|---|
| Same Wi-Fi / LAN | "same Wi-Fi" |
| Over the internet, no router changes (easiest) | both of you install [Tailscale](https://tailscale.com) (free) and the host shares their PC with the friend; use the "Tailscale" code |
| Over the internet | "over the internet", after forwarding **UDP 7777** on the host's router to the host's PC |

How the codes are made (see `invite_code` and `decode_invite` in `scripts/main.gd`): the four numbers of an IPv4
address and the port are packed into 48 bits and written in Crockford base 32 (no I, L, O or U, so a code reads
aloud cleanly), as two groups of five. When decoding, capitals, spaces and the dash don't matter, and O, I and L
typed by mistake are read as 0, 1 and 1. A "Tailscale" code is any local address starting `100.`; the "over the
internet" code uses the public address that the game looks up from `https://api.ipify.org`. The Tailscale code (or
else the first Wi-Fi code) is copied to the clipboard.

The first time you host, Windows Firewall asks whether Godot (or the exported game) may use the network. Allow it on
private networks, or friends can't connect. (The PDF guide recommends ticking both Private and Public.)

Host and guests must run the **same version** of the game. When a guest joins with a different version, the host
turns them away with a message that says who needs to restart to update.

Later, a Steam build can use Steam's relay network ([GodotSteam](https://godotsteam.com)). Friends then join through
the Steam friends list, with no addresses and no port forwarding.

### Dedicated server

To run a server with no window and no player of its own (for an always-on server):

```
Godot_v4.7.2-stable_win64_console.exe --headless --path dev/multiplayer-game -- --server --port 7777
```

Other options after `--`: `--host`, or `--join <address>`, to skip the menu. The full list is in
[Running the tests](#running-the-tests) and in [scripts/README.md](scripts/README.md#maingd).

## How it fits together

This section follows the game from the moment it starts. Every script is described in more detail in
[scripts/README.md](scripts/README.md).

**1. Boot.** `project.godot` names `boot.tscn` as the main scene. That scene holds one node running
`scripts/boot.gd`. In an exported game, boot.gd looks for a downloaded update (`updates/game.pck` and
`updates/version.txt` beside the exe, or in the per-user data folder). If that update is newer than the version built
into the exe, it loads the pack over the built-in files with `ProjectSettings.load_resource_pack`. Only then does it
switch to `main.tscn`. Because boot.gd uses no other script before the pack is loaded, every script, scene and asset
afterwards comes from the newest version.

**2. Main.** `main.tscn` is one `Node3D` running `scripts/main.gd`, the game shell. It reads the command line,
builds the world (sky, sun, the ground plane with its grid shader, the pillars from `WorldLayout`, the yard
(`EcoView`) and the practice dummies), the camera, the menu, the HUD and the Esc menu. It creates the `Net` node and
gives it a function to call for the local player's input each tick. It listens to Net's signals to create and remove
avatars, draw projectiles, items, hits and effects. Every frame it places each avatar where Net says to draw it and
calls the avatar's `animate()`.

**3. Net (`scripts/net.gd`).** One node on every peer that holds the server side, the client side, or both (a host is
a server that also plays). The server runs the authoritative simulation at a fixed 60 Hz, applies each player's
inputs in order, decides every hit and pick-up, and sends snapshots. The client predicts its own player immediately,
reconciles with each snapshot, and draws other players slightly in the past, interpolating between snapshots. Details
are in [How the netcode works](#how-the-netcode-works).

**4. Sim (`scripts/sim.gd`).** The shared, deterministic movement and combat step: `Sim.step(state, input)`. The
server runs it to decide what happens; the client runs exactly the same function to predict its own player. It uses
no randomness and no clock, only fixed steps of 1/60 s, and rounds every float to 32 bits so that both sides get
bit-identical results. It reads the static world from `WorldLayout` (pillars, steps, tree trunks, dummies) and the
weapon timings from `Weapons`. It reports events (`MELEE_HIT`, `SHOT`) that only the server acts on.

**5. Codec (`scripts/codec.gd`).** Packs the two messages sent all the time (inputs from a client, snapshots from the
server) into compact binary with `StreamPeerBuffer`. Everything else (roster, items, hits, projectiles, yard events)
goes as ordinary reliable Godot RPCs, because it happens rarely.

**6. Ecology and EcoView (the living yard).** `scripts/ecology.gd` runs on the server only. It grows fruit on the two
fruit trees, drops it, works out each fruit's whole flight and roll in advance, sends worms into fruit that has lain
on the ground for a while, and sends birds after the worms. Everything it does goes out as timed events (`Net.eco`
signal, `Net.eco_event` RPC), each stamped with the server tick it starts at. `scripts/eco_view.gd` on every client
draws those events on the same delayed clock that other players are drawn on (`Net.render_tick`), so a bird lands
and pecks at the same moment for everyone.

**7. Avatars.** Two classes with the same interface (`yaw`, `grounded`, `dashing`, `state`, `model`, `flash()`,
`hitstop()`, `animate(delta, camera)`): `Avatar` (Pip the sprite, `scripts/avatar.gd`) and `FigureAvatar` (the 3D
figure, `scripts/figure_avatar.gd`). Both animate purely from the `Sim.PlayerState` that the client already has, so
animation adds no network traffic. The host picks the look for everyone (`Net.style`, changed with F2); when it
changes, Main rebuilds every avatar.

**8. Combat visuals.** `scripts/fx.gd` (slash trails, thrust streaks, shockwaves, particle bursts, impact words),
`scripts/dummy.gd` (the practice dummies), `scripts/weapon_models.gd` (3D models of weapons and ammo built from simple
meshes, used for items on the ground and in the 3D figure's hands).

**9. Updater (`scripts/updater.gd`).** Created by Main's menu. It asks the GitHub API for the latest release. If that
is newer than the running version and was built with the same Godot version, it downloads `game.pck` into the updates
folder, writes `version.txt` beside it, and offers **Restart now**. boot.gd loads it on the next start. If the
release was built with a different Godot version, a pack can't be patched in, so it shows a **Download page** button
instead.

**10. Release flow.** `tools/release.sh` writes the new version into `version.txt`, commits, exports the Windows game
and the update pack, and publishes both as a GitHub release. See [Making a release](#making-a-release).

## How the netcode works

| Piece | What it does | Why |
|---|---|---|
| Server-authoritative, fixed 60 Hz | Only the server's simulation counts | Cheating is hard; everyone agrees |
| Shared deterministic `Sim.step` | The same movement code runs on server and client, every value rounded to float32 | Predictions match the server exactly |
| Client-side prediction | Your player moves the instant you press a key | No input lag, whatever your ping |
| Reconciliation | Each snapshot says which of your inputs the server has applied; the client replays the rest from the server's state, and blends out any real correction | No rubber-banding |
| Interpolation | Other players are drawn about 100 ms behind, blended between snapshots; brief extrapolation (up to 250 ms) covers a lost packet. The delay adapts to how unevenly snapshots really arrive (between 3 and 20 ticks) | Smooth motion, even with jitter |
| UDP (ENet), unreliable inputs and snapshots | Each input packet repeats the last 8 inputs; the server puts late or reordered inputs back in sequence | A lost packet costs nothing; no head-of-line stalls like TCP |
| Compact binary packets | 25 bytes per input (so about 200 bytes per input packet, with the 8 repeats), 47 bytes per player per snapshot plus a 10-byte header; snapshots go out 30 times a second | Low bandwidth: 32 players fit easily |
| Input jitter buffer and backlog limit | The server holds a couple of inputs per player before applying them, then applies one per tick (two when catching up after a hiccup); at most 30 waiting inputs are kept | Smooth motion for everyone; sending inputs faster can't make you move faster |
| Lag-compensated melee | The server keeps 1.5 s of position history per player and tests melee hits against where the attacker saw the others | What looked like a hit is a hit |
| Projectiles on a fixed path | A shot's whole flight follows from its launch (closed-form gravity), so only the launch and the landing are sent | No per-tick projectile traffic |

Files:

- `scripts/config.gd`: shared numbers (tick rate, snapshot rate, interpolation delay, port).
- `scripts/sim.gd`: the deterministic movement simulation: `PlayerInput`, `PlayerState`, `step()`.
- `scripts/codec.gd`: binary packing of inputs and snapshots.
- `scripts/net.gd`: server, client and host logic: prediction, reconciliation, interpolation.
- `scripts/main.gd`: the world, avatars, camera, controls, menu and HUD.

## Repository layout

```
multiplayer-game/
├── README.md             this guide
├── project.godot         Godot project settings (main scene = boot.tscn)
├── export_presets.cfg    the "Windows Desktop" export preset used by tools/release.sh
├── version.txt           the game's version number (written by tools/release.sh)
├── boot.tscn             first scene: loads a downloaded update, then opens main.tscn
├── main.tscn             the game scene: one Node3D running scripts/main.gd
├── .gitignore            keeps Godot's cache and the export folder out of git
├── scripts/              every game script            → scripts/README.md
├── tools/                tests, preview renderers, the release script, asset and netcode tools → tools/README.md
├── assets/               art: Pip's sprite sheets      → assets/README.md
│   └── pip/              the sheets and their frame data → assets/pip/README.md
├── docs/                 the host-and-join guide (PDF) → docs/README.md
├── export/               (not in git) build output of tools/release.sh
└── .godot/               (not in git) Godot's import cache, rebuilt automatically
```

## Files at the top level

| File | What it is |
|---|---|
| `README.md` | This guide. |
| `project.godot` | Godot's project file. Sets the name ("Multiplayer Game"), the main scene (`res://boot.tscn`), the feature set (Godot 4.7, Forward Plus renderer), a 1280 x 720 window, `physics_jitter_fix = 0` (the game does its own fixed-tick timing) and 2x MSAA. Open this file in Godot to open the project. The physics tick rate is left at Godot's default of 60, which matches `Config.TICK_RATE`. |
| `export_presets.cfg` | One export preset, **Windows Desktop** (x86_64), writing `export/windows/MultiplayerGame.exe` with a separate `.pck` (not embedded), with a console wrapper. It includes `version.txt` in the export and excludes the `tools/` folder. `tools/release.sh` exports with this preset. |
| `version.txt` | The current version number, one line (for example `0.2.2`). It is packed into the game and read at runtime by `boot.gd` and `Updater.running_version()`; host and guests must match it exactly to play together. `tools/release.sh` rewrites it; don't change it by hand unless you are releasing. |
| `boot.tscn` | The first scene Godot opens: a single `Node` named Boot with `scripts/boot.gd`. |
| `main.tscn` | The game scene: a single `Node3D` named Main with `scripts/main.gd`. Everything else (world, UI, network) is built in code at startup, so this scene stays tiny. |
| `.gitignore` | Ignores `.godot/` (Godot's import cache), `export/` (build output), `*.translation` files, and the OS files `Thumbs.db` and `.DS_Store`. |
| `export/` | Not in git. Created by `tools/release.sh`: `windows/MultiplayerGame.exe` + `windows/MultiplayerGame.pck` (the full game), `MultiplayerGame-windows.zip` (those two zipped, for new players) and `game.pck` (the update pack that running games download). |
| `.godot/` | Not in git. Godot's editor cache (imported textures, class lists, script UIDs). Safe to delete; Godot rebuilds it when the project is opened. |

## Running the tests

All the tests run Godot from the command line. Below, `<godot>` means your Godot 4.7 console executable, for example
`Godot_v4.7.2-stable_win64_console.exe`. Run them from the repository folder. More detail about each tool is in
[tools/README.md](tools/README.md).

### Headless unit tests

These need no window and exit with code 0 when everything passes.

| Command | What it checks |
|---|---|
| `<godot> --headless --path . -s tools/sim_test.gd` | The shared simulation: walking into a step stops beside it, a jump lands on top, walking off falls back down, a dash can't push through a pillar, identical inputs give identical results, melee combos with no keys held stay in place while swinging on the move steps forward, walking turns the body, aiming faces the camera. |
| `<godot> --headless --path . -s tools/fruit_test.gd` | Fruit physics in `Ecology`: fallen fruit comes to rest, walking into it kicks it, a melee blow sends it flying, it never ends up inside a pillar, trunk or dummy, and its path has no jumps. |
| `<godot> --headless --path . -s tools/eco_test.gd` | Runs the yard for 20 simulated minutes and checks that fruit falls, worms move in, birds come and trees can be hit. Prints `ECO OK` or `ECO FAIL`. |
| `<godot> --headless --path . -s tools/invite_test.gd` | Invite codes: encoding then decoding gives back the address and port. |

### Visual checks (need a window)

These render a picture and quit. Leave out `--headless`.

| Command | What it makes |
|---|---|
| `<godot> --path . -s tools/figure_poses.gd -- out.png <pose> [view_degrees] [no-markers]` | A close-up of the 3D figure in one pose, with markers for the hands and the weapon grip. |
| `<godot> --path . -s tools/figure_strip.gd -- <out_prefix> <weapon> <combo> [view] [every]` | A filmstrip of one move, every Nth frame saved as a PNG. |
| `<godot> --path . -s tools/pip_feet_check.gd -- out.png` | Pip at the origin with a camera at ground level, to check that his feet sit on the ground line. |

### Live tests with scripted players (bots)

For a live test with scripted players: start a server (`-- --server --port 7789`), then run clients with
`-- --join 127.0.0.1 --port 7789 --bot`; each prints its position, the players it sees, its ping and its prediction
corrections every 2 s. Add `--screenshot shot.png` (and `--view first`) to save a frame.

```
<godot> --headless --path . -- --server --port 7789
<godot> --path . -- --join 127.0.0.1 --port 7789 --bot --name Bot1
```

The bot modes (all in `scripts/main.gd`, functions `_bot_input`, `_bot_fight` and `_bot_close`):

| Option | What the bot does |
|---|---|
| `--bot` | The default test player: walks forward while slowly turning in a circle, sprints every other 2 s, jumps every 1.5 s, dashes every 2.5 s, and prints a status line every 2 s (tick, position, players seen, ping, corrections, how far behind others are drawn, how often they had to be guessed). |
| `--bot fight` | Walks to every weapon and ammo spawn and picks everything up, then walks to the middle practice dummy and uses each weapon on it for 6 s in turn (melee from 1.6 m, bow and slingshot from 10 m, aimed with the low-arc launch angle). Every 10 s it prints an audit line if `--log` is on. If it is the host, at 25 s it switches the look for everyone, to test F2. |
| `--bot aim` | Like fight, but only with the bow and slingshot, aiming like a person: it steers the camera so the crosshair sits on the dummy's chest, then draws and lets go. Alternates 10 m and 22 m every 12 s. Tests that shots land where the crosshair is. |
| `--bot close` | Close-quarters test. After picking everything up, for each weapon it walks right into the middle dummy and then into the nearest tall pillar (7 s each), keeps the crosshair on the target, and attacks (clicks, then holds; bows draw and release). Every 6 ticks it logs how far the body is turned from the target and from the camera; at the end it prints the worst angle per weapon and quits. Add `--shots <folder>` to save screenshots at three moments of each phase. |

Other command-line options (after `--`):

| Option | Meaning |
|---|---|
| `--server [--port 7777]` | Dedicated server: no window, no player of its own. Prints its version and invite codes. |
| `--host` / `--join <address or invite code>` | Skip the menu and host or join at once. |
| `--port <n>` | UDP port (default 7777). |
| `--name <name>` | Your player name. |
| `--style pip` or `--style figure` | (host or server) the look for everyone. |
| `--screenshot <file.png> [--shot-frame 240] [--view first]` | Save one frame (frame 240 by default) and quit. `--view first` starts in first person. |
| `--log` | Print every hit and pick-up on the server, and (with `--bot fight`) an audit line counting every replicated event this client received. |
| `--netsim ping_ms,jitter_ms,loss_percent` | Test this client over a simulated bad connection: delays, jitters and drops its own inputs and incoming snapshots. Example: `--netsim 150,40,3`. |

### Checking the netcode

`tools/netcode_model.py` (plain Python 3, no packages) models the same rules as `net.gd` over bad connections and
counts how often a client's prediction had to be corrected. Current result: **0 corrections** in two minutes of
play at 30, 80, 150 and 250 ms ping, with up to 80 ms jitter and 5% packet loss. Run it after any netcode change:

```
python tools/netcode_model.py
```

The model covers movement only (no combat, no jitter buffer); see [tools/README.md](tools/README.md#netcode_modelpy).

## Making a release

Releases are made with one command, run from Git Bash on the developer's PC:

```
tools/release.sh 0.3.0 "What changed, one line"
```

What it does, step by step:

1. Writes the version (`0.3.0`) into `version.txt`.
2. Stages **everything** in the working folder (`git add -A`) and commits it as `Release v0.3.0: <notes>`.
3. Exports the full Windows game (`export/windows/MultiplayerGame.exe` and `MultiplayerGame.pck`) with the
   "Windows Desktop" preset, and the update pack `export/game.pck` (every script, scene and asset).
4. Zips the Windows folder into `export/MultiplayerGame-windows.zip` (with PowerShell's `Compress-Archive`).
5. Pushes to GitHub and creates the release `v0.3.0` with the zip and `game.pck` attached, using the GitHub CLI
   (`gh`). The release notes end with a line `godot: <version>`, for example `godot: 4.7.2`.

Requirements: Git Bash, the GitHub CLI logged in, PowerShell, and Godot with the Windows export templates. The script
uses the Godot at `GODOT` if that environment variable is set, otherwise the path written in the script.

How players get it (the auto-update flow):

1. A player starts the game. `Updater` asks `https://api.github.com/repos/juggernautjake/multiplayer-game/releases/latest`.
2. If the release's tag is newer than the running version, it looks for the `game.pck` asset and reads the
   `godot: x.y.z` line from the release notes.
3. If the Godot version matches the player's, it downloads `game.pck` to `updates/game.pck.part` (beside the exe, or
   in the per-user data folder if that folder can't be written), renames it to `game.pck` and writes the new version
   to `updates/version.txt`. The menu shows **Restart now**, which starts the game again.
4. On the next start, `boot.gd` sees the newer version in `updates/`, loads the pack over the built-in files and runs
   the new game.
5. If the Godot versions differ (or there is no `game.pck`), the menu says the new version needs a full download and
   shows a **Download page** button.

Version checks when joining: a guest sends its running version with its first message (`Net.hello`). If it is not
exactly the host's version, the host sends `turned_away` and disconnects the guest a second later. The guest's menu
then says "The host is on vX and you're on vY" and tells whoever is older to restart to update.

## Contributing / conventions

- **Engine.** Godot 4.7, standard build (GDScript). Use typed GDScript (`var x := 1`, typed arguments and returns).
- **Everything in code.** Scenes are tiny; nodes, meshes, materials and UI are built in code. There are no `.tres`
  resources yet. Global classes are declared with `class_name` and used by name (`Sim`, `Net`, `Weapons`, ...).
- **Determinism.** Anything that affects a player's state must go through `Sim.step` and stay deterministic: no
  `randf()`, no wall-clock time, only tick counts and `Config.DT`, and every float rounded with `Sim.quantize`. If you
  add a field to `Sim.PlayerState` that the client needs, add it to `PlayerState.copy()` and to both
  `Codec.encode_snapshot` and `Codec.decode_snapshot`.
- **Server decides.** Hits, pick-ups, damage and the yard are decided on the server only. Clients draw what they are
  told. Rare events go as reliable RPCs on `Net`; a new one should also be emitted locally when `is_host_player` is
  true, because the host does not receive its own RPCs.
- **Shared data in one place.** World layout in `WorldLayout`, weapon numbers in `Weapons`, network constants in
  `Config`. Change them there, not in copies.
- **Comments.** Every script starts with a `##` header saying what it is for; functions that matter have a `##` line
  above them. Write comments in plain full sentences, like the existing ones.
- **Tests.** Run `sim_test.gd`, `fruit_test.gd`, `eco_test.gd` and `invite_test.gd` after changes, and
  `python tools/netcode_model.py` after netcode changes. A quick live check is a server plus two `--bot` clients.
- **Versions.** Don't edit `version.txt` by hand; `tools/release.sh` does it. Remember that a release commits
  everything in the working folder.
- **Metadata files.** Commit the `.uid` files next to scripts and the `.import` files next to images; Godot uses them
  to keep references stable.

## Roadmap (next foundations)

1. **Collision and physics**: Godot 4.4+ ships Jolt physics. Move the player through a kinematic character controller,
   still stepped in the fixed tick so prediction holds. Physics props stay server-simulated and interpolated.
   (Today the simulation has its own simple collision against boxes and dummies, in `Sim`.)
2. **Abilities and spells**: a data-driven ability system (resources describing cost, cooldown, cast time, effects).
   Casting is predicted on the client (animation and effects start at once) and confirmed by the server. Projectiles
   are simulated by the server and spawned predictively on the caster's client. (The dash, and the bow and slingshot
   shots, already work this way.)
3. **Hit detection with lag compensation**: the server rewinds other players to what the shooter saw (keeps a short
   history of states) before testing hits, so aiming feels fair at any ping. (Done for melee; projectiles are not
   rewound yet.)
4. **Stats, armour sets, items, skills**: server-owned character data, replicated on change (reliable), not every tick.
5. **Interest management**: only send each client what's near them, for big worlds.
6. **Steam**: GodotSteam for lobbies, friends invites, relay networking, achievements, and the Steam build.
7. **Art pipeline**: characters, animation (synced by state, not by bone), environment assets.
