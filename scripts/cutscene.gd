## The Duel Stone's corruption (v0.12.3, Jacob): a ~12 s cinematic that plays once per Thunderhorn fight, the first
## time his health drops below CUT_HP (60%). It is NEVER started in the middle of a Storm Leap sequence, while he is
## dazed, in a phase change or arriving: it waits until that is over (Boss.cut_due). Restarting the fight (a new Boss)
## arms it again.
##
## This file is the shared timeline (pure statics): the server (Boss: where he is each tick; Net: when the six corrupted
## minions are spawned, how they rise and turn) and every client (CutsceneView: the camera shots, poses, letterbox,
## title, sounds; BossView: his poses; ArenaView: the stone turning evil) read the same numbers, so everyone sees the
## same film. Clients take the time from the boss state (state Boss.S.CUTSCENE, its `t`), so a player who joins in the
## middle sees the rest of it from where it is.
##
## The film, in ticks (60 a second):
##   0   .. TURN_END   wide shot: he stops and swings round toward the Duel Stone, snorting; thunder
##   .. RUN_END       tracking shot: he gallops to the stone (if it is far, the cut at RUN_END hides the rest of the way)
##   .. SLAM_AT       low angle: he rears up over the stone ... and slams down on it; a bolt of lightning hits it
##   CORRUPT_AT ..    close-up: the runes turn from gold to deep red and violet, cracks glow, corrupted motes, a drone
##   RISE_AT  ..      wide shot: six figures claw up out of the ground round the stone, limp and hunched (bone creaks)
##   EYES_AT  ..      close-up: they jerk their heads up and evil smoke-trails ignite from their eyes (a whisper chord)
##   TWITCH_AT ..     they twitch and jerk like puppets on strings (~2.8 s), the camera slowly circling them
##   SNAP_AT  ..      they freeze, snap round to face the players and draw their weapons
##   LEN              control comes back; each client's camera eases back to its player over BLEND s
## While it plays (Net, server side): nobody can act (inputs are emptied), everybody (players, golems, Thunderhorn,
## challengers, minions) is invulnerable, projectiles and pending spells are cleared, golems and challengers stand
## still, and Thunderhorn's own clocks (burning, slow, stun meter, leap timers) are paused.
class_name Cutscene

const CUT_HP := 0.6
const LEN := 720
const TURN_END := 72
const RUN_END := 204
const SLAM_AT := 268
const CORRUPT_AT := 280
const RISE_AT := 372
const RISE_LEN := 84
const RISE_ORDER := [2, 0, 4, 1, 5, 3]   # who comes up first (the k-th to rise starts RISE_STAGGER * k later)
const RISE_STAGGER := 9
const EYES_AT := 468
const TWITCH_AT := 504
const SNAP_AT := 672
const BLEND := 1.0          # seconds for the camera to ease back to the player
const UNDER := -2.2         # a minion's feet before it rises (below the ground)
const STAND_D := 5.0        # Thunderhorn stops this far from the stone's middle, facing it
const RUN_MAX := 26.0       # his fastest gallop (m/s) in the run; further than that and the cut covers the rest
const RING_R := 6.2         # the minions rise on this ring round the stone, on the far side from him
const SPREAD := [-75.0, -45.0, -15.0, 15.0, 45.0, 75.0]   # degrees round from straight away from him
const EVIL := Color("d01c4e")     # the corruption's colours: deep red ...
const EVIL2 := Color("8a2cff")    # ... and violet
const MINION_COL := Color("b0205a")   # a minion's own colour (its accent, ring and name)
const WEAPONS := [Weapons.SWORD, Weapons.CLUB, Weapons.BOW, Weapons.SLING, Weapons.STAFF, Weapons.WAND]
const NAMES := ["Swordsman", "Clubber", "Archer", "Slinger", "Staff Wizard", "Wand Wizard"]


static func stone() -> Vector3:
	return Vector3(WorldLayout.DUEL_C.x, 0, WorldLayout.DUEL_C.y)


## Where he stops to slam the stone: STAND_D from it, on the side he comes from.
static func stand_spot(from: Vector3) -> Vector3:
	var s := stone()
	var d := Vector2(from.x - s.x, from.z - s.z)
	d = d.normalized() if d.length() > 0.5 else Vector2(0, 1)
	return s + Vector3(d.x, 0, d.y) * STAND_D


## The yaw (Boss / Sim convention: forward is (-sin, -cos)) that faces `to` from `from`.
static func yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))


## Thunderhorn at tick t of the film, from where he was (`from`, facing `yaw0`) when it began: [position, yaw].
static func boss_at(t: int, from: Vector3, yaw0: float) -> Array:
	var s := stone()
	var stand := stand_spot(from)
	var face := yaw_to(from, s)
	var f0 := Vector3(from.x, 0, from.z)
	if t < TURN_END:
		var k := smoothstep(0.0, 1.0, clampf(float(t) / (TURN_END * 0.8), 0.0, 1.0))
		return [f0, lerp_angle(yaw0, face, k)]
	if t < RUN_END:
		var path := Vector3(stand.x - f0.x, 0, stand.z - f0.z)
		var l := path.length()
		var dur := (RUN_END - TURN_END) * Config.DT
		var covered := minf(l, RUN_MAX * dur)
		var u := float(t - TURN_END) / float(RUN_END - TURN_END)
		var along := covered * (0.45 * u + 0.55 * u * u * (3.0 - 2.0 * u))   # a quick start, a braking finish
		var at := f0 + (path.normalized() * along if l > 0.01 else Vector3.ZERO)
		return [at, face]
	return [stand, yaw_to(stand, s)]


## Where minion i (of the six, in WEAPONS order) rises: on a ring round the stone, on the far side from him.
static func minion_spot(i: int, from: Vector3) -> Vector3:
	var s := stone()
	var u := Vector2(from.x - s.x, from.z - s.z)
	u = u.normalized() if u.length() > 0.5 else Vector2(0, 1)
	var a := deg_to_rad(float(SPREAD[i]))
	var away := (-u).rotated(a)
	var r := RING_R + (0.9 if i % 2 == 1 else 0.0)
	return s + Vector3(away.x, 0, away.y) * r


## When minion i starts to rise (ticks into the film).
static func rise_start(i: int) -> int:
	return RISE_AT + RISE_ORDER.find(i) * RISE_STAGGER


## How high a minion's feet are at tick t: under the ground, then clawing up in lurches, then standing (0).
static func minion_y(t: int, i: int) -> float:
	var k := clampf(float(t - rise_start(i)) / float(RISE_LEN), 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 2.2)
	e += 0.07 * sin(k * PI * 5.0) * (1.0 - k)   # lurching, not gliding
	return UNDER * (1.0 - clampf(e, 0.0, 1.0))


## The tick minion i jerks its head up and its eyes ignite.
static func eyes_at(i: int) -> int:
	return EYES_AT + [6, 0, 14, 3, 18, 9][i]


## A minion puppet's pose at film time `ct` (ticks): {limp, hunch, head (pitch: - down, + up), roll, twist, arms,
## hide_weapon, snap}. Deterministic (the same on every screen).
static func puppet(ct: float, i: int) -> Dictionary:
	var p := {"limp": 1.0, "hunch": 1.0, "head": -0.75, "roll": 0.0, "twist": 0.0, "arms": 0.0, "hide_weapon": true, "snap": false}
	var sway := sin(ct * 0.05 + i * 1.7)
	p.roll = 0.06 * sway
	if ct < rise_start(i) + RISE_LEN:   # still coming up: dangling, swinging a little
		p.head = -0.9
		p.roll = 0.12 * sin(ct * 0.11 + i)
		return p
	var up := clampf((ct - eyes_at(i)) / 8.0, 0.0, 1.0)   # the head jerks up in 8 ticks
	p.head = lerpf(-0.8, 0.45, up)
	if ct >= TWITCH_AT and ct < SNAP_AT:   # possessed: jerking to new poses a few times a second, never smoothly
		var beat := floorf(ct / 9.0 + i * 0.37)
		var h1 := _hash(beat * 3.1 + i * 17.0)
		var h2 := _hash(beat * 5.7 + i * 7.0 + 1.0)
		var h3 := _hash(beat * 2.3 + i * 11.0 + 2.0)
		var h4 := _hash(beat * 7.9 + i * 3.0 + 3.0)
		var spasm := 1.0 if _hash(beat * 1.3 + i) > 0.55 else 0.45
		p.twist = (h1 - 0.5) * 1.3 * spasm
		p.roll = (h2 - 0.5) * 0.7 * spasm
		p.head = 0.25 + (h3 - 0.5) * 1.1 * spasm
		p.arms = (h4 - 0.5) * 2.0 * spasm
		p.hunch = 0.55 + 0.45 * _hash(beat * 4.4 + i * 5.0)
		p.snap = true
	elif ct >= SNAP_AT:   # frozen a moment, then they straighten, turn and draw
		var k := clampf((ct - SNAP_AT - 14.0) / 7.0, 0.0, 1.0)
		p.limp = 1.0 - k
		p.hunch = 1.0 - k
		p.head = lerpf(0.3, 0.0, k)
		p.roll = 0.0
		p.snap = true
		p.hide_weapon = ct < SNAP_AT + 22.0
	return p


static func _hash(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 78.233) * 43758.5453, 1.0)
