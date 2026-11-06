# Networking: lag, rubber-banding and Tailscale

Written for v0.8.0 (November 5, 2026), after Jacob and a friend saw lag and rubber-banding playing over Tailscale.
Back to the [docs README](README.md) or the [project README](../README.md#how-the-netcode-works).

## What the game already did (before 0.8.0)

The netcode was already built for internet play (details in the project README, "How the netcode works"):

- **Your own player never waits for the network.** Movement, attacks, draws and casts are simulated on your PC the
  moment you press a key (client-side prediction). The server runs the exact same simulation, and your PC replays
  anything the server hasn't confirmed yet (reconciliation). Real disagreements are blended away over a few frames,
  not snapped; a jump of more than 4 m (a respawn, a teleport) snaps.
- **60 ticks a second, 30 snapshots a second.** Inputs go to the host every tick, each packet repeating the last 8
  inputs, so a lost packet costs nothing. Snapshots and inputs are unreliable UDP (ENet), so one lost packet never
  holds up the next.
- **Other players are drawn slightly in the past** and blended between snapshots. The delay adapts to how unevenly
  snapshots arrive (3 to 20 ticks); a short extrapolation covers a lost one.
- **The host holds a few of each guest's inputs** (a jitter buffer) and applies one per tick. It grows when it runs
  dry and shrinks after 10 s of calm, so guests move evenly on everyone else's screen.
- **A network simulator for testing:** `--netsim <round trip ms>,<jitter ms>,<loss %>` on a client.

## What 0.8.0 changed

| Change | Why |
|---|---|
| **The interpolation delay no longer gets stuck at its maximum.** The "on time" baseline is now the fastest arrival in the last 4 s, not since the game started; snapshots handled right after a local hitch (a frame over 50 ms, such as loading or a first-time shader) are left out; the delay shrinks back twice as fast. | Before, a slow drift between the two PCs' clocks, or a few local hitches, made every snapshot look late. The game then drew other players a full **333 ms** in the past and kept it there. This was the biggest cause of "the others are laggy". It now settles around 70-110 ms. |
| **Golems are drawn on the same clock as players.** Their updates (20 a second) are kept with their server tick and blended at the same moment players are drawn; past the newest one they carry on for up to 0.1 s. | Before, each golem eased toward its newest reported position, which looked floaty and stepped on a jittery link, and didn't line up with the players they were hitting. |
| **Your own fireball leaves your staff at once**, like arrows and stones already did (the server's copy then takes over the same path). | It used to appear a full round trip after the cast. |
| **Projectile and hit messages get their own reliable channels** (6 and 7). | A reliable message waiting to be re-sent (lost packet) holds up everything behind it on its channel. Shots and hits no longer queue behind item and roster updates. |
| **The host's input buffer for each guest starts at 3 ticks** (was 2). | Over the internet it nearly always grew to 3-4 within the first seconds, and each time it ran dry the guest froze for a moment and then hurried on everyone else's screen. |
| **A connection readout on the HUD.** Guests: `link: <round trip> ms, jitter <ms>, loss <%>` and, over Tailscale, `Tailscale: direct` or `Tailscale: RELAYED via DERP <city>`. Host: each guest's round trip, input buffer and how often it ran dry. The ping now includes `--netsim`'s simulated delay. | So you can see what the connection is doing, and whether Tailscale goes direct (see below). |
| **Test flags:** `--give-guests` (on the host: guests start with every weapon, so a guest can be tested casting); the `--bot show` and `--bot golems` showcase bots. | Two-instance testing. |

### Measured (two copies of the game on one PC, the guest with `--netsim`)

| Guest connection | Guest's corrections | Others drawn behind | Guessed (extrapolated) |
|---|---|---|---|
| 140 ms round trip, 30 ms jitter, 2% loss (walking bot) | 0 | about 100 ms | under 1% |
| 140 ms, 30 ms jitter, 2% loss (casting every spell) | 0 | about 109 ms | 2.7% |
| 150 ms, 40 ms jitter, 3% loss | 0 | about 100 ms | under 1% |

The host drew the guest about 67 ms behind; the guest's input buffer settled at 4 ticks. "Corrections" counts
the times the server disagreed with the guest's own prediction, so 0 means no rubber-banding of your own player.
Rubber-banding can still happen when the server really does move you in a way your PC couldn't know about
(knock-back from a hit, a gravity well's pull). That is blended in over a few frames and is expected.

How to repeat the test:

```
Godot --path . -- --host --port 7790 --name Host --bot --give-guests
Godot --path . -- --join 127.0.0.1 --port 7790 --name Guest --bot magic --netsim 140,30,2
```

The guest's `[bot]` / `[magic]` log lines and its HUD show corrections, the delay and the link readout.

## Is Tailscale going direct or through a relay?

Tailscale first tries to connect the two PCs **directly** (peer to peer over UDP). If the routers won't allow it,
traffic goes through one of Tailscale's **DERP relay** servers instead. Relays work everywhere, but they add distance
(the nearest relay city might be hundreds of miles from both of you) and they are shared and rate-limited, so
round trips are longer and much jumpier. Jumpy round trips are what make other players stutter.

**Check it:**

- In the game, a guest's HUD says `Tailscale: direct` or `Tailscale: RELAYED via DERP <city>`. The game runs
  `tailscale ping` itself, every 30 s.
- On either PC, in a command prompt:
  - `tailscale ping <the other PC's 100.x address>`. A reply that ends `via 73.12.34.56:41641` is **direct**; one
    that ends `via DERP(dfw)` is **relayed**. Tailscale often starts relayed and switches to direct within a few
    seconds, so run it 3-4 times.
  - `tailscale status` shows each peer; a peer going through a relay shows `relay "dfw"`, a direct one shows an
    address and port.
  - `tailscale netcheck` shows whether UDP works and what kind of NAT you're behind. `MappingVariesByDestIP: true`
    ("hard NAT") on **both** sides is the usual reason it can't go direct.

**Getting a direct connection:**

1. Make sure both PCs allow Tailscale through their firewalls. It installs a rule for itself; leave it on.
2. On at least **one** of the two routers, turn on **UPnP** or **NAT-PMP / PCP** (router settings, usually under
   "Advanced" or "NAT"). Tailscale uses them to open a path for itself.
3. Or forward **UDP port 41641** on one router to that PC (Tailscale's port). That PC then always accepts direct
   connections. (This is Tailscale's port, not the game's 7777: over Tailscale the game's traffic goes inside the
   Tailscale tunnel.)
4. Avoid "double NAT" (a provider's modem-router plus your own router, both doing NAT). Put the provider's box in
   bridge mode, or forward the port on both.
5. Phone hotspots and some mobile and satellite internet use carrier-grade NAT, which often can't go direct. That
   side can't fix it; forwarding the port on the *other* side usually still allows a direct path.
6. Wired Ethernet beats Wi-Fi for jitter.

**Without Tailscale:** forward UDP **7777** on the host's router to the host's PC and use the "over the internet"
invite code. This is always direct, but it doesn't work behind carrier-grade NAT.

## Ideas for later (brainstorm)

Roughly from most to least worthwhile:

1. **Show the round trip next to each player's name** (from the host's measurements, sent with the roster), so you
   can tell at a glance whose connection is bad.
2. **Predict more of your own actions' effects.** The cast glow, rune circle and fireball are already instant. Next:
   the lightning's warning ring, the teleport's flash and the stun bolt, drawn locally on the cast tick (the
   server's copy then replaces or confirms them).
3. **Lag-compensate spells and projectiles** the way melee already is: test fireball and arrow hits against where
   the shooter saw the target, not where the target is now.
4. **Send golems and items as part of the snapshot** (delta-compressed) instead of separate messages, so they share
   one clock and one packet.
5. **Delta-compress snapshots** (send only what changed). Bandwidth isn't a problem at 2-4 players, but it is for
   20+.
6. **A dedicated server** (below). The biggest win when one player's home upload or Wi-Fi is the weak link, or
   when neither PC should have to stay on.
7. **Steam's relay network** (GodotSteam) for a Steam build: friends join from the friends list and traffic goes
   over Valve's backbone, which is usually better than Tailscale's DERP relays when a direct path isn't possible.

### Would a dedicated server help?

**Sometimes.** Today the host's PC is the server, so the host plays with zero lag and the guest gets the full
round trip to the host's house, through the host's home upload and Wi-Fi. A dedicated server moves the game to a
rented machine in a data center:

- **Better when:** the host's internet or Wi-Fi is the problem (upload, jitter, a busy household); Tailscale can't
  go direct; or you want the world always on.
- **Not better when:** you two live close together on good connections. Each player's round trip becomes "my house
  to the data center", which is about the same as host to guest. The host loses their zero-lag advantage, but it
  becomes fair.
- **Region:** pick the data center roughly between the players. For players in Texas, Dallas is ideal. Chicago,
  Atlanta or Ashburn (Virginia) suit players spread across the US.

**What it looks like:**

- **Machine:** a small Linux VPS (1-2 virtual CPUs, 1-2 GB of memory is plenty for a few players at 60 Hz). Typical
  prices in 2026 are roughly **$4-12 a month**, e.g. Hetzner Cloud (Ashburn and Hillsboro in the US), Vultr,
  DigitalOcean, Linode/Akamai or AWS Lightsail, all with Dallas or nearby options except Hetzner. Check current
  prices and regions. Bandwidth is tiny (well under 1 GB per hour of play).
- **The game:** the server already exists. `--server --port 7777` runs a headless server with no player of its
  own. It needs a **Linux export** of the game (add a "Linux" export preset and install the Linux export template
  in `dev/tools/godot-export`), then copy the build to the VPS.
- **Running it as a service:** a `systemd` unit (`/etc/systemd/system/multiplayer-game.service` running
  `./MultiplayerGame.x86_64 --headless -- --server --port 7777`, with `Restart=always`) so it starts on boot and
  restarts if it crashes. Open UDP 7777 in the VPS firewall.
- **Invite codes:** the server has a fixed public address, so its invite code never changes. Pin it on the menu as
  "Join the server", or give the server a name like `game.example.com` and let the Join box accept names as well
  as codes. It could also join your tailnet (Tailscale on the VPS) and only accept players from it.
- **Updates:** the server must run the same version as the players. Simplest: a small script on the VPS (run by
  `release.sh` over SSH, or by a timer) that downloads the new release's files from GitHub and restarts the
  service. The game could also check for updates at server start the same way players' games do (`updater.gd`).
- **Things to add to the game first:** the host's admin powers (switching everyone's look, PvP rules) need a
  server-side setting or an "admin" player, since there's no host player; plus a player count and server name on
  the menu.

## Where the code is

- `scripts/net.gd`: `_measure_jitter` (interpolation delay), `_server_step_player` (input jitter buffer),
  `_client_tick` (prediction, sending inputs, the predicted fireball), `_client_receive_snapshot`
  (reconciliation), `quality_line`, `check_tailscale_path`.
- `scripts/golem_view.gd`: `_interp` (golems on the players' clock).
- `scripts/config.gd`: tick rate, snapshot rate, redundancy.
- `tools/netcode_model.py`: a Python model of the movement netcode over bad connections.

## 0.8.1

- **Leaving a game now closes its connection** (`Net.shutdown()`): "Leave game" used to rebuild the world without
  closing it, so its UDP port stayed taken and hosting again failed with "port 7777 is being used". Hosting also
  retries the port for about a second if the system is still releasing it. `tools/rehost_test.gd` hosts, leaves and
  hosts again on the same port, has a guest leave and rejoin, and goes host -> leave -> join -> leave -> host.
- **Shots bounce off shields** on the server; the new path goes to everyone (`proj_bounce`, channel 6) and each
  client's copy of the shot follows it.
