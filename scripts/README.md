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
offset, angle, crouch, lean, flare and whether the free hand joins, through each spell's gesture: `thrust` (Fireball, Spark Beam, Life Drain,
Stun, Teleport), `sky` (Lightning, Meteor, Arcane Storm), `slam` (Frost Nova), `summon` (Golem, Stone
Titan), `vortex` (Gravity Well, Fog). Each gesture has anticipation, a fast release with overshoot and a follow-through; the
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

## v0.8.1

- **wizard_garb.gd** (rewritten; the 3D figure only): the robe is a stack of rings (`f.rings`: centre, basis, radii);
  the top `pinned` ones ride the body (round the neck, the shoulders, the chest, the waist), the rest are heavy cloth
  hanging to the floor. `_hang` keeps each segment its length (it used to let segments stretch, so the 0.8.0 robe
  bunched up like a skirt) and within ~60 degrees of hanging straight; `_push_from_leg` keeps cloth in front of a
  striding leg, never behind it; `_push_inward` keeps it inside the forearms and hands. Drawn with thickness: a darker
  lining `THICK` inside, joined at the hem. The wizard's cloak is an open sheet pinned round the back of the shoulders,
  lighter (it swings more), with a back face; a rope belt at the waist ring; the hat is a soft felt cone of 6 points
  with a crooked tip (see-through on your own head: `own`); the wand's hood is a deep cowl framing the face.
- **figure_avatar.gd:** `SHOULDER` / `SHOULDER_REST` (the joint at the end of the collarbone), the `trap_*` parts,
  `arm_fk` (an arm posed from swing, elbow bend and abduction, with its elbow pole), `_pole_l`, the archery stance
  (`ARROW_RUN`, and `aim_pitch`, set by Main for your own player), the robe's rings and colliders in `_dress`, the face
  shadowed in the hood, `orb_position()`.
- **avatar.gd (Pip):** no 3D garb or 3D staff any more. `garb_textures` swaps to the garb sheets; `_update_prop` draws
  the carried weapon as a sprite at his hand (`assets/pip/garb/pip-hands.json`, `assets/pip/carry`), hidden in the
  frames that already show it, moved through the casting gestures and raised overhead for the shield;
  `orb_position()` for the shield.
- **magic_fx.gd:** the shield's shader (screen-space refraction, fresnel rim, shimmer, honeycomb, energy flowing from
  the orb, hit ripples sized by `hit_s`), `_orb_emit` (the glow, light and sparks at the orb), `_shield_hit` with the
  hit's strength.
- **net.gd:** `shield_center`, `_shield_bounce`, `proj_bounce`, `Proj.immune` / `bounces`; `shutdown()` and the bind
  retry in `host()`.
- **weapons.gd:** `SHIELD_RADIUS` 1.5, `SHIELD_CENTER_Y` 1.1, `SHIELD_BOUNCE`.
- **main.gd:** `_leave_game`, `_on_proj_bounce`, the `archery` bot, `--orbit`, `--carry`, `--leave-at`.

## v0.9.0

- **Costumes:** `WizardGarb.kind_for` gives the costume for the equipped weapon (`COSTUME`, `LOOK`); new kinds
  BRAWLER, KNIGHT, BARBARIAN, RANGER, SCOUT. WizardGarb dispatches per costume: the robe's ring cloth (robes, the
  barbarian's kilt), the cloak (wizard, ranger: `cloak_col`), `_sheet` (hanging panels: the knight's tabard front and
  back), `_chain` (swinging tails: sash ends, headband tails, the bandana's knot), `_satchel_bounce`. figure_avatar.gd:
  `COLS` (each costume's colours on the body's own parts), `_build_costume_parts` / `SHOWN` / `_cpart` (rigid pieces,
  built once and shown per costume), the accent from the player's colour, a puff on every swap. avatar.gd (Pip):
  `garb_textures` (the costume's sheets and accent sheets), `_accent` (the accent sprite, tinted, just in front).
- **Chain lightning:** net.gd `_blast` returns who it struck; `_chain_jump`, `_chain_candidates`, `_target_feet`,
  `_shield_up`; magic_fx.gd `_chain`. weapons.gd: Lightning's `falloff: false`, `chain_range`, `chain_max`,
  `chain_every`; `area_damage` honours `falloff`.
- **Pip's carried weapon:** 12 cm toward the camera (was 3 cm) with a sorting offset, 2 px out from his middle, ahead
  of him side on.
- **Cloth length:** the robe's and cloak's lengths come from the feet (`feet_y`), not the ground.

## v0.10.0: the Duel Stone, challengers, the Storm Altar, Thunderhorn and the prize

- `npc_ai.gd` (`NpcAI`): a challenger's brain. `think(net, me)` returns a `Sim.PlayerInput` that `Net._server_npcs`
  queues like a player's input, so challengers obey exactly the same rules. Archetypes melee / ranged / staff / wand;
  reaction delays, aim error and dodge chance per difficulty (0 easy, 1 medium by default, 2 hard); spacing, strafing,
  dodges, feints, punishing recovery, retreating when hurt; leading shots (`_lead`, the low ballistic arc) and kiting;
  wizards shield, cast area spells, blink, summon golems and follow stuns up.
- `boss.gd` (`Boss`): Thunderhorn on the server (a `RefCounted` like the golems). States `S`, `tick(now, people,
  golems)` fills `hits`, `slows`, `strikes` and `fx` for Net to apply; `hurt(amount, from, spell)` applies his
  weaknesses (Meteor x1.5, Lightning x0.25, Fireball burns), `stunned` (a point on the stun meter; 7 = dazed),
  `frosted`; enrage below 1/2, storm below 1/4; `pack()` for clients. Target id `Boss.ID` (-5000).
- `boss_view.gd` (`BossView`): draws him from `Net.boss_changed` and the `boss_*` events: the cloud body, the lightning
  skeleton, horns, eyes, gait, every state's pose, the beam, stomp rings, ball lightning, the static field, sounds,
  and the health bar with status. Also the challengers' arrive/leave puffs.
- `arena_view.gd` (`ArenaView`): the Duel Stone (gold runes, violet after level 2) and the Storm Altar (rises at level
  3), their toasts and prompts (`prompt_for`).
- `prize_screen.gd` (`PrizeScreen`): victory (confetti, the words, the Smiguel fiesta ported from LoadingFiesta) and
  defeat (sad trombone, any key -> `Net.ask_restart`). The picture is loaded at runtime only (`load_picture`:
  `prize/` next to the exe, then `user://prize/`), with a drawn stand-in.
- `synth.gd` (`Synth`): sounds made in code: roars (entrance, enraged, bellow, death), thunder, trumpet, maracas, sad
  trombone.
- `net.gd`: `ServerPlayer.npc` / `.ai`; `humans()`; `duel_pool`, `_stone_interact`, `spawn_npc`, `_server_npcs`;
  `_server_altar`, `summon_boss`, `_server_boss`, `restart_after_defeat`, `ask_restart`; signals `toast_msg`,
  `boss_changed`, `boss_result` ("victory", "defeat", "restart"). Challengers get no snapshots or toasts over the
  network and don't take player slots.
- `world_layout.gd`: `DUEL_C`, `ALTAR_C`, `ARENA_R` (pillars and trees kept clear of them).
- `main.gd`: builds ArenaView, BossView and PrizeScreen; toasts stack; bots `duel`, `boss [--defeat]`, `prize`.

## v0.11.0: Thunderhorn reworked, Static, the Storm Leap

- `boss.gd`: the header documents the whole fight: the designed flow (opener `plan`, rotation, phase changes via
  `want_phase` -> `S.PHASE`, the Storm Leap), every attack and variant (`variant` 0/1/2 by phase), manoeuvres
  (`S.STRAFE`, `BACKOFF`, `HOP`, `TURN`, `LUNGE`), targeting (`_retarget`: distance, `threat`, `damage_by`, `far_t`,
  casting, finishing, helpless, line of sight `_los`, `attention` share and `focus_t`), and the numbers.
  - **Static:** `zaps` ([player, damage, dir, blocked]) from homing orbs, static balls and the static roar; Net's
    `_boss_zap` / `add_static`: a stack is `Sim.ZAP_STACK` (200) in `PlayerState.zap`; `Boss.static_need(enraged)` =
    6 stacks (5 enraged) -> `zap = Sim.ZAP_STUN`, `stun = Sim.STATIC_STUN` (420 ticks, 7 s). After a hit `zap_cd` =
    `Sim.ZAP_HOLD` (150), then `Sim.step` drains 1 a tick (a stack in 3.3 s); the meter clears when the stun ends or
    on death. A shield (or a hit while static-stunned) adds nothing.
  - **Storm Leap rules** (`_want_leap`): at most `LEAP_MAX` 5; at least `LEAP_GAP` 1500 ticks (25 s) from one start to
    the next; guaranteed as health passes each of `LEAP_HP` 80/55/30% (`leap_sure`); if fewer than 2 have happened
    and 75 s (`LEAP_FALLBACK`) pass, one anyway; up to 2 bonus leaps (`leap_bonus`) at an 18% chance per pick while
    the players do well (`_doing_well`: average health >= 70% and `hurt_recent` per player < 15, fading over ~14 s)
    and he is below 92%. A phase change goes first. Sequence states `SEQ`: `LEAP_WIND` 90 ticks (`_leap_spot`: far,
    never within 6 m of a player), `LEAP` 84 ticks (a 14 m arc), the landing ring (kind 1: jump it), `LEAP_LAND` 40,
    `HOWL` 260 (`homing_count(n)` = min(5 + 5n, 24) orbs, `_launch_orb` round robin over the living, `orb_sent`),
    `SLAMS` 140 (three rings at 9, 10.5, 12 m/s), `PAW` 96 (locked on the nearest player not stunned or down), `RUSH`
    24 m/s (`launches`; a dashing player is untouchable), `RECOVER` 70.
  - Orbs: `ORB_V0` 6 -> `ORB_VMAX` 15 m/s at `ORB_ACC` 5, `ORB_TURN` 2.8 rad/s, a little lead from `pvel`, gone after
    `ORB_LIFE` 330 ticks or in a pillar; a shield bounces them (spent).
  - Health: `hp_for(n)` = 7000 x (1 + 0.7 (n - 1)); `add_fighter()` when someone joins mid-fight (Net
    `_server_add_player`).
  - Rings are `[radius, hit, centre, speed, damage, kind]`; `pack()` sends rings as [r, cx, cz, kind], balls as
    [pos, static], orbs as a PackedVector3Array and `[leap x, leap z, variant, phase, target, rush target, rep]`.
  - `people` rows from Net: [id, pos, alive, shielded, hp, dash ticks, casting, helpless].
- `boss_model.gd` (`BossModel`, new): the creature: a Skeleton3D (`BONES`), one skinned body mesh lofted through
  Catmull-Rom cross sections (`_loft`, `_chain_w` weights), rigid details on `BoneAttachment3D`s, the shaders
  (`HIDE_SHADER`, `STONE_SHADER`, `SMOKE_SHADER`, `TRAIL_SHADER`), `apply(pose, legs, tail_t, delta)`, `set_look`,
  and `Trail` (verlet glowing ribbons).
- `boss_view.gd`: rewritten around BossModel: per-state poses (`_smooth_pose`), trail colours, the leap marker, the
  rush path, orbs, gold jump rings, the storm swirl, banners, all `boss_*` / `static_*` events and their sounds
  (`_sound(key, ...)`, cached `Synth` sounds).
- `synth.gd`: `fx(kind)`: snort, hoof, scrape, crackle, charge, whoosh, zap, slam, chirp, stun, pant, eat; `roar(4)`,
  the howl.
- `sim.gd`: `PlayerState.zap`, `zap_cd`, `down` (knocked down: no control, no air control, a long slide; the last
  `DOWN_GETUP` ticks are the get-up). `codec.gd`: stun now 16 bits (7 s), plus zap, zap_cd, down (79 bytes a player).
- `net.gd`: `_boss_zap`, `add_static`, `boss_launch`; richer `people` rows; health growth when joining mid-fight.
- `avatar.gd` / `figure_avatar.gd`: the Static bar over other players' heads (`Avatar.static_bars`, `show_static`),
  a dizzy sway when stunned (a violet flicker on Pip when it's Static), knocked down (Pip: lieDown / lieIdle, then his
  getUp frames following the clock; the figure tumbles in the air, lies flat, then pushes up). `main.gd`: the HUD
  Static bar (segments, stun countdown), "Knocked down!", the `--leap` bot.
- `npc_ai.gd`: ranged challengers: `SHOT_ERR`, `SHOT_START`, `SHOT_HOLD`, `_pause`; `_lead(..., lead)` (0 for them).

## v0.12.0

- `wizard_garb.gd`: cloth keeps up with fast moves. `_carry(step)`: of the body's step this frame (the anchor's
  motion), anything beyond `lag_speed` (7 m/s) x the frame time is added to every free point and its previous position
  before integrating, so a dash, teleport, frame hitch or net correction (own or interpolated remote players: both go
  through `update`) no longer leaves the robe, cloak, hat, hood tail, tabard and sash tails behind to whip back. A last
  pass clamps every robe and cloak segment to its rest length. Pip's garb is drawn into his sprite sheets, so it never
  lagged. Test: `tools/cloth_test.gd`.
- `golems.gd`: golems fight for their summoner. `foe(owner, other, pvp)`: Thunderhorn (`Who.BOSS`), challengers and
  minions (`Who.NPC`) and their golems always; other players and their golems only with PvP on for both and a grudge
  (`harmed(owner, other, GRUDGE)`: they hurt the summoner or one of the summoner's golems in the last 12 s). A
  challenger's own golems fight players (and their golems). `_pick`: within `LEASH` (18 m) of the summoner and `SENSE`
  of the golem, whoever hit the summoner in the last 4 s (`ATTACKING`) first, then the nearest. `note_harm(victim,
  attacker, tick)` is called by `Net._damage` for every hit on a player or a golem. `people` rows gained a 5th field,
  `Who`. Credit is unchanged: a golem's hit is its summoner's (`dmg_src = WAND`: challenger kills level the wand, boss
  damage goes into `damage_by`), and killing a golem gives nothing.
- `npc_ai.gd`: `_pick_target` turns on a players' golem within 4 m (or one that hit it in the last 2 s, within 8 m),
  through `_golem_proxy` (a ServerPlayer standing in for it).
- Charge throws (v0.12.0): both the charge and the rush now throw (`Boss.launches`), and also hit and throw
  challengers and minions in the path (`Boss.bystanders`, filled by `Net._server_boss`; `_trample_bystanders`).
  `Net.boss_launch`: `LAUNCH_V` 22 m/s out, `LAUNCH_UP` 11 m/s up. `Sim.step` while `down`: smashing into the ground
  faster than `BOUNCE_MIN` (4 m/s) bounces (`BOUNCE_K` 0.5, losing 18% across), hitting a pillar, trunk or post
  ricochets (`RICOCHET_K` 0.6, a hop up) instead of sliding along it, the world's edge throws you back, and the
  knock-down clock waits through the flight and skid. Typically ~30 m with two bounces, ~3 s down. The figure tumbles
  head over heels with a cartwheel (also while skidding), Pip spins in the view's plane (`Avatar._pip_tumble`: the
  billboards off, the body rolled round its middle); both throw dust at each bounce and ricochet and trail it while
  skidding. Tests: boss_test (`_throw_tests`).
- Storm Leap (v0.12.0): `LEAP_H` 34 m, `LEAP_AIR` 135 ticks (2.25 s). Take-off: a crater (scorch, cracks, debris,
  dust) and a shake; in the air, lightning streaks trail behind him (`_update_marker`) and his shadow grows and darkens
  on the landing marker; landing: a white impact flash, gold sparks, debris, a stray bolt, a big shake.
- Landing spot (`Boss._leap_spot` -> `maximin_spot(points)`): candidates are a 1.5 m grid (`LEAP_GRID`) over the arena
  disc less a 3 m margin (`LEAP_MARGIN`), minus points within `RADIUS + 1` m of any `WorldLayout.boxes()` obstacle
  (`leap_candidates()`). Each candidate scores its distance to the nearest living player (`min_dist`); the highest
  wins (maximise the minimum distance). Ties within 1 cm go to the candidate nearer the arena's centre, then grid
  order: deterministic on the server. No one alive: the centre. Test: boss_test `_maximin_tests` (1 and 2 players,
  the pick's min-distance >= every candidate's, inside the bounds).
- Static looks (v0.12.0, `BossView.static_star`): every Static source (homing orbs, static balls) is a spinning spiky
  caltrop, a hot-pink core with six white needle spikes in a violet shell, crackling white and trailing violet
  sparks, with a buzz (`Synth.fx("buzz")`) when one appears; his plain damage balls stay smooth blue-white spheres. The
  first one shows the banner "Violet orbs build STATIC / 6 hits = stun!".
- Apples heal (v0.12.0, `ecology.gd`): every tree bears fruit (oaks grow apples, hung lower and further out under
  their crown: `slot_pos(tree, slot, kind)`), up to the four slots, regrowing one per tree a minute. Any hit by any
  weapon or spell knocks one ripe apple loose (two for 8+ damage). `eat_under(pos)`: a hurt player walking over a
  fallen fruit (no worm in it) eats it: +`HEAL` (18) health; the `fruit_gone` event then carries [id, true, heal, pos]
  and EcoView shows "+18", a green sparkle and the crunch (`Synth.fx("eat")`). E still eats one too (now +18). Five
  real apple trees ring Thunderhorn's arena (`WorldLayout.TREES`, the last five). `fell_tree`, `restore_trees`,
  `ground_fruit_near`, `splat` (events `tree_fell`, `tree_up`, `fruit_splat`) are for Thunderhorn (below). Test:
  fruit_test `_apples`.
- Thunderhorn vs trees and apples (v0.12.0, `boss.gd` "knows apples heal" block; `Net._server_boss` fills
  `boss.trees` / `boss.apples` and applies `felled` / `splats` through Ecology): he goes for the nearest tree within
  24 m now and then (`S.TREE`: walk up, lower the horns, splinter it; `TREE_CD` 15 s apart, likelier when a fighter is
  under half health or has just eaten), lines charges up through a tree near his line to the target (70% of
  charges, `_tree_on_line`), fells anything his charge or rush runs through, tramples apples underfoot and stomps (or
  bucks, 5 m) apples near him (`APPLE_CD` 4 s, shorter under pressure). Felled trees topple in EcoView and bear no
  fruit; `Ecology.restore_trees` stands them up again on summoning, victory and restart. Splats fade after ~5 s.
  Tests: boss_test `_tree_tests`.
- Far Storm Leap (v0.12.0, Jacob: "very far across the map"): `leap_candidates(from)` is now a 5 m grid over the
  whole 400 x 400 m map, `LEAP_EDGE` (10 m) inside its edge, within `LEAP_MAX_D` (200 m) of the take-off and clear of
  obstacles; `maximin_spot(points, from)` picks the one furthest from the nearest living player (ties: nearer the
  arena, then grid order). In practice he bounds ~200 m. `leap_arc(d)`: apex 34 -> 75 m and 2.25 -> 3.4 s in the air
  as the distance grows to 200 m (`leap_h`, `leap_air`; `leap_air` is sent as the 8th `extra`). The view adds a 120 m
  gold light pillar over the landing spot and an edge-of-screen arrow with the distance (to the landing spot during the
  leap, to him while he's far and off screen). Homing orbs launched from far away get enough life to cross the map and
  cruise at `ORB_FAR_V` (30 m/s) until `ORB_SLOW_R` (30 m) from their target, then the usual dodgeable 15 m/s.
- Going home: between attacks (idle, walk, strafe, back-off, turn, recover, tree, stagger) he drifts back toward the
  arena at up to `HOME_DRIFT` (16 m/s, scaled by how far out he is); attacks, targets and trees are chosen as always.
  With no living player within `HOME_NEAR` (40 m) he gallops home (`S.HOME`). Test: boss_test `_home_tests` (from
  ~180 m out he's back within ~32 m of the arena centre in 45 s of fighting, with as many attacks as at home).
- Demo: `--bot boss --leap --chase` follows him with the camera through the leap (`Main._chase_cam`); `--every N`,
  `--from T`, `--until T` control the leap pictures. Record a video with Godot's movie maker, e.g.
  `<godot> --path . --write-movie leap.avi --fixed-fps 30 -- --host --port 7793 --give-all --bot boss --leap --chase --every 100000 --until 1000`.
- Map-wide shockwaves (v0.12.0): the Storm Leap's landing ring (kind 1, gold) and the three slam waves after the howl
  (kind 2, white-blue, 12 damage, 14 enraged) race out at `Boss.WAVE_V` (22 m/s) until `wave_max(centre)` (past the
  map's farthest corner), so every grounded player anywhere is hit unless they jump as it passes; `WAVE_GAP` 75 ticks
  (1.25 s) between slam waves leaves time to land and jump again. Rings carry a 7th field, their end radius (24 m for
  the ordinary stomp rings). BossView draws the wide ones with a constant band width and a 1.4 m glowing wall, dust
  thrown up where it is nearest you, a ripple running ahead and a rumble (whoosh + slam) timed to its arrival.
- Level up (v0.12.0, `MagicFx._level_up`): the light column is a child of the player's avatar, so it rides along for
  ~2.2 s and fades over 1.4 s (with its own light).
- Storm Altar button (v0.12.0): a solid drum (`WorldLayout.ALTAR_BTN_R` 2.6 m, top at `ALTAR_UP` 0.6 m, `ALTAR_DOWN`
  0.2 m while pressed) for players at level 3 (`Sim._collide_altar`: land on its top, pushed out of its side; the
  same in client prediction). Only landing on top summons Thunderhorn (`Net._server_altar` checks the feet are up on
  it). `WorldLayout.altar_pressed` (server: boss present or the defeat screen; clients: from the boss state) holds it
  down for the whole fight; ArenaView sinks it with a clunk, dust and a flash and lets it rise slowly afterwards.
  Test: npc_test `_altar_button`.

## Thunderhorn anatomy (v0.12.0)

- Bones (`BossModel.BONES`, model space before `S` 0.85, forward -Z): spine `hips` (pelvis), `loin`, `back`, `chest`
  (withers and the shoulder hump), `neck0`, `neck1`, `head`, `jaw`; front legs `s` (scapula), `u` (shoulder), `e`
  (elbow), `c` (carpus, folds backwards), `f` (fetlock), `h` (hoof); hind legs `u` (hip), `k` (stifle), `c` (hock), `f`,
  `h`; tail `t0`..`t7`. The trunk's cross sections (`SECTIONS`: z, y, half width, up, down, keel, ridge) are squarish
  super-ellipses narrowing underneath and on top, plus Gaussian muscle masses (`BUMPS`): shoulders, triceps, brisket,
  haunches, neck crest, cheeks, a thick dewlap. A separate lower-jaw tube really opens (throat, molars, spade incisors,
  cracked fangs, lower tusks, tongue).
- IK (`BossModel._leg_ik`): BossView gives each hoof a target (`t`, model space) or an offset from the leg's root in
  model axes (`rel`, blended by `k`), plus `flex` (carpus / hock fold) and `curl` (hoof flip). Abduction tilt about Z,
  a two-bone solve with a virtual lower bone whose length follows the fold, the pastern at its standing angle to the
  ground, the hoof flat. Knees bend the bovine way by construction (bend sides taken from the rest pose).
- Gaits (`BossView.GAITS`, `_locomote`): walk 4-beat lateral (LH 0, LF .25, RH .5, RF .75; duty .66; 4.2 m stride at 6
  m/s), trot diagonal pairs (duty .45), transverse gallop (LH 0, RH .11, LF .36, RF .48; duty .30, suspension). Planted
  hooves stay fixed in the world; swings land at the predicted spot (speed and turn rate); corrective steps when
  standing. Body: head bob, hump roll, gallop pitch rocking / spine flex / surge, lean into turns, a damped momentum
  spring, braced skid with dust (also on `boss_skid`), rear (forelegs striking, slam on the way down), jump (hop,
  Storm Leap), buck (on `boss_snort` while idle / walking / turning).
- Face: brows (`brow` -1 furrowed .. 1 lifted), upper lids (`lid`, blinks), pupils tracking `extra[4]`'s avatar, head
  turning toward it, flaring nostrils, steam breath (`breath()`, a pool of 20 billboards, `STEAM_SHADER`), `tongue`.
- Horns: span about 6.5 m, out from a 0.66 thick base then forward and up to points about 5.2 m ahead of his centre;
  growth-ring ridges, chips and a crack groove in the mesh (`_horn_mesh`, parallel-transport frames, UVs), `HORN_SHADER`
  (weathered base, black polished tips glowing white-hot, crack veins brightening with `hot` and `crack`); a smaller
  second pair and brow spikes; a third, rhino-like spike out of the nose ridge pointing along the snout (about 13
  degrees up): a lance when his head is down in the charge, rush and gore. Trails from every tip (`horn_*`, `horn2_*`,
  `spike`). A charge or rush hit (`boss_launch`) shows an impale-and-toss head heave with a burst at the spike's tip.
- Hitboxes scaled to the horns (`boss.gd`): gore `RADIUS + 4.6` (was 3.4) and facing dot > 0.25 (was 0.35); charge
  `RADIUS + 1.4` (was 0.9) for players and trampled bystanders, golems `RADIUS + 1.2` (was 0.7); rush `RADIUS + 1.3`
  (was 0.8); plus the nose spike: `Boss._on_spike(d, dir)` hits within `SPIKE_R` 1.4 m of a point `HORN_REACH` 5.6 m
  ahead along his facing (charge, rush, gore).
- Tools: `tools/boss_pose_shots.gd` (`model`: still poses and face close-ups; `gait`: 8-frame strips per motion
  through a real BossView), `tools/boss_anim_review.gd` (every motion in slow motion under an orbiting camera with
  labels; records with `--write-movie`, writes `segments.txt`).
- `boss_pose_shots.gd dazed` (v0.12.0): the stun meter's 7 s daze as an 8-frame strip (run with `--fixed-fps 60`).

## Thunderhorn: stun meter, dodging, horn beam (v0.12.0, Group B)

- Stun meter (`Boss.stunned`, `_daze`, `S.DAZED`; replaces "stuns only stagger, shorter each time"): each wand Stun
  that catches him adds 1 (`stun_m`); at `STUN_NEED` 7 (Jacob) he is dazed for `STUN_TICKS` 420 (7 s). The meter holds
  `STUN_HOLD` 180 ticks (3 s) after a hit, then drains a point every `STUN_DRAIN` 90 ticks (1.5 s); it stays full while
  he's down and empties as he gets up. Dazed: normal damage, no attacks, no static field, no moving, no big-hit
  stagger. It interrupts anything: a charge or the rush stops dead (with a skid), the beam goes out, a howl stops
  launching orbs; filled while he's in the air (`daze_pending`) he lands (the landing ring still goes out) and drops,
  and when he gets up the rest of the Storm Leap sequence is dropped: back to his normal attacks. It is the only way
  to stop a charge or the rush now: frost no longer slows them (they ignore `slow`). Synced: `extra[8]` (the meter,
  0..7) and status bit 64 (dazed). BossView: a thin gold bar under the health bar with a notch per hit and
  "STUN n/7" (flashing "DAZED n s" while down), a toast two and one short, a "THUNDERHORN IS DAZED!" banner, then the
  animation (`S.DAZED` in `_process`): a stagger, the legs buckle (`crouch` 2, legs tucked, rolled onto his side),
  head low and swaying, lids drooping, tongue out, a ring of stars and gold sparks round his head (`_update_daze`),
  then 1.3 s of struggling up, and he shakes it off (a body shake, snort and spark burst). Fx: `boss_stun_hit` [pos,
  meter], `boss_dazed`, `boss_get_up`. Stuns while he's down don't count.
- The meter's math (Jacob: stunning him consistently must fill it): the wand's Stun recharges in 300 ticks and casts in
  26, so one player lands one every ~5.4 s. The hold is `Boss.stun_hold_ticks()` = that recharge + cast +
  `STUN_MARGIN` 150 = 476 ticks (7.9 s, read from `Weapons` so it follows the spell), then `STUN_DRAIN` 360 (a point
  per 6 s). One player on cooldown: dazed after 32.6 s; missing every 4th cast: 48.9 s; two wand players: 16.3 s.
- Dodge audit: every attack has a tell of at least `MIN_TELL` 0.4 s (`Boss._wind(base)`), and a dash's i-frames
  (`dash_ticks`) cover every one of his hits (`Boss._dodging` drops the hit, launch and zap and shows "Dodged!";
  orbs and ball lightning fly through a dashing player). Changes: gore wind-up 26 -> 32 ticks, tail 24 -> 30, stomp
  40 -> 48, beam 45 -> 60, a follow-up charge at least 0.5 s; the roar lands at `ROAR_AT` 45 ticks (was 15) and
  reaches `ROAR_R` 12 m (slow; was 16) / 10 m (static; was 13); the stomp's slams are `STOMP_EVERY` 52 ticks apart at
  one speed `STOMP_V` 9.5 m/s (they were 0.4 s apart and faster each time, so at some distances a ring came just as
  you landed from jumping the last: an impossible chain); homing orbs commit within `ORB_COMMIT` 5 m (they stop
  steering, so a sidestep beats them); the SLAMS rear-up is timed to each wave (0.5 s before it); frost no longer
  slows charges. Per attack, tell (calm / enraged with two players), the skilled bot's avoidance and an idle
  player's hit rate (boss_test `_dodge_tests`, 24 trials each, half enraged):

  | attack | tell | answer | skilled bot avoided | idle hit |
  |---|---|---|---|---|
  | charge (double/triple) | 0.83 / 0.47 s | side-step, dash across | 100% | 100% |
  | rush | 1.60 s pawing | side-dash | 100% | 100% |
  | gore | 0.63 / 0.50 s | back off + dash | 100% | 100% |
  | tail lash | 0.65 / 0.55 s | back off + dash | 100% | 88% |
  | stomp rings | 0.80 / 0.45 s, then 0.87 s apart | jump on the beat | 100% | 100% |
  | slam waves (leap) | 0.5 s rear each | jump on the beat | 100% | 100% |
  | horn beam | 1.00 / 0.57 s | out of reach, or dash through | 100% | 79% |
  | called lightning | 1.33 s circles | leave the circle | 100% | 100% |
  | ball lightning | 0.33 s (slow drifters) | outrun | 100% | 100% |
  | roar | 0.75 s | back off past 12 m (or shield) | 100% | 100% |
  | leap landing + ring | 1.5 s marker | leave the marker, jump the ring | 100% | 100% |
  | homing orbs (per orb) | 0.5 s launch | keep moving across them, dash late | 95% | 100% |
- Horn beam (`scripts/horn_beam.gd`, `HornBeam`, owned by BossView; Jacob's addenda): in BEAM_WIND two thin feeder
  beams shoot (0.2 s) from the curved side horns' tips (`anchors.horn_l/r`) and meet just ahead of the nose spike's
  tip, where an orb forms: a white core in a cyan glow (`BEAM_SHADER`, additive, falling off from the centre line,
  packets flowing along it) with three rings spinning on different axes, crackling, growing (`1 - e^(-2.6 t)`) and
  pulsing faster as it charges: its growth is the telegraph (wind-up 1.0 s calm, 0.57 s at the shortest). In BEAM the
  main beam fires out of the orb, which stays as the emitter with a billboard muzzle flare: a hot white core (r 0.2), a
  cyan glow (r `Boss.BEAM_R` 0.75: the hitbox's radius) and a faint halo (2.2x), width and brightness pulsing, the core
  jittering, packets flowing out, tendrils spiralling off (helical ribbons), three lights (orb, middle, impact), the
  feeders still pumping; at the ground end sparks, smoke and a glowing scorch trail (additive marks cooling from
  white-cyan to orange to nothing over ~2 s, plus ragged scorch). After it everything collapses with a pop. Red-shifted
  when he's enraged. Sounds (`Synth.fx`): "beam_hum" (the rising charge whine), "beam" / "beam_long" (1.6 / 2.75 s
  crackling roar with a warble), "pop".
- Beam geometry = hitbox (`Boss.beam_ends(at, heading, body_yaw)`, `beam_hits`): the orb sits `BEAM_ORB` 7 m out and
  `BEAM_ORB_Y` 3.9 m up along where his head points (`BEAM_HEAD_K` 0.6 of the way from his body's heading to the
  beam's: the neck turns the head; measured 0.8 m ahead of the spike's tip), the beam slants down to the ground at
  `BEAM_REACH` 24 m along the beam's heading; a player (capsule 0.4-1.4 m up, r 0.4) touching that segment within
  `BEAM_R` is hit (every 6 ticks). So under the orb close in it passes over your head, near its far end you can jump
  it, and past 24 m it never reaches. BossView turns the head with the beam (head yaw = the full beam offset, eased at
  45/s while firing) and HornBeam follows the server's heading eased at 45/s.
- `tools/boss_beam_shots.gd`: the whole sequence at dusk through a real BossView (stills, or a clip for the movie maker).


## Wand spells: Spark Beam, Fog, Life Drain (after v0.12.0)

- Wand spell set. Earth Spikes are gone everywhere (weapons, `CastPose`, `MagicFx`, `Net._cast` / the
  "spike" pending spell, NpcAI, Thunderhorn's weakness and charge stop, docs, tests). The wand is now (slot: name,
  level, recharge): 0 **Spark Beam** L1 1 s; 1 Golem L1 10 s; 2 Teleport L1 4 s; 3 Stun L1 5 s; 4 **Fog** L2 18 s;
  5 **Life Drain** L3 3 s; 6 Gravity Well L3 15 s; 7 Stone Titan L4 60 s. R cycles the unlocked ones (the HUD shows four a
  row). `Sim.PlayerState.recharge` has 8 slots and `Codec.RECHARGES` (8) sends them all (83 bytes a player). Code
  names spells instead of slots: `Weapons.idx(w, name)`, `spell_named`, `spells_at(w, level)` (the level-up banner
  names every spell of the level, "A & B"); Net, Main's bots and the tests use names.
  - **Spark Beam:** windup 5, cast 14, damage 7, knock 1, range 30. `Net._beam_target(p, from, aim, reach)`: the first
    enemy player, other summoner's golem (via `_stun_target`), practice dummy or Thunderhorn along the line, walls stop
    it. Event `spark` [id, hand, end, hit]: `MagicFx._spark` (a thin white-blue jagged line gone in ~0.14 s, sparks, two
    small lights).
  - **Life Drain:** windup 12, cast 30, damage 18, `drain` 0.45, range 18. `Net.last_dealt` (set by `_damage`: what the
    target really lost, 0 if a shield soaked it all) -> `Net.drain_heal(dealt, k)` back to the caster. Event `drain`
    [id, hand, target point, heal]: `MagicFx._drain` (a crimson jagged stream, nine red/green motes flying from the
    victim into the caster's wand, following them, "+N" in green).
  - **Fog** (`fog.gd`, `Fog`, pure statics; `fog_view.gd`, `FogView`): `Net.fogs` holds records (`Fog.make`: id,
    centre, caster, t0, `duration` 600, `fade` 120, `half` 12.5, a drift direction from the id); the `fog` event
    (`Fog.to_args`) gives every client the same record; pruned when over. `covers` (the 25 x 25 m square, -3..+7 m
    high, while density >= 0.12), `density` (1, then down over the last 2 s), `centre` (drifts 1.5 m/s while fading),
    `half_now` (spreads 15%). Sides like `Net.can_hurt` (`enemies(a, b, pvp)`; ids from `Fog.NPC_ID0` are challengers
    / minions; golems pass their summoner): `friend(f, who)` = the caster or anyone they can't hurt. `impair`,
    `view_for(viewer, pos, fogs, tick, pvp)` -> {impair, see_through, inside}, `look_for(viewer, vpos, side, pos, ...,
    is_self)` -> `Look.NORMAL / OUTLINED / HIDDEN`, `can_see` (NPC brains, golems), `lost`, `steer` (walk round a
    cloud's edge, a steady side choice), `overlap_at(pos, fogs, tick, pvp)`: clouds from OPPOSING casters overlapping
    there (Jacob): everyone inside that overlap is blind, both sides, and no outlines there (none on anyone in it, none
    seen from it); same-side overlaps change nothing. Thunderhorn has no fog code. Net: `fog_pvp()`; NpcAI:
    `_confused` (`fog_mode` "thrash": swing / shoot / spark at a random spot 1-4 m off every 0.5 s; "stumble": walk on
    a jerking heading), re-picked every `FOG_ROLL` 120 ticks, `FOG_RECOVER` 60 ticks after getting out; `_pick_target`
    skips anyone it can't see; moves pass through `Fog.steer`. Golems: `fogs` / `fog_pvp` set by Net each tick,
    `_confused` (thrash = a slam at the air, stumble), `_pick` skips hidden targets, walking is steered round.
    FogView (Main calls `update(delta, avatars, golem_view, cam)` after placing the avatars): 108 billboard puffs per
    cloud (3 layers of 6 x 6, a generated noise texture), alpha 0.8 x density for those it hides from, 0.12 for the
    caster's side, billowing out over 0.5 s; avatars and golems that are HIDDEN are made invisible (names and bars with
    them); OUTLINED gets a rim-light `material_overlay` (red on enemies, cyan on yourself; depth test off, so it shows
    through everything) on every mesh of the figure or golem, or for Pip a twin Sprite3D with a shader that grows his
    sprite's alpha by ~2.5 px in flat glowing colour, drawn just behind him; blind (impair > 0): a full-screen quad on
    the camera reading the depth buffer, fogging by distance from the player's body (1.6 -> 3.2 m), washing colours
    out and darkening the edges, easing in fast and out over `Fog.CLEAR` (0.5 s); the crosshair is UI and stays.
    Demo bot: `--bot fog` (Main `_bot_fog`). Tests: `tools/fog_test.gd`, magic_test additions.
- Life Drain on an ally (v0.12.0, Jacob): if the first body along the beam is an ally (a player the caster can't hurt,
  or the caster's or an ally's golem: `Net._ally_on_beam`), nobody is hurt; the ally is healed `ally_heal` (12) through
  `Net.heal_target` (players and golems, never past full) and the caster gets nothing. Event `drain_ally` [caster,
  hand, point, healed, target]: `MagicFx._drain_ally` (a green-gold stream from the wand into them, motes, "+N" on
  them). Same 3 s recharge. Challenger wand wizards don't have Life Drain (it's level 3; their kit is level 1).
  Test: fog_test `_spells`.
- Challenger wizards (v0.12.0, `npc_ai.gd`, the WIZARDS block). Kit: `NpcAI.kit(w)` = the weapon's level-1 spells
  (staff: Lightning, Fireball, Shield; wand: Spark Beam, Golem, Teleport, Stun); the basic attack is Fireball / Spark
  Beam. Mana: no bypass was found (the staff's mana always went through `Sim.step`); what looked infinite was a cast
  as soon as it could afford one. Now below `LOW_MANA` (22) it rests (backs off 5 m further, strafes, no casting)
  until `REST_MANA` (55). Choice: `_utility` -> `_score` per ready spell (`_ready_to`: the game's recharge / mana and
  its own `SPELL_CD`): Lightning 1.0 (+0.6 at a still target, +0.5 per player near the target, -0.6 under 5 m),
  Fireball 1.1 (+0.4 at 5-20 m, -0.3 at a fast target, +0.3 a crowd), Shield 2.5 with shots coming (+0.6 low health
  up close), Spark Beam 1.0 in range, Golem 1.3 (0.4 with two out; +0.4 low health) under 22 m, Teleport 2.6 under
  4 m (1.4 low health under 8 m), Stun 0.9 (+0.7 at a runner, +0.5 if they're attacking or drawing); x0.6 if it would
  leave under 10 mana; x`REPEAT_K` (0.5) per use among the last `REPEAT_WINDOW` (4); 0 after `MAX_SAME` (3) in a row
  (`_run_of`, also for the reactive shield); x random 0.75-1.25. Reactive shield: a shot about to hit, or (new) a bow
  or slingshot drawn at it past 20 ticks (`_threat`); it drops a wind-up for it. Aim: `_track` follows the target's
  current position with a lag (`TRACK` 0.08 a tick; no lead), plus an error picked at the wind-up (`WIZ_ERR`
  0.09/0.07/0.055 rad at 10 m, x(0.6 + d/25), x(1 + speed/4, at most 2.5), x1.8 if dashing), turned round the caster
  and short/long. Tell: `WINDUP` 34/26/20 ticks planted and facing them (event `npc_tell` [id, spell, ticks]:
  `MagicFx._npc_tell`, a swelling light in the spell's colour and motes at its hand), then the cast, then `PAUSE`
  50-90 / 35-70 / 25-55 ticks. `casts` lists what it cast. Melee keeps `AIM_ERR`; wizards don't use it any more.
  Mana bar: `Avatar.mana_bars` / `show_mana` (a blue bar under the health bar, flashing when low) for challengers
  (`npc`, set by Main from the id) holding a mana weapon, in both the Pip and figure views. Test: `tools/wizard_test.gd`.
- Challengers learn to dash (v0.12.0, `npc_ai.gd`): `_threat` also reports area spells about to land on them (the
  warning ring of lightning, a meteor, a storm bolt or Thunderhorn's called lightning within its radius + 0.8 m,
  `pending_spells`; never a fellow challenger's) and Thunderhorn winding up or running a charge / rush down a line
  through them (ahead within 28 m, within his radius + 1.6 m of the line); `threat_kind` says which ("shot", "draw",
  "melee", "spell", "charge"). For spells and charges: noticed after REACT/2 + `SPELL_REACT` (10/6/3) + random ticks,
  then a side-dash away with `SPELL_DODGE` (0.12/0.4/0.65) by tier. Measured (dodge_test): lightning rings 7% / 42% /
  73% after ~24 / 15 / 8 ticks; charges 12% / 37% / 70%. `dodges` counts them. Archers and slingers (v0.11.0)
  verified unchanged: no lead (`_lead(..., 0.0)`), `SHOT_ERR` 0.1/0.075/0.055, `SHOT_START` 0.02/0.028/0.036,
  `SHOT_HOLD` 32/24/16. Test: `tools/dodge_test.gd`.
- Heal Aura (v0.12.0, Jacob; the staff's second level-3 spell, after Meteor; the staff is now Lightning, Fireball,
  Shield, Frost Nova (L2), Meteor (L3), Heal Aura (L3), Arcane Storm (L4)). `channel: true`, `drain` 1 fifth a tick
  (12 mana a second), `radius` 7, `every` 30, `heal` 4 (8 a second). `Sim._combat`: held with the mana for a tick, it
  keeps `atk` at 2 (so no mana comes back and the pose holds; the first tick is `Ev.CAST` and a new `swing_n`); let go
  or dry, `atk` runs out and `atk_cd` = its cooldown (20). `Sim.channeling(s)`. `Net._server_heal_auras` (each tick
  after the spells): `heal_aura_targets` = the caster and living allies (players the caster can't hurt; never
  challengers) within 7 m, flat; the first tick and every 30 after (`ServerPlayer.heal_t0`, `heal_last`) each hurt one
  gains up to 4 (event `heal_pulse` [caster, pos, radius, [[id, gained]...]]); with nobody in reach hurt the server ends
  the channel (`atk` 0, cooldown; event `heal_stop`) - the caster's client sees that as a small correction. Looks:
  `CastPose` style "raise" (staff high overhead, swaying, the orb glowing; both views use the shield's raised pose);
  `MagicFx._heal_pulse`: a green ring spreading to 7 m, gold motes over the staff, green and gold motes rising from
  each one healed, "+N" over them, and `Synth.fx("heal")` (a soft shimmering major-triad chime) each pulse, within
  30 m. Challenger wizards never have it (level 1 kits). Test: `tools/heal_test.gd`.
- Challenger tiers (v0.12.0, Jacob: every challenger used to be difficulty 1). `ServerPlayer.duel_wins` counts the
  challengers a player called that went down (`Net._damage`); `Net.duel_tier(wins, level)`: tier 1 (NpcAI difficulty
  0) at first, tier 2 after `TIER2_WINS` (3) wins or the staff / wand at level 2, tier 3 after `TIER3_WINS` (8) or
  level 3; `_stone_interact` passes it to `spawn_npc`, and the name tag reads "Challenger Morwen (tier 2)". Dash-dodging
  now starts at tier 2: `DODGE` 0 / 0.6 / 0.85 and `SPELL_DODGE` 0 / 0.4 / 0.65 (dodge_test now measures ~0% / 30% /
  58% out of lightning rings, 0% / 27% / 50% out of a charge); aim (`SHOT_ERR`, `AIM_ERR`, `WIZ_ERR`) tightens, draws
  (`SHOT_START`) come faster and reactions (`REACT`) quicker per tier, as before. Test: npc_test (a run of nine duels
  goes tier 1, 1, 1, 2, 2, 2, 2, 2, 3).
- NPC wizards' golems (v0.12.0, Jacob): challenger / minion wand wizards summon golems (Golem is in their level-1
  kit) but never more than `NpcAI.MAX_GOLEMS` (3) of their own alive at once (`_score` gives Golem 0 at 3). Their
  golems fight players whatever PvP says, and players' golems (`Golems.foe`: an NPC's golems fight Who.PLAYER only;
  players' golems always fight Who.NPC and Who.BOSS and those enemies' golems). Killing one gives no level credit
  (golem kills never call `_magic_kill`). Chosen: they DISSOLVE when their wizard falls (`Golems.dissolve(owner)` from
  `Net._server_npcs` as soon as the wizard is down: they crumble). Test: wizard_test `_npc_golems`.
