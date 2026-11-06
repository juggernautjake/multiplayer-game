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
3. [The Duel Stone, the Storm Altar and Thunderhorn](#the-duel-stone-the-storm-altar-and-thunderhorn)
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

## Magic: the staff and the wand

Two magic weapons, each one of a kind (only one player has each; they go back when that player leaves):

- **The Wizard staff** lies on top of the **wizard's tower**, a spiral of pillar steps 15.6 m up, in sight of the spawn
  (follow the pale beam of light). Every step is one jump from the last. The staff uses **mana** (the blue bar under
  your health; it comes back at 12 a second, but not while you cast or hold the shield).
- **The Magic wand** is hidden in **the vault**, a low stone block far from the spawn: walk round to its far side, open
  the door (E) and take the wand off its shelf. The wand uses no mana: each spell has its own **recharge** instead.

Pick a weapon (6 staff, 7 wand), pick a spell with **R**, hold the left mouse button to cast where the crosshair is.

| Level | Staff (mana) | Wand (recharge) |
|---|---|---|
| 1 | **Lightning** (34): a warning ring, then a bolt from the sky: 28 to everyone in the 3 m strike (0.9.0: no falloff), then it **chains** to the nearest enemy not yet hit within 6 m for half (14, 7, 4), up to 5 jumps; a shield soaks a jump and ends that branch | **Golem** (10 s): a small, fast stone golem (8 m/s, faster than walking, slower than sprinting) that chases your enemies from 25 m and hits on the move; up to 6, loyal to you |
| 1 | **Fireball** (22): a burning orb that bursts on contact: 24 at the centre down to 6 at 3.4 m | **Teleport** (4 s): blink to what the crosshair is on, up to 18 m (five dashes), onto tops or into the air |
| 1 | **Shield** (10, held): hold the button to keep the bubble up (the staff raised overhead); hits on it cost mana (1.5 a point from weapons, 2 from spells, 25 for a stun); out of mana, it **shatters** | **Stun** (5 s): a bolt that bursts in a 2.5 m ring where it lands; everyone caught is held for 3 s |
| 2 (3 kills) | **Frost Nova** (30): a ring of ice from you, 6 m: damage, a shove, and half speed for 2 s | **Earth Spikes** (6 s): stone spikes stab up one after another in a line toward the crosshair |
| 3 (8 kills) | **Meteor** (45): a flaming rock falls where you aim: 40 at the centre down to 10 at 5 m, then burning ground for 3 s | **Gravity Well** (15 s): a vortex that drags enemies within 7 m into its heart for 3 s, then bursts |
| 4, ultimate (18 kills) | **Arcane Storm** (80): a storm cloud rains lightning for 5 s, seeking enemies under it | **Stone Titan** (60 s): one giant golem, 150 health, whose slam crushes everyone round it |

Kills with the staff or wand (with **PvP** on: P) level that weapon up: after 3, then 5 more, then 10 more. Area damage
is always strongest at the centre and falls off toward the edge; you never hurt yourself. Players only hurt each other
when both have PvP on; dummies and golems can always be hit.

**Costumes (0.9.0).** What you wear changes with the weapon in your hand, for everyone to see (it follows the weapon
in every snapshot), with a puff as it swaps: sparkles for the staff and wand, dust for the rest. Each costume has an
accent in your own player colour, so two players in the same costume can tell each other apart.

| Weapon | Costume | Accent (your colour) |
|---|---|---|
| Fists | **Brawler**: a sleeveless leather vest, hand wraps, a sash, a headband (its tails and the sash's ends swing) | headband, sash |
| Sword | **Knight**: a mail shirt, a tabard front and back with an emblem, shoulder guards, a mail coif (the tabard is cloth) | tabard |
| Club | **Barbarian**: bare chest, a fur mantle, a leather harness, a hide kilt (cloth), fur-topped boots | kilt belt (Pip) |
| Bow | **Ranger**: a leather jerkin, a green-brown cloak (cloth), the hood down round the neck, bracers, a quiver | scarf (Pip) |
| Slingshot | **Scout**: a short vest over a white shirt with rolled sleeves, a bouncing satchel, a bandana | bandana |
| Staff | **Wizard**: a long, worn grey robe, a grey cloak, a rope belt, a tall soft pointed hat | hat band (Pip) |
| Wand | **Hooded robe**: one heavy dark robe from a deep peaked hood to the floor, the face in its shadow | trims (Pip) |

On the 3D figure the cloth (robes, cloaks, the tabard, the kilt, tails) is simulated with fixed lengths (it never
stretches, even mid-jump), weight and thickness, kept clear of the legs and arms; sleeves are tubes round the arms with a
bell cuff the hand comes out of. Pip's costumes are painted into his sprite sheets frame by frame
(`tools/make_costumes.py`), with the accent as a second, tinted sprite over him.

**The shield (0.8.1).** The bubble pours out of the staff's raised orb and covers you head to foot. It's a
see-through force field (it bends what's behind it a little, with a glowing rim and a shimmer), and arrows, stones and
fireballs **bounce off it**: the holder pays mana as before, and a bounced shot can't hurt them; a fireball bounces
once, then bursts on its next contact, never inside. Every hit sends a ripple across the dome from where it struck,
as big as the hit. Out of mana, it still shatters and lets the rest through.

**Pip carries his weapon (0.8.1, fixed in 0.9.0).** The sword, club, bow, slingshot, staff or wand is in his hand in
every frame and every direction, beside him and in front of him (from behind too), the staff rising above his head;
the attack frames already show the weapon.

**How it looks (0.8.0).** Every spell has its own casting gesture (a pull-back and thrust for the fireball, the staff
raised to the sky for lightning, driven into the ground for the frost nova, the wand circling over the ground to
summon) with a rune circle turning under you as it builds. Fireballs churn and flicker in flight and no two
explosions or lightning bolts look alike (bolts branch, strike several times, crawl over the ground and boom with a
shake that fades with distance). Golems spread out round a target, leap at it from a few metres, alternate overhead
slams and haymakers, and stand guard round you when there's nothing to fight.

## The Duel Stone, the Storm Altar and Thunderhorn

New in 0.10.0: things to fight that fight back, a boss, and a prize.

### How to unlock everything

1. **The Duel Stone** stands in open ground east of the spawn: a rough standing stone carved with glowing runes. Walk
   up to it and press **E**: a challenger steps out to fight you. At first they come with a bow, slingshot, sword or
   club. You get one challenger at a time; pressing E again while yours is still standing just says "Defeat your
   challenger first".
2. **Wizards:** once you level up your staff or your wand for the first time (level 2), the stone's runes turn violet
   ("The Duel Stone now summons wizards!") and it summons staff and wand wizards too. A wizard is never a higher level
   than you.
3. **Kills on challengers count toward your levels** exactly like kills on other players (golem and titan kills still
   never count). So the stone is the way to level up alone.
4. **The Storm Altar** lies at the far end of the field (north of the spawn): a ring of dark stone round a huge round
   button. It stays sunk into the ground until you reach **level 3** with the staff or the wand; then it rises, crackles
   and a little storm turns over it ("The Storm Altar has risen!").
5. **Jump onto the altar** (land on the button from a jump) to summon the boss, **Thunderhorn**.

Challengers wear the enemy red, have a name tag ("Challenger Brutus") and a health bar, never run out of arrows or
rocks, and can hurt you and be hurt whether PvP is on or off. Their fighting style depends on their weapon:
swordsmen and clubbers keep a striking distance, strafe, dodge (not every time), feint, punish you while you recover
from a swing, and back off when hurt; archers and slingers keep their distance, lead their shots at you when you move
and back away when you get close; wizards shield, use area spells, blink away when cornered, summon golems (wand) and
follow a stun with something heavy. They're medium difficulty by default.

### Thunderhorn, the storm bull

A giant bull of dark storm cloud (v0.11.0: about three and a half times your height, a sculpted, skinned creature with
a churning storm hide, glowing veins and a lightning skeleton that pulses as he attacks, obsidian horns and hooves, a
spiked tail, a mane of storm smoke, a scowl and bared teeth). Glowing trails stream from his eyes, and from his horns,
hooves or tail while they attack, in the attack's colour. Clouds gather, he comes down in a lightning strike, slams
the ground and roars. His health bar (with his status, and gold ticks where Storm Leaps are guaranteed) is at the top
of the screen.

**Health:** 7000 alone, x1.7 with two players (11 900), +0.7x for each player after that (`Boss.hp_for`); someone
joining mid-fight adds health in proportion. At a level-3 wizard's realistic ~15 damage a second (dodging half the
time) that is a fight of about 8 minutes alone.

He moves like a hunting animal between attacks: circling you, backing off, pouncing hops to a new spot, snapping round
with stamping hooves, short feint lunges, snorting and shaking his head.

His attacks, and how to see them coming:

| Attack | The warning | What to do |
|---|---|---|
| **Charge** | He lowers his head, scrapes a hoof; a path glows on the ground | Step sideways at the last moment; enraged he may charge twice, in the storm three times |
| **Stomp** | He rears up on his hind legs | Jump the rings that roll out over the ground (enraged: four slams, the last a double ring) |
| **Horn beam** | His horns light up, arcs jump between them | The beam sweeps the ground in front of him (enraged: back and forth): get behind him, or shield |
| **Called lightning** | He bellows at the sky | Circles appear under you: keep moving (in the storm the bolts walk at you in a line) |
| **Roar** | He snorts and throws his head back | Close to him it slows you (enraged: and adds a stack of Static); a shield blocks it |
| **Ball lightning** | His head dips and the air flashes | Balls drift after you (enraged: five violet static balls, each a stack of Static) |
| **Gore** | Head low, swung to one side | Don't stand in front of his face |
| **Tail lash** | His body coils, the spiked tail lifts | Don't stand at his flank or behind him |
| **Static field** | Always on: sparks round his hooves | A small shock twice a second right next to him |

**Static:** his violet attacks charge you up. A Static bar fills above your health bar (and over the heads of other
players): one segment a hit. Six hits (five while he's enraged) and you're **stunned for 7 seconds** (sparks, stars,
dizzy). The bar holds 2.5 s after a hit, then drains a segment every 3.3 s. A held shield blocks the orbs (no stack).

**The Storm Leap** (2 to 5 times a fight; always as he falls past 80%, 55% and 30% health, and up to twice more if
you're doing too well):
1. He crouches, lightning gathers, a gold marker glows where he will land, far across the arena.
2. He leaps across the arena. Landing sends out a **low gold ring: JUMP it**.
3. A long howl: 10 homing static orbs (15 with two players, +5 a player) fly out of his back and chase you. They turn
   slowly and speed up: sprint, change direction sharply and dash past them, put a pillar between you, or shield.
4. Three ground slams: **jump three rings** in a row.
5. He paws the ground, locked on the nearest player ("HE'S COMING FOR YOU"), and **rushes**: **dash sideways** as he
   comes. If he hits you, you're thrown across the arena and knocked down for a couple of seconds, then get up.

**Phases:** below half health he stops and transforms ("THUNDERHORN IS ENRAGED": red-white light cracks open across
his hide, faster, shorter wind-ups, variants); below a quarter "THE STORM BREAKS" (the storm swirls round him and
lightning keeps falling).

His weaknesses (and resistances):

- **Earth Spikes** do half again as much damage and **stop a charge dead** (he staggers).
- **Meteors** do half again as much damage.
- **Fireballs** set him burning.
- **Frost Nova** slows him a lot.
- **Stuns** only stagger him, and shorter each time.
- **Lightning** does only a quarter of its damage: he's made of it. A gravity well can't move him.
- He can't be hurt while he comes down. The Storm Leap shrugs off staggers, except that Earth Spikes stop the rush.

### Winning and losing

- **Win:** confetti, "CONGRATULATIONS!", then the prize. Press any key to move the words along and, at the end, to
  close the prize.
- **Lose:** if everyone fighting him is down at the same time (alone: if you die), he leaves and you see "Awww, you
  didn't get the final prize! And you died! Better luck next time..." with a sad trombone. Press any key: everyone is
  back at the spawn with full health, **keeping their weapons and levels**, and the altar is ready to try again.

### The prize picture

The prize is a fiesta for Smiguel el Magnifico (ported from Jacob's 4X game). His picture is **not** part of the game
or its releases: the game looks for `smiguel_el_magnifico.png` in a folder called `prize` next to
`MultiplayerGame.exe` (or in `prize\` in the game's user folder, `%APPDATA%\Godot\app_userdata\Multiplayer Game\prize\`).
Without it, a drawn stand-in (a huge sombrero and a grand moustache) takes his place.

### Credits

Music in the prize: "Mariachi Snooze" Kevin MacLeod (incompetech.com), licensed under Creative Commons: By Attribution
3.0, https://creativecommons.org/licenses/by/3.0/ (`assets/audio/mariachi.mp3`, see
[assets/audio/MARIACHI_CREDITS.txt](assets/audio/MARIACHI_CREDITS.txt)). The credit is shown on the prize screen.
Thunderhorn's roars, the thunder, the trumpet, the maracas and the sad trombone are made by the game itself
(`scripts/synth.gd`).

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

**Lag or rubber-banding?** Look at the line under the HUD: a guest sees the round trip, jitter, packet loss and
whether Tailscale goes **direct** or is **relayed** (slower). [docs/networking.md](docs/networking.md) explains how to
get a direct Tailscale connection, what 0.8.0 changed and the ideas for later (including a dedicated server).

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

0.8.0 fixed the interpolation delay getting stuck at its 333 ms maximum (a slow clock drift or local hitches made
every snapshot look late), drew golems on the players' clock, made your own fireball appear at once, gave projectile
and hit messages their own channels, and added the connection readout. Measurements and Tailscale advice:
[docs/networking.md](docs/networking.md).

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
| `<godot> --headless --path . -s tools/boss_test.gd` | v0.11.0: Static (a stack a hit, holds, drains, 7 s stun at 6, 5 enraged, shield blocks, synced), homing orbs (count by players, even split, dodgeable), 2-5 Storm Leaps a fight 25 s apart, jumping the landing ring, the rush (side-dash dodges; otherwise thrown, knocked down, up again), fair targeting. |
| `<godot> --headless --path . -s tools/npc_test.gd` | v0.10.0: who the Duel Stone summons before and after the first level-up, one challenger at a time, challengers hurt and are hurt whatever PvP says, kills on them level the staff, a swordsman closes in and an archer leads its shots, Thunderhorn's health with two players, what each spell does to him, victory, and defeat then restart (alone and with two players, levels kept). |

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
| `--bot show` | Showcase (host with `--give-staff`, `--give-wand` or `--give-all`; add `--style figure` for the 3D figure): runs toward the camera, strafes, backpedals, dashes, jumps, swings the sword and casts with the staff or wand while the camera circles, saving a picture every 6 ticks with `--shots <folder>`. For checking animation, the wizard garb and effects by eye. |
| `--bot golems` | Golem showcase (`--host --give-all --max-level`): summons a golem at the dummies, then the stone titan, and watches from the side; `--shots <folder>`. |
| `--bot show --orbit` / `--bot show --carry` | The showcase standing still while the camera goes all the way round (front, side, back) / with every weapon in turn, walking and standing. |
| `--bot archery [--sling]` | Draws, holds and looses the bow (or slingshot) aiming level, up and down, seen from behind, the side, the front and above; pictures at half draw, full draw, the release and rest. |
| `--leave-at <frame>` | Presses "Leave game" at that frame (the game then starts again with the same options: with `--host` it hosts again). |
| `--bot magic` | Casts every staff and wand spell at the middle dummy (`--plan2`, `--plan3` for the level 3 and 4 spells, `--every` to save a picture every 6 ticks with `--shots`). |
| `--bot duel` | (`--host --give-all --shots <folder>`) Walks to the Duel Stone and presses E, then meets a challenger of every kind (sword, club, bow, slingshot, then after a level-up staff and wand) for 7 s each, with pictures through each fight. |
| `--bot boss --leap` | (v0.11.0, `--host --give-all --shots <folder>`) Static stacks on you, then a Storm Leap at once; a picture every 10 ticks for 25 s. |
| `--bot boss [--defeat]` | (`--host --give-all --shots <folder>`) Levels up to 3 (the stone turns violet, the altar rises), jumps on the altar, watches Thunderhorn come down and fight from 10-16 m (kept alive), takes him to half and a quarter of his health, then beats him and pictures the victory and the prize. With `--defeat` it dies instead: the defeat screen, a key, the restart. |
| `--bot prize [--defeat] [--no-prize-pic]` | Just the end screens (victory and the prize, or defeat); `--no-prize-pic` shows the drawn stand-in. |
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
| `--give-all`, `--give-staff`, `--give-wand`, `--max-level` | (host) start with every weapon, or the basic weapons plus the staff or the wand; every spell unlocked. |
| `--give-guests` | (host) guests start with every weapon too, so a guest can be tested casting over `--netsim`. |
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

## What's new in 0.8.1

- **Arms and shoulders (3D figure):** the shoulder joints sit at the ends of the collarbones (they were above the
  torso, like epaulettes), with a deltoid and a sloping trapezius; slightly longer arms (hands to about mid-thigh);
  elbows point back, not out; the free arms swing from the shoulder opposite the legs (about 15 degrees walking, 30
  running, the elbows bending toward 90 degrees at a run), swing less when strafing, trail back on a dash and lift
  only a little in the air.
- **Archery (3D figure):** a real stance: side-on, the head looking along the arrow, the arrow at the side of the jaw,
  the bow canted, so the string and arrow never pass through the head or neck; it tilts with your aim.
- **Robes, hat, hood, cloak:** see "Wizard garb" above.
- **Shield:** see "The shield" above.
- **Pip carries his weapon** at all times.
- **Leaving and hosting again** in the same session works: leaving used to keep the old connection open, so hosting
  again failed with "port 7777 is being used" (`Net.shutdown`, `tools/rehost_test.gd`).

## What's new in 0.9.0

- **Costumes for every weapon** (see "Costumes" above), on Pip and the 3D figure, swapping as you switch weapons.
- **Chain lightning:** the staff's Lightning hits everyone in its strike for the full 28, then jumps from each one hit
  to the nearest enemy within 6 m for half the damage (28, 14, 7, 4), every 5 ticks, at most 5 jumps; the same enemies
  as everything else (PvP players, other summoners' golems, practice dummies), never you or your own golems; a shield
  soaks a jump and stops that branch; kills count for the staff (golems never do).
- **Pip's weapon in front of him** in every direction (it could fall behind his body sprite), held beside him from
  behind, ahead of him side on; the staff taller.
- **3D figure:** the robe and cloak keep their length when jumping (they used to stretch toward the ground); sleeves
  are tubes round the arms with bell cuffs; the hooded robe for Pip redrawn (a peaked cowl framing the face).
- **Tests:** chain lightning (28/14/7 down a line, out of range, never the caster or their golem or PvP-off players,
  shields end a branch, two in the strike both take 28); golem and titan kills never count toward levels.

## What's new in 0.10.0

- **The Duel Stone:** E summons a challenger to fight (bow, slingshot, sword or club; staff and wand wizards after
  your first level-up, when its runes turn violet). Challengers have real fighting AI (spacing, strafing, dodging,
  feints, punishing, leading shots, kiting, shields, area spells, blinks, golems, stun combos), count toward your
  levels and fight whatever PvP says.
- **The Storm Altar and Thunderhorn:** at level 3 the altar rises; jump on it to call down the storm bull, a boss
  with seven telegraphed attacks, enrage and storm phases, weaknesses and resistances, three kinds of roar, a big
  health bar, synced to everyone.
- **The prize** for beating him (confetti, then a mariachi fiesta), and a defeat screen with a restart that keeps
  your levels. See [The Duel Stone, the Storm Altar and Thunderhorn](#the-duel-stone-the-storm-altar-and-thunderhorn).
- Challengers don't take up player slots.

## What's new in 0.11.0

- **Thunderhorn reborn:** a sculpted, skinned creature (3.5x your height) with storm-hide shaders, obsidian horns and
  hooves, a spiked tail, glowing eye and attack trails; animal movement (circling, backing off, hops, snap turns,
  lunges, snorts, head shakes); every attack with a wind-up, sound and impact (dust, sparks, scorch, camera shake);
  new attacks (gore, tail lash) and variants by phase (double/triple charge, stomp combo, two-way beam, static balls
  and roar, walking lightning); designed phases with announcements; new procedural sounds (snorts, hooves, scrapes,
  crackle, charge-up, whooshes, slams, zaps, the howl).
- **Smarter targeting:** distance, threat (who hurt him lately and most), finishing the weak (but never someone stunned
  or knocked down), punishing those who hang back or cast, line of sight, and a fair share of attention between players.
- **Static** (a build-up stun) and **the Storm Leap** (see Thunderhorn above).
- **More health:** 7000 alone, x1.7 for two, +0.7x per extra player; joining mid-fight scales it.
- **Challenger archers and slingers are fair now:** they aim where you stand with a real spread (wider far away and
  when you run or dash), hold the full draw a moment (watch for it), shoot less often and pause to reposition.
