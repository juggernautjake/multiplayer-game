# Multiplayer Game: foundation

A 3D online multiplayer game in **Godot 4** (GDScript). This first stage is the foundation everything else stands on:

- a server that several people can join (or a host who plays and serves at once; solo is just hosting alone);
- an open plane in 3D with solid pillars and steps to jump on (collision is part of the shared simulation), each player a simple character with a name;
- movement: WASD, sprint (Shift), jump (Space), dash (Q, the first ability: predicted, with a cooldown);
- camera: third person or first person (V), mouse-wheel zoom, crosshair;
- netcode built for fast action, with no lag felt on your own moves and no rubber-banding.

## Getting started

1. Download **Godot 4.7** (standard, not .NET) from <https://godotengine.org/download>. It's a single program, so no
   install is needed: unzip it anywhere.
2. Open Godot, choose **Import**, and pick `dev/multiplayer-game/project.godot`.
3. Press **F5** (Play). In the menu:
   - **Play solo / Host** starts a game on your PC that friends can join. The screen shows the addresses to give them.
   - **Join**: type the host's address, then Join.

To test two players on one PC, go to **Debug → Customize Run Instances**, set 2 instances, and press F5. Host in one
window and join `127.0.0.1` in the other.

## Playing with a friend

The host's PC listens on **UDP port 7777**.

| Where your friend is | What to give them |
|---|---|
| Same Wi-Fi / LAN | your LAN address, shown on screen (e.g. `192.168.1.23`) |
| Over the internet | your public IP (search "what is my IP"), after forwarding **UDP 7777** on your router to your PC |
| Over the internet, no router changes | both of you install [Tailscale](https://tailscale.com) (free), then give your Tailscale address (`100.x.y.z`) |

The first time you host, Windows Firewall asks whether Godot (or the exported game) may use the network. Allow it on
private networks, or friends can't connect.

Later, a Steam build can use Steam's relay network ([GodotSteam](https://godotsteam.com)). Friends then join through
the Steam friends list, with no addresses and no port forwarding.

### Dedicated server

To run a server with no window and no player of its own (for an always-on server):

```
Godot_v4.7.2-stable_win64_console.exe --headless --path dev/multiplayer-game -- --server --port 7777
```

Other options after `--`: `--host`, or `--join <address>`, to skip the menu.

## How the netcode works

| Piece | What it does | Why |
|---|---|---|
| Server-authoritative, fixed 60 Hz | Only the server's simulation counts | Cheating is hard; everyone agrees |
| Shared deterministic `Sim.step` | The same movement code runs on server and client, every value rounded to float32 | Predictions match the server exactly |
| Client-side prediction | Your player moves the instant you press a key | No input lag, whatever your ping |
| Reconciliation | Each snapshot says which of your inputs the server has applied; the client replays the rest from the server's state, and blends out any real correction | No rubber-banding |
| Interpolation | Other players are drawn 100 ms behind, blended between snapshots; brief extrapolation covers a lost packet | Smooth motion, even with jitter |
| UDP (ENet), unreliable inputs and snapshots | Each input packet repeats the last 8 inputs; the server puts late or reordered inputs back in sequence | A lost packet costs nothing; no head-of-line stalls like TCP |
| Compact binary packets | About 9 bytes per input, about 37 bytes per player per snapshot | Low bandwidth: 32 players fit easily |
| Input backlog limit | The server applies at most one input per tick (catching up a little after a hiccup) | Sending inputs faster can't make you move faster |

Files:

- `scripts/config.gd`: shared numbers (tick rate, snapshot rate, interpolation delay, port).
- `scripts/sim.gd`: the deterministic movement simulation: `PlayerInput`, `PlayerState`, `step()`.
- `scripts/codec.gd`: binary packing of inputs and snapshots.
- `scripts/net.gd`: server, client and host logic: prediction, reconciliation, interpolation.
- `scripts/main.gd`: the world, avatars, camera, controls, menu and HUD.

## Roadmap (next foundations)

1. **Collision and physics**: Godot 4.4+ ships Jolt physics. Move the player through a kinematic character controller,
   still stepped in the fixed tick so prediction holds. Physics props stay server-simulated and interpolated.
2. **Abilities and spells**: a data-driven ability system (resources describing cost, cooldown, cast time, effects).
   Casting is predicted on the client (animation and effects start at once) and confirmed by the server. Projectiles
   are simulated by the server and spawned predictively on the caster's client.
3. **Hit detection with lag compensation**: the server rewinds other players to what the shooter saw (keeps a short
   history of states) before testing hits, so aiming feels fair at any ping.
4. **Stats, armour sets, items, skills**: server-owned character data, replicated on change (reliable), not every tick.
5. **Interest management**: only send each client what's near them, for big worlds.
6. **Steam**: GodotSteam for lobbies, friends invites, relay networking, achievements, and the Steam build.
7. **Art pipeline**: characters, animation (synced by state, not by bone), environment assets.

## Tests

`tools/sim_test.gd` checks the shared simulation headless: walking into a step stops beside it, a jump lands on top, walking off falls back down, a dash can't push through a pillar, and identical inputs give identical results.

```
<godot>_console.exe --headless --path . -s tools/sim_test.gd
```

For a live test with scripted players: start a server (`-- --server --port 7789`), then run clients with `-- --join 127.0.0.1 --port 7789 --bot`; each prints its position, the players it sees, its ping and its prediction corrections every 2 s. Add `--screenshot shot.png` (and `--view first`) to save a frame.

## Checking the netcode

`tools/netcode_model.py` (plain Python 3, no packages) models the same rules as `net.gd` over bad connections and
counts how often a client's prediction had to be corrected. Current result: **0 corrections** in two minutes of
play at 30, 80, 150 and 250 ms ping, with up to 80 ms jitter and 5% packet loss. Run it after any netcode change:

```
python tools/netcode_model.py
```
