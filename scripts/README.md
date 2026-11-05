# scripts/

Every GDScript file that makes up the game. Most of them declare a global class with `class_name`, so other scripts
use them by name (for example `Sim.step(...)` or `Weapons.get_data(...)`) without loading them.

The `.gd.uid` file next to each script is Godot metadata: it holds the script's unique ID (`uid://...`) so that
references to the script survive renames. Godot writes them; commit them, but never edit them.

Back to the [project README](../README.md).

## At a glance

| File | Class | Runs on | In one line |
|---|---|---|---|
| [boot.gd](#bootgd) | (none) | everyone | First scene: loads a downloaded update, then opens the game scene. |
| [main.gd](#maingd) | (none) | everyone | The game shell: menu, world, camera, controls, HUD, bots, invite codes, combat visuals. |
| [net.gd](#netgd) | `Net` | everyone | Networking: server, client and host; prediction, reconciliation, interpolation; combat and items on the server. |
| [sim.gd](#simgd) | `Sim` | everyone | The deterministic movement and combat step shared by server and client. |
| [codec.gd](#codecgd) | `Codec` | everyone | Binary packing of inputs and snapshots. |
| [config.gd](#configgd) | `Config` | everyone | Numbers every peer must agree on (tick rate, port, limits). |
| [weapons.gd](#weaponsgd) | `Weapons` | everyone | Weapon data (combos, timings, damage), projectile maths, item kinds. |
| [world_layout.gd](#world_layoutgd) | `WorldLayout` | everyone | The static world: pillars, steps, trees, dummies, item spawns; ray and height queries. |
| [ecology.gd](#ecologygd) | `Ecology` | server | The living yard's rules: fruit, worms, birds; sends timed events. |
| [eco_view.gd](#eco_viewgd) | `EcoView` | client | Draws the yard from Ecology's events. |
| [avatar.gd](#avatargd) | `Avatar` | client | A player drawn as Pip, the pixel-art sprite. |
| [figure_avatar.gd](#figure_avatargd) | `FigureAvatar` | client | A player drawn as the rigged 3D figure. |
| [weapon_models.gd](#weapon_modelsgd) | `WeaponModels` | client | 3D models of weapons and ammo built from simple meshes. |
| [fx.gd](#fxgd) | `Fx` | client | Combat effects: slash trails, thrusts, shockwaves, bursts, impact words. |
| [dummy.gd](#dummygd) | `Dummy` | client | A practice dummy that rocks when hit and shows damage and DPS. |
| [updater.gd](#updatergd) | `Updater` | client | Checks GitHub for a newer release and downloads the update pack. |

"Runs on: client" means it only draws things; on a host (which is server and client at once) it runs too. A dedicated
server (`--server`) never builds the world, so none of the drawing scripts run there.

---

## boot.gd

**The first scene's script** (attached to the Boot node in `boot.tscn`, which `project.godot` names as the main scene).

Its job is to load a downloaded update before anything else runs, and then hand over to `main.tscn`.

- Only in an exported game (`OS.has_feature("template")`): it looks for `updates/game.pck` beside the executable,
  and if it isn't there, in `user://updates` (the per-user data folder).
- It compares `res://version.txt` (the built-in version) with `updates/version.txt` (the downloaded one) using
  `_newer(a, b)`, which compares dotted version numbers part by part.
- If the download is newer, it calls `ProjectSettings.load_resource_pack(..., true)` so the pack's files replace the
  built-in ones, and prints "Running update vX (built in: vY)". If loading fails it warns and runs the built-in
  version.
- Finally it changes scene to `res://main.tscn` (deferred).

It deliberately uses no other script (not even `Updater`) before the pack is loaded, so every script used afterwards,
including the updater, comes from the newest version. `Updater` repeats the same version-folder logic in
`update_dir()` and `running_version()`.

## main.gd

**The game shell**, attached to the Main node in `main.tscn`. It is the biggest script (about 1,260 lines) and
owns everything the player sees and touches. Networking and simulation are not here: they live in `Net` and `Sim`.

### Startup (`_ready`)

1. Creates the `Net` node (named `Net`, so it sits at `/root/Main/Net`), sets `net.input_source = _sample_input`,
   and connects to Net's signals: `roster_changed`, `status`, `projectile_spawned`, `projectile_ended`, `hit`,
   `local_shot`, `item_added`, `item_removed`, `style_changed` (and, with `--log`, counts every event for the audit).
2. Reads the command line (`_args()` turns `--key value` / `--flag` pairs after `--` into a dictionary).
3. With `--server`: starts a dedicated server (`net.host(port, "", false)`), sets the look from `--style`, prints the
   version and the invite codes, and stops there: no world, no UI.
4. Otherwise builds the world (`_build_world`) and the UI (`_build_ui`), applies `--name`, `--style`, `--netsim`,
   `--port`, and with `--host` or `--join` starts at once.

### Command-line options (after `--`)

| Option | Meaning |
|---|---|
| `--server [--port 7777]` | Dedicated server with no window and no player. |
| `--host` / `--join <address or invite code>` | Skip the menu. |
| `--port <n>`, `--name <name>` | UDP port and player name. |
| `--style pip` / `--style figure` | The host's look for everyone. |
| `--bot`, `--bot fight`, `--bot aim`, `--bot close`, `--bot magic`, `--bot show`, `--bot golems` (`--shots <dir>`) | Scripted test players (see below). |
| `--give-all`, `--give-staff`, `--give-wand`, `--give-guests`, `--max-level` | Test loadouts (Net reads them when hosting). |
| `--screenshot <file.png> [--shot-frame 240] [--view first]` | Save one frame and quit. |
| `--log` | Count every replicated event and print an audit line (with the fight bot); Net also prints hits and pick-ups. |
| `--netsim ping,jitter,loss%` | Simulate a bad connection on this client (sets `net.sim_lat_ms`, `sim_jit_ms`, `sim_loss`). |

The header comment of main.gd lists the older options only; `aim`, `close`, `--shots`, `--log` and `--netsim` are
found in the code.

### The world (`_build_world`)

A procedural sky with fog, a sun with shadows, a 400 x 400 m ground plane with a small grid shader (2 m and 10 m
lines, so motion reads clearly), one box mesh per `WorldLayout.boxes()` entry (pillars, steps and tree trunks, tinted
with a fixed seed), an `EcoView` node for the yard (`eco.setup(net)`), one `Dummy` per `WorldLayout.DUMMIES`
position, and the camera.

### Avatars

`_make_avatar(id, info)` creates an `Avatar` (Pip) or a `FigureAvatar` depending on `net.style`; names are shown for
everyone except yourself. `_on_roster` adds and removes avatars as players come and go; `_on_style` rebuilds them all
when the host switches the look.

### Every frame (`_process`)

- For your own player: position from `net.own_draw_position(frac)`, state from `net.predicted`; the body is hidden in
  first person.
- For other players: `net.remote_draw(id, frac)` gives position, yaw, grounded, dashing and state.
- Calls `animate(delta, cam)` on each avatar.
- Moves the camera: first person at eye height (1.82 m), or third person orbiting a smoothed focus point with an
  over-the-shoulder offset that widens while aiming or drawing; it is pulled in when a pillar is in the way
  (`WorldLayout.ray_hit`). Right mouse zooms (FOV 70 to 46).
- Updates projectiles, items, camera shake and the HUD (role, players, ping, fps, view, dash cooldown, corrections,
  interpolation delay, how often others were guessed, and the host's invite codes).
- Saves the `--screenshot` frame and quits when asked.

### Controls

- `_sample_input()` is called by Net once per tick. It returns `[buttons, cam_yaw, aim_pitch, weapon_slot, aim_yaw,
  face_yaw]`, where `buttons` is a bit mask of `Sim.Btn` values. Keys only count while the mouse is captured.
- `_update_aim()` casts the camera's centre ray against the ground, pillars, dummies and other players
  (`_ray_people`) to find what the crosshair is on. From that it works out `aim_yaw` (where a shot should fly from the
  muzzle), `face_yaw` (where the body should turn: toward the target's centre, at most 60 degrees off the camera) and,
  for ranged weapons, the pitch of the low arc that lands on the point at the current draw speed.
- `_unhandled_input` handles mouse look, Tab and 1-5 (weapon slots you own), F2 (switch look), V (view), the mouse
  wheel (distance 2.5 to 14 m), the click that recaptures the mouse, and Esc.
- `_set_paused` shows the Esc menu. The game keeps running underneath, since it's online.
- `_switch_character` / `_pause_pick_style`: the host changes the look with `net.host_set_style`; anyone else sees
  "the host picks the look".

### Menu, HUD and joining

- `_build_ui` makes the HUD labels, the health bar, the bow/slingshot draw bar, the crosshair, the Esc menu
  (`_build_pause_menu`: resume, mouse sensitivity, look, leave) and the start menu (name, invite code or address,
  port, look, **Play / Host**, **Join a friend**, status line, version and update button).
- It creates an `Updater` (not for bots) and shows its messages through `_on_update`; the button reads
  **Restart now** (calls `Updater.restart()`) or **Download page** (opens the release page).
- `_start_host` hosts with the chosen look and shows the invite codes. `_start_join` decodes an invite code if the
  text is one, starts the connection and waits up to 6 s (`_process_joining`) for the host to answer, then gives up
  with a clear message.
- `_on_status` shows Net's status messages and returns to the menu if the connection drops or the host turned you
  away for a different version (then it re-runs the update check).

### Invite codes

- `invite_code(ip, port)` (static) packs an IPv4 address and port into 48 bits and writes them as ten Crockford
  base-32 characters, `XXXXX-XXXXX`.
- `decode_invite(text)` (static) turns a code back into `[address, port]`, or `[]` if the text isn't a code. It
  ignores case, spaces and dashes and reads O, I and L as 0, 1, 1.
- `_print_addresses(port)` lists one code per local IPv4 address ("Tailscale" for `100.x` addresses, otherwise "same
  Wi-Fi"), copies the best one to the clipboard, and `_fetch_public_ip` adds the "over the internet" code after asking
  `https://api.ipify.org`.

`tools/invite_test.gd` loads main.gd to test these two static functions.

### Combat visuals

- `_on_local_shot` draws your own arrow or stone the instant you release; `_on_proj_spawn` links it to the server's
  copy when that arrives, or creates other players' shots. `_update_projectiles` moves every shot along
  `Weapons.proj_pos` (others' on `net.render_tick`, yours on your own clock), sticks landed arrows for 3 s, and
  removes the rest.
- `_on_hit` rocks the dummy or flashes the player, shows a particle burst, "Shing!" / "Thock!" / "WHAM!", freezes
  attacker and victim for a few frames (hit-stop), shakes your camera when your hit lands, and floats a damage number.
- `_update_combat_hud` shows the weapons you own (with ammo counts), selects a newly picked-up weapon, sets the health
  and draw bars, and shows the knocked-out countdown.

### Items

`_on_item_added` places a `WeaponModels` model (weapons lie on the ground with a glowing ring), `_on_item_removed`
removes it and shows "+ Sword" if you took it, and `_update_items` makes weapons bob and turn and shows
"E  pick up ..." over the nearest one within 2.2 m.

### Test bots

`_bot_input()` replaces the keyboard when `--bot` is given:

- default: walks in a slow circle, sprints, jumps and dashes on a timetable, and prints a status line every 2 s;
- `fight` (`_bot_fight`): picks up every weapon and ammo, then uses each weapon on the middle dummy for 6 s; as host it
  switches the look at 25 s; with `--log` it prints an audit line every 10 s (`_audit_print`);
- `aim` (`_bot_fight` too): bow and slingshot only, steering the camera so the crosshair is on the dummy's chest, at
  10 m and 22 m;
- `show` (`_bot_show`): runs toward the camera, strafes, backpedals, dashes, jumps, swings the sword and casts while
  the camera circles; `--shots <dir>` saves a picture every 6 ticks (animation, garb and effects by eye);
- `golems` (`_bot_golems`): summons a golem at the dummies, then the titan, and watches from the side;
- `close` (`_bot_close`): walks into the dummy and into a pillar with every weapon, logs how far the body is turned
  from the target and the camera, prints the worst angles and quits; `--shots <dir>` saves screenshots.

## net.gd

**`class_name Net`, extends `Node`.** All networking. One instance lives on every peer at `/root/Main/Net`. It holds
the server side, the client side, or both: a host is a server that also plays (`is_host_player`), a dedicated server
has no player (`dedicated`). Uses Godot's `ENetMultiplayerPeer` (UDP).

### Signals (what Main listens to)

| Signal | When |
|---|---|
| `roster_changed(players)` | The player list changed (`id -> {name, color, character}`). |
| `status(text)` | A message for the menu ("Connecting...", "Disconnected...", "The host is on vX..."). |
| `projectile_spawned(id, owner, kind, tick0, pos0, vel0, g)` | The server launched an arrow (kind 0) or stone (kind 1). |
| `projectile_ended(id, tick, pos, stuck)` | A projectile hit something or landed. |
| `hit(target, amount, pos, dir, killed, attacker)` | Something was hit. Negative targets are dummies (-1, -2, -3). |
| `local_shot(kind, pos0, vel0, g)` | Your own shot, predicted, so it can be drawn at once. |
| `item_added(id, kind, pos, count)` / `item_removed(id, taker)` | Something to pick up appeared or was taken. |
| `style_changed(style)` | The host switched the look ("pip" or "figure"). |
| `eco(kind, args)` | A yard event from `Ecology`, for `EcoView`. |

### Starting and stopping

- `host(port, player_name, with_player := true)` creates the ENet server (up to `Config.MAX_PLAYERS`), turns off
  compression, places every item spawn, creates the `Ecology`, and with a player adds the host as player 1.
- `join(address, port, player_name)` creates the client; once connected (`_on_connected`) it sends `hello` with the
  name and its running version.
- `_reset()` closes everything and clears the state (used on failure, disconnect and give-up).

### RPCs

| RPC | Direction | Reliable? | Purpose |
|---|---|---|---|
| `hello(name, character, version)` | client to server | yes | Ask to join. The server turns away a different version (`turned_away`), else adds the player and sends `welcome`, the look, the full yard state and every item. |
| `turned_away(host_version, my_version)` | server to client | yes | Wrong version: explain who should update, then reset. |
| `welcome(tick)` | server to client | yes | The current server tick, to start the client's clocks. |
| `roster_update(list)` | server to all | yes | The player list. |
| `set_style(s)` | server to all | yes | The look for everyone. Use `host_set_style(s)` to change it. |
| `items_full`, `item_add`, `item_remove` | server to all | yes | Items on the ground. |
| `proj_spawn`, `proj_end` | server to all | yes | Projectiles. |
| `hit_fx(...)` | server to all | yes | A hit, for effects and numbers. |
| `eco_event(kind, args)` | server to all | yes (channel 3) | Yard events, in order. |
| `inputs(data)` | client to server | no (channel 1) | Packed inputs (`Codec.encode_inputs`), last 8 repeated. |
| `snapshot(data)` | server to client | no (channel 2) | Packed snapshot (`Codec.encode_snapshot`). |

The host does not receive its own RPCs, so every server-to-all RPC is also called locally when `is_host_player` is
true.

### The fixed tick (`_physics_process`, 60 Hz)

Runs the client tick (if this peer has a player), then the server tick (if it is the server), then advances
`render_tick`, the clock other players are drawn at, nudging it gently to stay `interp_delay` ticks behind the newest
snapshot.

### Server side

- `ServerPlayer` (inner class): id, name, colour, `Sim.PlayerState`, the input queue, `last_applied` (the ack), a
  jitter buffer (`target_buf`, grows to 8 when it runs dry, shrinks after 10 s calm), spawn slot, and 1.5 s of
  position history for lag compensation.
- `_server_receive_inputs` puts new inputs into the queue by sequence number and drops extras beyond
  `Config.MAX_INPUT_BACKLOG`.
- `_server_tick` steps every player, the projectiles, the items and the ecology, and every `Config.SNAPSHOT_EVERY`
  ticks sends each client a snapshot with its own ack.
- `_server_step_player` applies exactly one queued input per tick (two when catching up), waiting up to 8 ticks for a
  missing one before skipping it. It runs `Sim.step`, then acts on the event: `_melee` for `MELEE_HIT`, `_shoot` for
  `SHOT`. It respawns a player who has finished being knocked out (keeping weapons and ammo), and on a fresh press of
  E picks up a weapon (`_pick_up`) or else tries to eat fruit (`Ecology.try_eat`, +8 HP).
- `_melee` tests every other player (rewound with `_pos_at` to the attacker's `view_tick`, at most 30 ticks back) and
  every dummy against the move's range and arc; the club smash also has a shockwave. It also shakes trees in reach and
  knocks fruit.
- `_shoot` creates a `Proj` with speed and damage from the draw (`Weapons.shot`) and announces it.
- `_server_projectiles` moves each projectile along its fixed path, testing four points per tick against players,
  dummies, tree trunks, the ground and pillars. `_end_proj` drops a pickable arrow or rock where it landed.
- Items: `Item` (inner class), `_spawn_item_at`, `_add_item` (at most 40 dropped things), `_remove_item` (fixed
  spawns return after 20 s), `_server_items` (respawns, expiry after 60 s, walking over ammo), `_pick_up`.
- `_damage` lowers health, applies knockback, starts the 3 s knockout at 0 HP, and broadcasts `hit_fx`. With `--log`
  it prints each hit.

### Client side

- `_client_tick` asks `input_source` for the input, builds a `Sim.PlayerInput` (rounding pitch and yaws to what the
  packet carries), predicts with `Sim.step`, emits `local_shot` for its own shots, keeps the input in `pending`, and
  sends the last 8 inputs.
- `_client_receive_snapshot` keeps the last 40 snapshots, measures jitter, and reconciles: it drops acked inputs,
  replays the rest from the server's state, counts a correction if the result differs, blends small corrections out
  visually (snaps if more than 4 m off), and always takes the replayed state so health, ammo and pick-ups come in.
- `_measure_jitter` sets `interp_delay` from how late 95% of snapshots arrive, between 3 and 20 ticks.
- `own_draw_position(frac)` and `remote_draw(id, frac)` tell Main where to draw players; `remote_draw` extrapolates up
  to 250 ms when no newer snapshot has arrived.
- `ping_ms()` reads ENet's round-trip time.
- Network simulator: `sim_lat_ms`, `sim_jit_ms`, `sim_loss`, `_sim_push`, and `_process` delay and drop this client's
  inputs and snapshots (set by `--netsim`).

## sim.gd

**`class_name Sim`.** The movement and combat step, run identically by the server (the authority) and the client
(prediction). It must stay deterministic: no randomness, no wall-clock time, only fixed `Config.DT` steps, and every
float rounded to 32 bits.

- `enum Btn`: input bits `FORWARD`, `BACK`, `LEFT`, `RIGHT`, `JUMP`, `SPRINT`, `DASH`, `ATTACK`, `INTERACT`, `FACE_CAM`.
- `enum Ev`: what a step reports: `NONE`, `MELEE_HIT` (the swing's hit frame), `SHOT` (a bow or slingshot released).
- Constants: walk 6 m/s, sprint 10 m/s, ground and air acceleration, gravity 28 m/s², jump 10 m/s, dash 24 m/s for 9
  ticks with a 54-tick cooldown, player radius 0.4 m, turn rates, `MAX_HP` 100, `RESPAWN_TICKS` 180,
  `DUMMY_RADIUS` 0.3 m.
- `PlayerInput`: one tick of intent: `seq`, `buttons`, `yaw` (camera heading), `pitch`, `weapon`, `view_tick` (for lag
  compensation), `aim_yaw` (the shot's direction), `face_yaw` (where the body should face).
- `PlayerState`: position, velocity, yaw, grounded, dash counters, weapon, owned weapons (one bit each), arrows, rocks,
  combo step and window, attack and cooldown counters, draw charge, `swing_n` (counts attacks so clients can tell a new
  one started), hp, knockout timer, `last_charge` (server only). `copy()` duplicates it.
- `spawn_state(slot)`: a fresh state on a small ring around the origin (golden-angle spacing).
- `step(state, input) -> Ev`: runs `_combat`, works out the wanted velocity from WASD relative to the camera (slower
  while drawing or mid-swing), turns the body (`_face`), handles the dash, accelerates, steps into a melee blow when
  moving, jumps, applies gravity, moves, lands on the ground, collides with boxes and dummies, clamps to the world
  edge, and quantizes.
- `_combat`: weapon switching, melee combos (chaining within `COMBO_WINDOW`, cancelling late in recovery), and drawing
  and releasing ranged weapons (using up ammo).
- `_face`: aiming, drawing or first person faces `face_yaw`; holding attack turns toward it at a limited rate; a
  committed swing keeps its direction; otherwise the body turns toward the way you walk.
- `_collide_boxes`, `_collide_dummies`: the player as an upright cylinder against boxes (stand on top, or get pushed
  out and slide along) and against the dummies' posts.
- `quantize(state)`: rounds position, velocity and yaw to float32, the precision snapshots carry.

Used by `Net` (server and client), `Codec`, `main.gd` (button bits, constants), the avatars (state fields), and
`tools/sim_test.gd`.

## codec.gd

**`class_name Codec`.** Binary packing for the two messages sent constantly. Uses `StreamPeerBuffer`, with no Godot
Variant overhead.

- `encode_inputs(inputs) -> PackedByteArray` / `decode_inputs(data) -> Array`: a count byte, then per input:
  sequence (u32), buttons (u16), yaw (float), pitch (s16, times 10,000, clamped to ±1.6), weapon (u8), view tick (u32),
  aim yaw (float), face yaw (float): `INPUT_BYTES` = 25 bytes each. Decoding rejects short packets and non-finite
  angles.
- `encode_snapshot(tick, ack, ents) -> PackedByteArray` / `decode_snapshot(data) -> {tick, ack, ents}`: tick (u32),
  ack (u32, the last input of the receiving client the server applied), count (u16), then per player: peer id (u32),
  position and velocity (6 floats), yaw (float) and 15 one-byte fields (grounded, dash ticks, dash cooldown, weapon,
  attack, attack cooldown, charge, swing count, hp, knockout, owned, arrows, rocks, combo, combo window). That is 47
  bytes per player (the header comment says 45).

`PlayerState.last_charge` is not sent: only the server needs it. Used by `Net`.

## config.gd

**`class_name Config`.** Constants every peer must agree on:

| Constant | Value | Meaning |
|---|---|---|
| `DEFAULT_PORT` | 7777 | UDP port. |
| `MAX_PLAYERS` | 32 | Server capacity. |
| `MAX_NAME` | 16 | Longest player name. |
| `TICK_RATE`, `DT` | 60, 1/60 | Fixed simulation rate. |
| `SNAPSHOT_EVERY` | 2 | A snapshot every 2 ticks (30 per second). |
| `INTERP_DELAY_TICKS` | 6 | Starting delay for drawing other players (100 ms); Net then adapts it. |
| `INPUT_REDUNDANCY` | 8 | Inputs repeated in each input packet. |
| `MAX_INPUT_BACKLOG` | 30 | Queued inputs per player before extras are dropped. |
| `WORLD_HALF` | 200 | The world spans ±200 m. |

Its comment says the tick rate is also set in `project.godot`; in fact `project.godot` does not set it, and Godot's
default of 60 physics ticks per second is what matches.

## weapons.gd

**`class_name Weapons`.** Weapon data shared by the server and every client, so attacks are predicted exactly like
movement. Times are in ticks (60 per second).

- `enum { FISTS, CLUB, SWORD, BOW, SLING }` and `NAMES`.
- `COMBO_WINDOW` (18 ticks to chain the next move) and `CANCEL_AT` (a move can be cancelled into the next once only
  35% of its recovery is left).
- `DATA`: one entry per weapon. Melee weapons have a `slow` factor and three `moves`, each with `windup` (ticks until
  the hit lands), `swing` (whole move), `recover`, `range`, `arc`, `damage`, `knock`, `lunge`, `anim` (Pip's
  animation) and `shape` (`arc`, `thrust` or `smash`, the smash with an `aoe`). Ranged weapons have `draw`, speed and
  damage ranges, `gravity`, `shot`, `cooldown`, `slow`, `projectile` and `ammo`.
- `get_data(w)`, `is_melee(w)`, `move(w, combo)`: lookups.
- `muzzle(pos, yaw)`: where a shot starts (chest height, half a metre ahead). `aim_dir(yaw, pitch)`: a unit direction.
- `proj_pos(pos0, vel0, g, n)` / `proj_vel(vel0, g, n)`: a projectile's position and velocity n ticks after launch, in
  closed form, so server and clients agree with no updates sent.
- `shot(w, charge) -> [speed, damage]` for a draw of `charge` ticks.
- `enum Item { CLUB, SWORD, BOW, SLING, ARROWS, ROCKS }`, `ITEM_NAMES`, `ITEM_WEAPON` (item kind to weapon slot, or
  -1 for ammo) and `MAX_AMMO` (60).

Used by `Sim`, `Net`, `main.gd`, both avatars, `WeaponModels` and the tools.

## world_layout.gd

**`class_name WorldLayout`.** The static world, identical everywhere because it is built from fixed data and a fixed
seed, so the simulation's collision and the visuals agree exactly.

- `Box` (inner class): a pillar with centre `cx`, `cz`, half sizes `hx`, `hz` and height `h`.
- `boxes()`: built once and cached: 60 random pillars (seed 20261104) between 15 m and 190 m from the centre, one box
  per tree trunk, and three steps near the spawn (0.9, 1.9 and 3.0 m high).
- `DUMMIES`: the three practice dummies' positions (target ids -1, -2, -3).
- `TREES` (apple, pear and ten oaks) and `TRUNK` (half width and height per kind). `tree_at(pt, margin)`: which trunk a
  point is inside.
- `ITEM_SPAWNS`: `[item kind, position, count]` for the weapons and ammo at the start.
- `ground_height(x, z, y)`: the highest surface under a point (for shadows, animation and landing spots).
- `ray_hit(o, d, max_t)`: distance along a ray to the first box (the camera uses it to avoid pillars; aiming too).

Used by `Sim`, `Net`, `Ecology`, `EcoView`, `main.gd`, the avatars and the tests.

## ecology.gd

**`class_name Ecology`, extends `RefCounted`.** The living yard, run on the server only (Net creates it in `host()`).
Ported from Jacob's Pip village (`04-games/pip/village`, outside this repository) with its rules and timings, at
1 village pixel = 0.04 m. It has one signal, `event(kind, args)`, which Net forwards to every client.

What it simulates:

- **Fruit.** The apple and pear trees each start with three ripe fruit in four slots. Every 60 s an empty slot may
  sprout (it swells to full over 4 s); every 45 s each ripe fruit has a 25% chance to drop (at most 4 on the ground
  per tree). `_drop` and `_launch` work out the fruit's whole path in advance: a parabola, maybe one bounce, then
  rolling segments that slow on the grass and glance off pillars, trunks, dummies and the world edge (`_roll`,
  `_wall_normal`). `path_pos(segs, t)` (static) gives the position at any tick, for the server and for `EcoView`.
  `slot_pos` (static) places hanging fruit.
- **Kicks and hits.** `_kicks` makes people walking into loose fruit kick it along. `hit_fruit` (from a melee swing)
  sends it flying. `hit_tree` (melee or arrow) shakes a tree; from the third hit, ripe fruit falls.
- **Eating.** `try_eat(pos, now)` eats the nearest fallen fruit within 1.3 m and returns 8 HP. If a worm is inside,
  30% of the time it blows a raspberry and you get nothing; otherwise it says "Hey!" and leaves.
- **Worms.** Every 6-12 s, if fewer than two worms exist, a worm may come for a fruit that has lain 25 s with nobody
  near: it emerges, looks around, crawls over, bores in, then pops in and out with greetings and quirks
  (`_worm_arrive`, `_worm_cycle`). It ducks when someone comes close and leaves if disturbed while crawling.
- **Birds.** After a worm has lived in a fruit for 9 s, a robin, sparrow or bluebird may come (about one every 12 s)
  when nobody is near. It glides in and either catches the worm out in the open or probes and pecks, then wins or loses
  a tug-of-war (`_bird_hunt`). A person coming close before it commits scares it off (`_bird_flee`).
- `tick(now, players)` runs all of this each server tick. `full_state(now)` lists events that recreate the current
  yard for a player who just joined.

Event kinds: `fruit_hang`, `fruit_fall`, `fruit_ground`, `fruit_gone`, `tree_hit`, `worm`, `bird`, `say`, `sound`.
Each worm and bird event carries the tick it starts at, so it can be scheduled. (`sound` events are sent but nothing
plays them yet.)

Uses its own seeded `RandomNumberGenerator`; tested by `tools/eco_test.gd` and `tools/fruit_test.gd`.

## eco_view.gd

**`class_name EcoView`, extends `Node3D`.** Draws the yard on clients from Ecology's events. Main creates it in
`_build_world` and calls `setup(net)`, which connects to `Net.eco` and builds the trees from `WorldLayout.TREES`.

- `_on_event(kind, args)` keeps track of fruit, worms and birds and their scheduled steps (`_add_step` replaces
  whatever was planned from a new step's start on).
- `_process` runs everything on `net.render_tick` (the same delayed clock as other players): trees wobble on a damped
  spring when hit (and shed leaves through `Fx.burst`), hanging fruit sways and grows, falling fruit follows
  `Ecology.path_pos` and turns as it rolls, worms (five pink spheres) and birds (body, breast, head, beak, eyes, wings
  in the species' colours) are posed for their current phase.
- `_bubble(at, text)` shows a floating speech bubble ("munch!", "Hello world!", "POP!", "pbbt!").

All models are built in code from spheres, cylinders and boxes; there are no asset files.

## avatar.gd

**`class_name Avatar`, extends `Node3D`.** A player drawn as **Pip**, Jacob's pixel-art character: a `Sprite3D`
billboard that stays upright and turns to face the camera.

- Loads both sprite sheets once (`_load_sheets`): `assets/pip/pip-spritesheet.png` + `.json` and
  `assets/pip/pip-weapons.png` + `.json`. The JSON gives the cell size (64 x 64), the anchor where the feet are, and
  each animation's row, frame count, frame durations and looping, per direction.
- `_init(player_name, color, show_name)` builds the sprite (0.04 m per pixel, so Pip stands about 1.8 m), a coloured
  ring at the feet, the name label and a small health bar.
- `animate(delta, cam)` (called by Main every frame) picks the animation for the player's state (`_pick`), picks one
  of eight views from where the camera is relative to the way the player faces (`_dir_for`, with hysteresis; SW, W
  and NW are mirrored from SE, E and NE), advances frames (the bow and slingshot draw frames follow the draw instead of
  the clock), shows the hit flash, health bar and ground ring, and fires the slash trail on the hit frame
  (`_swing_fx`, which uses `FigureAvatar._trail`).
- Animations used: `idle`, `walk`, `run` (speed-scaled), `dash`, `jumpStart`, `air`, `land`, `lieDown` / `lieIdle`
  (knocked out), the fist moves `jab` / `cross` / `kick`, club moves `c_swing` / `c_back` / `c_smash` with walking,
  running and air versions, the matching sword moves from the weapons sheet, and `bowDraw` / `bowShot` /
  `slingDraw` / `slingShot`.
- `flash()` tints the sprite red briefly; `hitstop(seconds, shake)` freezes it on impact.

## figure_avatar.gd

**`class_name FigureAvatar`, extends `Node3D`.** A player drawn as the rigged **3D figure**, with the same interface
as `Avatar` (`yaw`, `grounded`, `dashing`, `state`, `model`, `label`, `flash()`, `hitstop()`, `animate()`), so Main can
use either.

- `_init` builds the body from simple meshes: pelvis, waist, chest, a tunic in the player's colour with belt and hem,
  head with eyes, brows, nose, ears and hair, arms with elbows, hands and thumbs, legs with knees and boots, plus a
  name label, health bar and ground ring.
- Arms and legs are two-bone IK chains (`ik()` static, `_arm`, `_leg`), so each pose only says where hands and feet go.
- `animate(delta, cam)` computes the whole pose every frame from the state, smoothed with critically damped springs
  (`spring_v`, `spring_f`): breathing and glances at rest, stepping feet and swinging arms when moving, tucked knees in
  the air, keyframed melee moves (`_move_keys`, `_sample`, with hands moving on arcs around the shoulder,
  `_arc_lerp`), real archery for the bow (side-on stance, draw to the jaw, a flexing stave, string and arrow drawn
  live), and the slingshot pulled back to the cheek with stretching bands. `_track_release` notices releases so the
  string and bands spring.
- Holds the right weapon model from `WeaponModels` (`_update_held`, `_draw_weapon`), shows a quiver on the back and a
  stone bag on the belt when you have a bow or slingshot.
- `_trail(parent, pos, yaw, weapon, mv)` (static) draws the move's effect with `Fx` (slash, thrust streak, or smash
  arc with shockwave and dust). Pip's `Avatar` uses it too.
- `instant` skips smoothing (for previews); `last_hand_r`, `last_hand_l` and `last_grip` record where the hands and
  the grip ended up (the preview tools mark them).

Previewed with `tools/figure_poses.gd` and `tools/figure_strip.gd`.

## weapon_models.gd

**`class_name WeaponModels`.** 3D models of the weapons and ammo built from boxes, cylinders and spheres, each standing
along +Y with its grip at the origin.

- `make(kind)` takes a `Weapons.Item` kind and returns the model (used by Main for items on the ground).
- `for_weapon(w)` takes a weapon slot (fists have none; used by `FigureAvatar` for the hands).
- `sword()`, `club()`, `bow()` (a curved stave with a string named `string`), `sling()` (fork with bands `band_l`,
  `band_r` and a `pouch`), `quiver()`, `rocks()`.
- Helpers `_mat`, `_mesh`, `_box`, `_cyl`, `_sphere`.

## fx.gd

**`class_name Fx`.** Purely visual combat effects, all static functions that add a short-lived node to a parent and
free it when done:

- `slash(parent, pos, yaw, r, span, color, overhead, flip)`: a crescent ribbon around the player that sweeps through
  the air (a small additive shader, `SLASH_SHADER`), flat or overhead.
- `thrust(parent, pos, yaw, reach, color)`: a straight streak forward from the chest (punches and the sword thrust).
- `shockwave(parent, pos, color)`: a ring growing along the ground (the club smash).
- `burst(parent, pos, dir, color, count, speed, size)`: a one-shot burst of little cubes (sparks, straw, dust, leaves).
- `word(parent, pos, text, color)`: a short word that pops and fades ("Shing!", "Thock!", "munch!").

Used by Main (`_on_hit`, pick-ups, "the host picks the look"), `FigureAvatar._trail`, and `EcoView`.

## dummy.gd

**`class_name Dummy`, extends `Node3D`.** A practice dummy: a straw figure on a post (post, sack body, head,
cross-arm, rope bands, base), built in code. Purely visual: the server decides hits, using target ids -1, -2, -3.

- `hit(amount, dir)` (called by Main's `_on_hit`): flashes white, pushes the dummy to lean away from the blow, and
  adds to the running total.
- `_process` swings it back upright on a damped spring and updates the label: the last hit, the total and damage per
  second, reset after 4 s without a hit ("Practice dummy" when idle).

Its solid post is in `Sim._collide_dummies`; its positions are `WorldLayout.DUMMIES`.

## updater.gd

**`class_name Updater`, extends `Node`.** Checks GitHub for a newer release and downloads the update pack. Main's menu
creates one (not for bots) and shows its messages.

- Signal `changed(text, can_restart, page_url)`: a status line for the menu, whether **Restart now** applies, and a
  page to open instead.
- Constants `REPO` (`juggernautjake/multiplayer-game`), `API` (latest release endpoint), `PAGE` (latest release page).
- `update_dir()` (static): `updates/` beside the executable if it can be written, else `user://updates`; always
  `user://updates` when running from the editor.
- `read_version(path)`, `running_version()` (static): the version actually running, the downloaded one if boot.gd
  would have loaded it, else `res://version.txt`. Net sends this when joining.
- `newer(a, b)` (static): compares dotted versions, ignoring a leading "v".
- `check()`: in the editor, just reports that updates come from git; otherwise requests the latest release.
- `_on_release`: if the tag is newer, finds the `game.pck` asset and the `godot: x.y.z` line in the release notes; if
  the Godot version matches, downloads to `game.pck.part`, renames it, writes `version.txt`, and reports "Restart to
  play it"; otherwise points to the download page.
- `restart()` (static): starts a new copy of the game with the same arguments and quits this one.

The header comment mentions a `manifest.json` release asset; the code does not use one. The Godot version comes from
the release notes, which `tools/release.sh` writes.

## magic_fx.gd

`class_name MagicFx`, a Node3D that Main adds to the world. It draws every spell from the server's spell events
(`Net.magic_fx(kind, args)`) and from players' states:

| Event | What you see |
|---|---|
| `lightning_warn`, `lightning` | a pulsing ring where it will land, then a jagged bolt with forks, a flash (with shadows), sparks, a scorch |
| `explode` | a fireball's burst: growing balls of fire, smoke puffs, sparks, a flash, a scorch |
| `shield_up`, `shield_hit`, `shield_shatter` | the bubble (a shader with a bright rim and drifting bands; up to six impact ripples running out from where hits land), its pop, and its shattering into glowing shards |
| `stun_beam`, `stun_burst` | a violet bolt and a crackling ring where it bursts; stars spin over stunned heads |
| `teleport` | violet puffs at both ends and a fading streak |
| `golem_rise`, `golem_slam`, `titan_rise` | dust, cracked rings, camera shake |
| `frost_nova`, `spike`, `meteor_warn`, `meteor`, `well`, `well_burst`, `storm` | the level 2-4 spells (see the table in the main README) |
| `level_up` | a column of golden light and the new spell's name (a toast on your own screen) |
| `vault_door` | swings the vault's door open or shut |

Every frame `update(delta, states)` keeps shield bubbles on their players (flickering when mana runs low), puts frost
at the feet of slowed players, and lights each caster's staff or wand in the spell's colour while they cast or hold
the shield, with sparks drawn in. `fireball_node()` builds the flying fireball (an emissive orb, a light, trailing
embers) that Main flies like any projectile. Only the biggest flashes cast shadows, to keep the frame rate up.

## golems.gd

`class_name Golems` (RefCounted, server only): the wand's stone golems and the Stone Titan. `spawn(owner, pos, yaw,
now, titan)` (six small ones per summoner, one titan), `tick(now, people)` runs their AI each server tick and returns
the slams that landed, `hurt(id, amount, from, dir)`, `stun(id, ticks)`, `pack()` for the network.

The AI: rise from the ground (0.75 s), pick a target every quarter second (the nearest player both sides have PvP on
for, or another summoner's golem, within 25 m; else a practice dummy within 14 m; else follow the summoner), steer
round pillars (the first free direction fanning out from the straight line, keeping to one side, with a detour when
stuck), start the slam on the run as it closes in and keep chasing while the arms come up. Never targets its own
summoner, who can't hurt it. The titan is slower and tougher and its slam hits everyone within 2.8 m of where it lands.

## golem_view.gd

`class_name GolemView`: draws the golems from `Net.golems_changed` (a few updates a second), easing each toward where
the server says it is. Built from stone blocks (moss on the shoulders, glowing amber eyes; the titan darker, with red
eyes and a molten glow in its chest) and animated in code: rising out of the ground, breathing, walking (legs and arms
swinging, body rocking), slamming (arms up, lean back, slam, lean in; legs still running when it swings on the move),
stunned (violet, trembling) and crumbling (the blocks fly apart, tumble and sink).

## Magic in the other scripts

- **weapons.gd**: `STAFF` and `WAND`, their spell tables (cost, timing, range, radius, damage, level), `LEVEL_KILLS`,
  `level_for`, `unlocked`, `area_damage` (full at the centre, falling to the minimum at the edge), shield mana costs.
- **sim.gd**: mana, the picked spell, the held shield, stun, slow, the wand's recharges and both weapons' levels are part
  of the player state; casting, the shield and the teleport (`teleport_target`, a blink with a maximum reach) are in
  the shared simulation, so they are predicted exactly; `Ev.CAST` tells the server a spell went off.
- **net.gd**: `_cast` and the spell code (lightning, fireballs as projectile kind 2, `_blast` for area damage, `_stun_target`,
  gravity wells, storms, golems), `_shield_soak` (hits on a shield cost mana; out of mana it shatters), `_magic_kill`
  (levels), PvP (`set_pvp`, `can_hurt`), the vault door, the one-of-a-kind staff and wand.
- **world_layout.gd**: the tower (`TOWER_*`) and the vault (`VAULT_*`) as boxes with a `kind`, the staff and wand spawns.
- **main.gd**: R picks a spell, the mana bar, the spell and level lines, the aim point sent with every input, the vault's
  look and door, the tower's beacon, `--give-all`, `--max-level` and `--bot magic` (`--plan2`, `--plan3`) for testing.
- **avatar.gd** / **figure_avatar.gd**: the staff or wand in hand (Pip holds a small 3D model at his side), cast poses,
  the staff raised overhead while shielding; outfits per player (`tools/make_outfits.py`).

## v0.8.0: animation, garb, effects and netcode

### wizard_garb.gd

`class_name WizardGarb` (Node3D, top-level: placed in world space). `kind_for(state)` picks the garb from what the
player carries: `WIZARD` (staff: grey robe and pointed hat), `SHADOW` (wand: dark hooded robe), `BOTH` (grey robe and
hat, the dark hood dropped round the neck) or `NONE`. Each avatar owns one and calls `update(delta, frame)` every
frame with where its body is (`hip`, `basis`, robe radii and length, leg capsules to keep out of, the ground, head top,
centre, size, up and facing, hat sizes).

- **Robe:** 20 strands x 6 rows of Verlet particles. The top ring is pinned to the waist; the rest fall under gravity,
  keep their length, spring gently back toward the robe's shape, never swing more than about 60 degrees from hanging
  straight down, keep their spacing round the ring, are pushed out of the body and the legs, and stay above the
  ground. Damping is relative to the body's own motion (damping world velocity would act like a gale and blow the robe
  flat when running). Running and dashing add a flutter at the hem. Drawn each frame into an `ImmediateMesh`
  (toon-shaded, a lighter trim at the hem).
- **Hat:** a chain of 5 points from the brim to the tip, each springing toward its place (stiff at the base, loose
  at the tip), drawn as tapered segments, with a band and a brim that tilts after the crown.
- **Hood:** a dome over the back of the head, a rim round the face and a 4-point tail hanging down the back.

### cast_pose.gd

`class_name CastPose`, static: `at(weapon, spell, into, windup, cast)` gives the staff or wand's reach, lift, sideways
offset, angle, crouch, lean, flare and whether the free hand joins, through each spell's gesture: `thrust` (Fireball,
Stun, Teleport), `sky` (Lightning, Meteor, Arcane Storm), `slam` (Frost Nova, Earth Spikes), `summon` (Golem, Stone
Titan), `vortex` (Gravity Well). Each gesture has anticipation, a fast release with overshoot and a follow-through; the
wand adds a looping flourish while the spell builds. Pip's prop and the figure's hands both use it.

### motion_fx.gd

`class_name MotionFx`, static: `puff` (dust at the feet), `land` (a ring of dust on a hard landing), `ghost_sprite`
(Pip's dash afterimages), `speed_lines` (the figure's dash).

### fireball_view.gd

`class_name FireballView` (MeshInstance3D): the fireball in flight. Each has its own size and colour; a white-hot core
and two churning see-through shells of flame, a flickering light, embers, a smoke ribbon and sparks.
`MagicFx.fireball_node()` returns one; Main flies it like any projectile.

### Changes in the existing scripts

- **avatar.gd (Pip):** squash and stretch over the drawn frames (stretching into a jump, squashing on landing by how
  hard he fell, a jolt on every blow, a kick back on every shot), running dust, dash afterimages, the staff and wand
  through `CastPose`, and the garb. Pip's head and shoulders move from frame to frame, so the garb reads where they
  are from the frame being shown (`_cell_info`: the first row of the head and the middle of the head and shoulders,
  cached per frame). With a robe, his sheets switch to the robe's colours (outfits 4 and 5).
- **figure_avatar.gd:** strafing leans into the side, backpedalling leans back, the head leads turns, a crouch soaks
  up landings (with dust) and it stretches on take-off, arms out for balance in the air, a low dash with the arms swept
  back and speed lines, dust where running feet plant, a little variety in every swing (by its number), the casting
  gestures, and the garb (recoloured tunic, sleeves and trousers, bell sleeves from the elbows, the cloth). Also fixed
  an old "axis must be normalized" error when the weapon's direction barely changed.
- **golems.gd:** golems after one target spread round it (`_assign_slots`, `SPREAD`), keep apart (`_separate`), leap
  from 3-5.5 m (`State.LEAP`, `LEAP_*`), stand guard round their summoner (`GUARD_R`), and look 2.6 m ahead for
  pillars (`_free_static`).
- **golem_view.gd:** footfalls with dust, the leap's crouch, arc and landing, alternating slam and haymaker, a flinch
  when hit, the head looking about, pulsing eyes; golems are drawn on the players' clock (`_interp`, from
  `Net.render_tick`).
- **magic_fx.gd:** fractal lightning (`_fractal`, `_bolt_paths`, `_ribbons`: one mesh per stroke) with re-strikes,
  ground arcs, afterglow and a distance-scaled thunder shake (`_shake_near_scaled`); randomised explosions; ragged
  scorches (`_scorch_ragged`); smoke (`_smoke`); rune circles under casters (`_rune`, `_make_rune`); the teleport's
  collapsing and bursting columns (`_blink`); summoning circles (`_summon_circle`) and cracks (`_cracks`); crackling
  arcs round stunned players.
- **net.gd:** the interpolation delay's fixes (`_measure_jitter`), the predicted own fireball, channels 6 and 7 for
  projectile and hit messages, input buffers starting at 3, the connection readout (`quality_line`, `loss_pct`,
  `check_tailscale_path`). See [docs/networking.md](../docs/networking.md).
- **main.gd:** the HUD's connection line; the `show` and `golems` bots; `--every` for the magic bot.
