## v0.13.0 SMIGUEL PEEKS (Jacob: "very rarely... smiguel will peek out from behind a tree or something at the player...
## just enough to see him, and then if they look directly at him with their cursor near him or on him then he will
## duck back behind the object and disappear... if they move close enough to him then he will also disappear... kinda
## creepy and subtle... If anyone is playing as smiguel, then that won't happen... every 4-7 minutes").
## Server side (Net.smiguel), so everyone sees the same thing:
##   - every PEEK_MIN..PEEK_MAX (4-7 minutes) of play he looks for a hiding place: a pillar or a tree trunk that every
##     living player can see, PEEK_NEAR..PEEK_FAR m from each of them, with a clear line from each of them to it;
##   - he stands just behind it, on the far side from the players, and leans out of its edge so that from every player's
##     view about a third to a half of him shows (VIS_MIN..VIS_MAX of his width past the edge: `_visible_frac`); with
##     players on very different sides there may be no such place: he tries again in a little while;
##   - he stays PEEK_HOLD seconds at most, watching them; he ducks back (and is gone) as soon as anyone's crosshair comes
##     near him (their aim point within LOOK_R m of him, or their aim line within LOOK_DEG degrees), or anyone comes
##     within FLEE_NEAR m, or the time is up. Go round the tree after: nothing there.
##   - never while anyone plays as Smiguel, during Thunderhorn's fight, or with nobody in the game.
## Events: "smiguel_peek" [pos, yaw, side (+1 leans right of the cover as the players see it, -1 left)], "smiguel_duck"
## [pos, how ("look", "near", "time")]. SmiguelView (on every screen) draws him.
class_name SmiguelPeek
extends RefCounted

const PEEK_MIN := 4 * 60
const PEEK_MAX := 7 * 60
const RETRY := 30            # seconds before trying again when there was no good place
# v0.13.0 (Jacob: "he will only appear behind objects players are facing away from, and then when they turn around,
# they will be able to see him for about 0.5-1.5 seconds, and then he will duck behind the object again. If they are
# far enough away, he will remain partially visible, but if they move closer then he will disappear"):
const PEEK_HOLD := 60.0      # s he waits for someone to turn round before slipping away unseen
const PEEK_NEAR := 8.0
const PEEK_FAR := 35.0   # (far off: "the player can kind of see something over there")
const FLEE_NEAR := 6.5
const BEHIND_DEG := 115.0    # his spot must be at least this far round from where every player is looking
const VIEW_DEG := 38.0       # within this of where a player looks, he's on their screen
const SEEN_MIN := 0.5        # once seen up close: he ducks after this many seconds...
const SEEN_MAX := 1.5        # ...to this many
const STAY_FAR := 14.0       # seen from closer than this: a moment, then he ducks
const AIM_DUCK := 24.0       # aimed at from closer than this: he ducks at once (further off, he doesn't care)
const STAY_MAX := 240.0      # s he'll stay peeking at someone far off before slipping away       # seen from further than this: he stays, half hidden, until they come closer (or aim at him)
const LOOK_R := 2.2
const LOOK_DEG := 6.0
const BODY_HALF := 0.5       # m: half his width as seen
const VIS_MIN := 0.45   # (Jacob: his face and at least half of him shows)
const VIS_MAX := 0.75

var next_at := -1            # server tick of the next try
var peeking := false
var pos := Vector3.ZERO
var yaw := 0.0
var side := 1
var since := 0
var cover := Vector3.ZERO    # the middle of what he's hiding behind
var rng := RandomNumberGenerator.new()
var peeks := 0               # (tests)
var last_reason := ""
var seen_at := -1            # server tick someone first had him on screen up close (-1: not yet)
var seen_for := 1.0          # seconds he lets them look
var seen_by := 0
var _far_seen := false       # someone far off has had him on screen (then he stays up to STAY_MAX)


func _init(seed_v := 0) -> void:
	rng.seed = seed_v if seed_v != 0 else randi()


func _schedule(tick: int, secs: float) -> void:
	next_at = tick + int(secs * Config.TICK_RATE)


## His lines: everyone playing as Smiguel (players and units) mutters one every SAY_MIN..SAY_MAX seconds, never the
## same one twice running (SmiguelView plays them from where they stand).
const SAY_MIN := 90.0
const SAY_MAX := 180.0
const LINE_COUNT := 12
var _say_at := {}    # id -> server tick of their next line
var _said := {}      # id -> their last line


func _lines(net: Net) -> void:
	var t := net.server_tick
	for p: Net.ServerPlayer in net.players.values():
		if p.skin != "smiguel" or p.state.dead > 0:
			continue
		if not _say_at.has(p.id):
			_say_at[p.id] = t + int(rng.randf_range(20.0, SAY_MAX) * Config.TICK_RATE)
		elif t >= int(_say_at[p.id]):
			var n := rng.randi_range(0, LINE_COUNT - 1)
			if n == int(_said.get(p.id, -1)):
				n = (n + 1) % LINE_COUNT
			_said[p.id] = n
			net._fx("smiguel_say", [p.id, n])
			_say_at[p.id] = t + int(rng.randf_range(SAY_MIN, SAY_MAX) * Config.TICK_RATE)


func tick(net: Net) -> void:
	var t := net.server_tick
	_lines(net)
	var humans := []
	var blocked := net.boss != null
	for p: Net.ServerPlayer in net.players.values():
		if p.npc:
			continue
		if p.skin == "smiguel":
			blocked = true
		if p.state.dead == 0:
			humans.append(p)
	if next_at < 0:
		_schedule(t, rng.randf_range(PEEK_MIN, PEEK_MAX))
	if peeking:
		if blocked or humans.is_empty():
			duck(net, "time")
			return
		for p: Net.ServerPlayer in humans:
			var d := Vector2(p.state.pos.x - pos.x, p.state.pos.z - pos.z).length()
			if d < FLEE_NEAR:
				duck(net, "near")
				return
			if d < AIM_DUCK and looking_at(p, pos):
				duck(net, "look")
				return
			if seen_at < 0 and d < STAY_FAR and in_view(p, pos):
				seen_at = t   # they turned round and he's on their screen: a moment, then gone
				seen_by = p.id
				seen_for = rng.randf_range(SEEN_MIN, SEEN_MAX)
		if seen_at >= 0 and float(t - seen_at) / Config.TICK_RATE >= seen_for:
			duck(net, "seen")
			return
		# (Jacob: "he should consistently stay peeking from behind objects whenever he is far away... whenever the
		# player gets close enough, he ducks back to hide"): far off he stays, whether they see him or not
		var held := float(t - since) / Config.TICK_RATE
		if seen_at < 0 and (held > STAY_MAX or (held > PEEK_HOLD and not _far_seen)):
			duck(net, "time")
		for p: Net.ServerPlayer in humans:
			if in_view(p, pos):
				_far_seen = true
		return
	if t < next_at or blocked or humans.is_empty():
		if blocked and t >= next_at:
			_schedule(t, RETRY)
		return
	if not try_peek(net, humans):
		_schedule(t, RETRY)


## Where player p is looking (flat), from their last input: toward their aim point, else their camera heading.
static func look_dir(p: Net.ServerPlayer) -> Vector2:
	var inp: Sim.PlayerInput = p.last_inp
	if inp == null:
		return Vector2(-sin(p.state.yaw), -cos(p.state.yaw))
	var cam := Vector2(-sin(inp.yaw), -cos(inp.yaw))
	return cam


## Is the spot on player p's screen (roughly: within VIEW_DEG of where they look)?
static func in_view(p: Net.ServerPlayer, at: Vector3) -> bool:
	var to := Vector2(at.x - p.state.pos.x, at.z - p.state.pos.z)
	if to.length() < 0.5:
		return true
	return rad_to_deg(look_dir(p).angle_to(to.normalized())) < VIEW_DEG and absf(rad_to_deg(look_dir(p).angle_to(to.normalized()))) < VIEW_DEG


## Is the spot behind player p (they're facing away from it)?
static func behind(p: Net.ServerPlayer, at: Vector3) -> bool:
	var to := Vector2(at.x - p.state.pos.x, at.z - p.state.pos.z)
	return absf(rad_to_deg(look_dir(p).angle_to(to.normalized()))) > BEHIND_DEG


## Is player p's crosshair on him or near him? (their aim point, or the line from them toward it)
static func looking_at(p: Net.ServerPlayer, at: Vector3) -> bool:
	var inp: Sim.PlayerInput = p.last_inp
	if inp == null:
		return false
	var head := at + Vector3(0, 1.1, 0)
	if inp.aim_point != Vector3.ZERO and inp.aim_point.distance_to(head) < LOOK_R:
		return true
	var eye := p.state.pos + Vector3(0, 1.5, 0)
	var to_him := head - eye
	var aim := inp.aim_point - eye if inp.aim_point != Vector3.ZERO else Vector3(-sin(inp.yaw), 0, -cos(inp.yaw))
	if aim.length() < 0.3 or to_him.length() < 0.3:
		return false
	var deg := rad_to_deg(aim.normalized().angle_to(to_him.normalized()))
	return deg < LOOK_DEG


## Find a hiding place and peek from it. -> false if there's none good enough now.
func try_peek(net: Net, humans: Array) -> bool:
	var best = null
	var best_score := INF
	for c in covers():
		var cc: Vector3 = c[0]
		var ok := true
		var centre := Vector3.ZERO
		for p: Net.ServerPlayer in humans:
			var d := Vector2(p.state.pos.x - cc.x, p.state.pos.z - cc.z).length()
			if d < PEEK_NEAR or d > PEEK_FAR or not behind(p, cc):
				ok = false
				break
			centre += p.state.pos
		if not ok:
			continue
		centre /= float(humans.size())
		var away := Vector2(cc.x - centre.x, cc.z - centre.z).normalized()
		var across := Vector2(-away.y, away.x)
		var depth: float = c[1]
		for s in [-1, 1]:
			for lean in [0.0, 0.12, 0.24, -0.1]:
				var off: float = float(c[2]) + lean
				var p2: Vector2 = Vector2(cc.x, cc.z) + away * (depth + 0.55) + across * float(s) * off
				var at := Vector3(p2.x, 0.0, p2.y)
				at.y = maxf(WorldLayout.ground_height(at.x, at.z, 0.5), 0.0)
				if WorldLayout.tree_at(at + Vector3(0, 0.5, 0), 0.3) >= 0 or _in_box(at):
					continue
				var score := 0.0
				var fits := true
				for p: Net.ServerPlayer in humans:
					var v := visible_frac(p.state.pos + Vector3(0, 1.5, 0), at, c)
					if v < VIS_MIN or v > VIS_MAX:
						fits = false
						break
					score += absf(v - 0.36)
				if fits and score < best_score:
					best_score = score
					best = [at, cc, s]
	if best == null:
		return false
	pos = best[0]
	cover = best[1]
	side = best[2]
	var centre := Vector3.ZERO
	for p: Net.ServerPlayer in humans:
		centre += p.state.pos
	centre /= float(humans.size())
	yaw = atan2(-(centre.x - pos.x), -(centre.z - pos.z))
	peeking = true
	seen_at = -1
	_far_seen = false
	since = net.server_tick
	peeks += 1
	net._fx("smiguel_peek", [pos, yaw, side, cover])
	return true


func duck(net: Net, why: String) -> void:
	if not peeking:
		return
	peeking = false
	last_reason = why
	net._fx("smiguel_duck", [pos, why])
	_schedule(net.server_tick, rng.randf_range(PEEK_MIN, PEEK_MAX))


## The dev console's "peek": now (somewhere near whoever's in the game).
func force_peek(net: Net = null) -> String:
	if net == null:
		return "no game"
	var humans := []
	for p: Net.ServerPlayer in net.players.values():
		if not p.npc and p.state.dead == 0:
			humans.append(p)
	if peeking:
		duck(net, "time")
	if try_peek(net, humans):
		return "Don't turn round... (he's behind something %.0f m behind you)" % humans[0].state.pos.distance_to(pos)
	return "Nowhere for him to hide behind you right now (have a tree or pillar 8-35 m behind you, then turn round)"


## What he can hide behind: [middle, half depth along the players' view (rough), half width] for pillars at least 1.6 m
## tall and the oak trunks (the fruit trees are too thin).
static func covers() -> Array:
	var out := []
	for b: WorldLayout.Box in WorldLayout.boxes():
		if b.kind != "" or b.h < 1.6:
			continue
		var tree := WorldLayout.tree_at(Vector3(b.cx, 0.5, b.cz)) >= 0
		if tree and b.hx < 0.3:
			continue
		out.append([Vector3(b.cx, 0, b.cz), maxf(b.hx, b.hz), minf(b.hx, b.hz) if not tree else b.hx, b])
	return out


static func _in_box(at: Vector3) -> bool:
	for b: WorldLayout.Box in WorldLayout.boxes():
		if absf(at.x - b.cx) < b.hx + 0.35 and absf(at.z - b.cz) < b.hz + 0.35 and b.h > 0.3:
			return true
	return false


## From `eye`, how much of him (0..1 of his width) shows past the cover's edge, if he stands at `at`; 0 if the cover
## hides him or something else is in the way, 1 if nothing covers him.
static func visible_frac(eye: Vector3, at: Vector3, c: Array) -> float:
	var b: WorldLayout.Box = c[3]
	var to := Vector2(at.x - eye.x, at.z - eye.z)
	var dist := to.length()
	if dist < 0.5:
		return 1.0
	var dir := to / dist
	var perp := Vector2(-dir.y, dir.x)
	# the cover's silhouette across the line of sight: its corners projected onto the perpendicular
	var lo := INF
	var hi := -INF
	var nearest := INF
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner := Vector2(b.cx + sx * b.hx - eye.x, b.cz + sz * b.hz - eye.z)
			var along := corner.dot(dir)
			nearest = minf(nearest, along)
			var k := corner.dot(perp) / maxf(along, 0.1) * dist   # scaled to his distance
			lo = minf(lo, k)
			hi = maxf(hi, k)
	if nearest > dist - 0.2:
		return 1.0   # the cover isn't between them
	var me0 := -BODY_HALF
	var me1 := BODY_HALF
	var hidden := maxf(0.0, minf(me1, hi) - maxf(me0, lo))
	var frac := 1.0 - hidden / (2.0 * BODY_HALF)
	if frac <= 0.0:
		return 0.0
	# something else in the way of the part that shows?
	var show_x := (me0 + me1) / 2.0
	if hi < me1:
		show_x = (maxf(hi, me0) + me1) / 2.0
	elif lo > me0:
		show_x = (me0 + minf(lo, me1)) / 2.0
	var target := Vector3(at.x + perp.x * show_x, 1.1, at.z + perp.y * show_x)
	var ray := target - eye
	if WorldLayout.ray_hit(eye, ray.normalized(), ray.length()) < ray.length() - 0.3:
		return 0.0
	return frac
