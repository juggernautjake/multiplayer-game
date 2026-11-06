## The living yard, run by the server only and sent to clients as timed events (Net.eco_event): fruit trees and oaks,
## fruit that grows, falls (on its own, or when you hit the tree) and bounces, worms that move into fallen fruit, and
## birds that come to eat them. Ported from Jacob's Pip village (04-games/pip/village: game.js, shared/village-worms.js)
## with its rules and timings; village pixels become metres at 1 px = 0.04 m (Pip is 45 px, 1.8 m tall). Fruit grows
## and drops faster than the village's 5-minute cycle, so it happens while you play.
##
## Every event carries the server tick it starts at, and clients draw it on the same delayed clock as other players,
## so a bird lands, pecks and tugs at the same moment for everyone.
class_name Ecology
extends RefCounted

const PX := 0.04                      # village pixels -> metres
const GROW_EVERY := 60 * 60           # ticks: an empty slot may sprout (village 300 s)
const DROP_EVERY := 45 * 60           # ticks: each ripe fruit rolls a 25% drop (village 300 s)
const DROP_CHANCE := 0.25
const MAX_FRUIT := 4
const MAX_GROUND := 4
const GRAVITY := 420.0 * PX           # 16.8 m/s^2
const FRUIT_R := 0.09                 # a fruit's radius: it rests and rolls with its centre this high
const ROLL_DECEL := 2.4               # m/s^2: grass slows a rolling fruit (a 3 m/s kick rolls about 1.9 m)
const ROLL_BOUNCE := 0.45             # share of its speed a rolling fruit keeps off a wall, trunk or dummy
const KICK_COOLDOWN := 12             # ticks before the same fruit can be kicked again
const SLOTS := [Vector2(-0.55, 0.35), Vector2(0.5, 0.42), Vector2(-0.15, 0.62), Vector2(0.25, 0.2)]
const GREETINGS := ["Hello world!", "Hi there!", "Mmm, apple!", "Oh, hello!", "Nice day!"]
const QUIRKS := ["look", "yawn", "munch", "wave", "stretch", "burp"]

signal event(kind: String, args: Array)   # -> Net -> every client

var rng := RandomNumberGenerator.new()
var trees: Array = []      # { i, pos, kind, hits, last_hit }
var fruits := {}           # id -> { id, tree, slot, state ("hang"/"fall"/"ground"), grow, pos, land, ground_since, worm }
var worms := {}            # id -> { id, fruit, steps: [[tick, phase, data]], lived_from, calm_until, out, gone }
var birds := {}            # id -> { id, worm, fruit, steps, pos }
var next_id := 1
var next_grow := GROW_EVERY
var next_drop := DROP_EVERY
var next_worm_check := 6 * 60


func _init() -> void:
	rng.seed = 20261104
	for t in WorldLayout.TREES:
		trees.append({ "i": trees.size(), "pos": t[1], "kind": t[0], "hits": 0, "last_hit": -9999, "felled": false })
	for tr in trees:
		for s in 3:   # v0.12.0: every tree (oaks too: apples) starts with three ripe
			_new_fruit(tr, s, 1.0, 0)


# ================================================================ late joiners
## Everything a new player needs to see the yard as it is now.
func full_state(now: int) -> Array:
	var out := []
	for tr in trees:
		if tr.felled:
			out.append(["tree_fell", [tr.i, Vector3.ZERO]])
	for f in fruits.values():
		if f.state == "hang":
			out.append(["fruit_hang", [f.id, f.tree, f.slot, f.grow]])
		elif f.state == "ground":
			out.append(["fruit_ground", [f.id, f.tree, f.pos]])
		else:
			out.append(["fruit_fall", [f.id, f.tree, f.fall]])
	for w in worms.values():
		if not w.steps.is_empty():
			var cur: Array = _current(w.steps, now)
			out.append(["worm", [w.id, w.fruit, cur[0], cur[1], cur[2]]])
	for b in birds.values():
		if not b.steps.is_empty():
			var cur: Array = _current(b.steps, now)
			out.append(["bird", [b.id, b.worm, cur[0], cur[1], cur[2]]])
	return out


func _current(steps: Array, now: int) -> Array:
	var c: Array = steps[0]
	for s in steps:
		if s[0] <= now:
			c = s
	return c


# ================================================================ the tick
## players: Array of [id, position, speed (m/s), horizontal velocity (Vector2)].
func tick(now: int, players: Array) -> void:
	# fruit grows and drops on its own
	if now >= next_grow:
		next_grow = now + GROW_EVERY
		for tr in trees:
			if tr.felled:
				continue
			var used := _slots_used(tr)
			var free := []
			for s in SLOTS.size():
				if not s in used:
					free.append(s)
			if not free.is_empty():
				_new_fruit(tr, free[rng.randi() % free.size()], 0.01, now)
	if now >= next_drop:
		next_drop = now + DROP_EVERY
		for f in fruits.values().duplicate():
			if f.state == "hang" and f.grow >= 1.0 and _ground_count(f.tree) < MAX_GROUND and rng.randf() < DROP_CHANCE:
				_drop(f, now, 0.6)
	for f in fruits.values():
		if f.state == "hang" and f.grow < 1.0:
			f.grow = minf(1.0, f.grow + 1.0 / (4.0 * Config.TICK_RATE))   # swells to full over 4 s
		elif f.state == "fall" and now >= f.land:
			f.state = "ground"
			f.pos = f.end
			f.ground_since = now
	_kicks(now, players)
	_worms_tick(now, players)
	_birds_tick(now, players)


func _slots_used(tr: Dictionary) -> Array:
	var used := []
	for f in fruits.values():
		if f.tree == tr.i and f.state == "hang":
			used.append(f.slot)
	return used


func _ground_count(tree_i: int) -> int:
	var n := 0
	for f in fruits.values():
		if f.tree == tree_i and f.state != "hang":
			n += 1
	return n


func _new_fruit(tr: Dictionary, slot: int, grow: float, _now: int) -> void:
	var f := { "id": next_id, "tree": tr.i, "slot": slot, "state": "hang", "grow": grow, "pos": Vector3.ZERO,
		"land": 0, "ground_since": 0, "worm": 0, "fall": [], "end": Vector3.ZERO, "kicked": -999 }
	next_id += 1
	fruits[f.id] = f
	event.emit("fruit_hang", [f.id, tr.i, slot, grow])


## Where a hanging fruit is (shared with the client's drawing).
static func slot_pos(tree_pos: Vector3, slot: int, kind := "apple") -> Vector3:
	var s: Vector2 = SLOTS[slot]
	if kind == "oak":   # v0.12.0: oaks bear apples too, under their bigger crown
		return tree_pos + Vector3(s.x * 2.4, 2.35 + s.y * 0.5, 1.15 + s.y * 0.3)
	return tree_pos + Vector3(s.x * 24.0 * PX * 2.2, 48.0 * PX + s.y * 40.0 * PX + 0.6, 0.35 + s.y * 0.3)


## Knock a fruit loose: it falls from its branch, maybe bounces once, rolls and comes to rest.
func _drop(f: Dictionary, now: int, kick := 1.0) -> void:
	var tr: Dictionary = trees[f.tree]
	var p := slot_pos(tr.pos, f.slot, tr.kind)
	var v := Vector3(rng.randf_range(-14, 14) * PX * kick, rng.randf_range(0, 20) * PX * kick, rng.randf_range(4, 14) * PX * kick)
	_launch(f, now, p, v)
	event.emit("sound", ["fruitDrop", f.end])


## Send a fruit on its way from p at velocity v: the whole path is worked out here and sent as segments, so every
## client draws the same flight and roll. Flight: parabola segments [tick, start, velocity] (one bounce if it lands
## hard). Then rolling: [tick, start, velocity, decel] segments, slowing on the grass, glancing off walls, trunks and
## dummies; the last one has zero velocity (at rest).
func _launch(f: Dictionary, now: int, p: Vector3, v: Vector3) -> void:
	var segs := []
	var t := now
	if p.y > FRUIT_R + 0.01 or v.y > 0.0:
		for bounce in 2:
			segs.append([t, p, v])
			# time to reach the ground: p.y + v.y t - g t^2 / 2 = 0
			var tt := (v.y + sqrt(v.y * v.y + 2.0 * GRAVITY * maxf(p.y, 0.0))) / GRAVITY
			var land := p + Vector3(v.x * tt, -p.y, v.z * tt)
			var vy := v.y - GRAVITY * tt
			t += int(tt * Config.TICK_RATE)
			p = Vector3(land.x, 0.0, land.z)
			if vy < -40.0 * PX and bounce == 0:
				v = Vector3(v.x * 0.6, -vy * 0.35, v.z * 0.6)   # one bounce, as in the village
			else:
				v = Vector3(v.x * 0.55, 0.0, v.z * 0.55)         # lands and rolls on
				break
	var res := _roll(segs, t, Vector3(p.x, FRUIT_R, p.z), Vector3(v.x, 0.0, v.z))
	f.state = "fall"
	f.fall = segs
	f.land = res[0]
	f.end = Vector3(res[1].x, 0.07, res[1].z)
	f.kicked = now
	event.emit("fruit_fall", [f.id, f.tree, segs])


## Roll along the ground from p at horizontal velocity v until the grass stops it, bouncing off what it meets.
## Appends the segments; returns [tick it stops, where].
func _roll(segs: Array, t: int, p: Vector3, v: Vector3) -> Array:
	for bounce in 6:
		var sp := v.length()
		if sp < 0.05:
			break
		segs.append([t, p, v, ROLL_DECEL])
		var dir := v / sp
		var tstop := sp / ROLL_DECEL
		var steps := int(ceil(tstop * Config.TICK_RATE))
		var hit := 0
		var n := Vector2.ZERO
		for k in range(1, steps + 1):
			var tt := minf(k * Config.DT, tstop)
			var q := p + dir * (sp * tt - 0.5 * ROLL_DECEL * tt * tt)
			n = _wall_normal(q)
			if n != Vector2.ZERO:
				hit = k
				break
		if hit == 0:
			p = p + dir * (sp * tstop * 0.5)
			t += steps
			v = Vector3.ZERO
			break
		var th := (hit - 1) * Config.DT
		p = p + dir * (sp * th - 0.5 * ROLL_DECEL * th * th)
		var vn := dir * (sp - ROLL_DECEL * th)
		var vv := Vector2(vn.x, vn.z)
		vv = (vv - 2.0 * vv.dot(n) * n) * ROLL_BOUNCE
		v = Vector3(vv.x, 0.0, vv.y)
		t += hit - 1
	segs.append([t, p, Vector3.ZERO, ROLL_DECEL])   # at rest
	return [t, p]


## The outward normal of whatever a fruit at q is touching (a pillar, a trunk, a dummy, the world's edge), or zero.
func _wall_normal(q: Vector3) -> Vector2:
	for b: WorldLayout.Box in WorldLayout.boxes():
		var nx := clampf(q.x, b.cx - b.hx, b.cx + b.hx)
		var nz := clampf(q.z, b.cz - b.hz, b.cz + b.hz)
		var d := Vector2(q.x - nx, q.z - nz)
		if d.length() < FRUIT_R:
			if d.length() > 1e-5:
				return d.normalized()
			var ox := q.x - b.cx
			var oz := q.z - b.cz
			return Vector2(signf(ox), 0.0) if absf(ox) / b.hx > absf(oz) / b.hz else Vector2(0.0, signf(oz))
	for dp: Vector3 in WorldLayout.DUMMIES:
		var d := Vector2(q.x - dp.x, q.z - dp.z)
		if d.length() < Sim.DUMMY_RADIUS + FRUIT_R:
			return d.normalized() if d.length() > 1e-5 else Vector2(0, 1)
	var lim := Config.WORLD_HALF
	if absf(q.x) > lim:
		return Vector2(-signf(q.x), 0)
	if absf(q.z) > lim:
		return Vector2(0, -signf(q.z))
	return Vector2.ZERO


## Where a fruit on its way is at tick t (the same maths the clients draw with).
static func path_pos(segs: Array, t: float) -> Vector3:
	var cur: Array = segs[0]
	for sg in segs:
		if sg[0] <= t:
			cur = sg
	var dt := maxf(t - float(cur[0]), 0.0) * Config.DT
	var p0: Vector3 = cur[1]
	var v0: Vector3 = cur[2]
	if cur.size() > 3:   # rolling: slowing at decel until it stops
		var sp := v0.length()
		if sp < 1e-4:
			return Vector3(p0.x, FRUIT_R, p0.z)
		var dec: float = cur[3]
		var tt := minf(dt, sp / dec)
		var r := p0 + v0 / sp * (sp * tt - 0.5 * dec * tt * tt)
		return Vector3(r.x, FRUIT_R, r.z)
	var p := p0 + v0 * dt - Vector3(0, GRAVITY * dt * dt / 2.0, 0)
	p.y = maxf(p.y, FRUIT_R)
	return p


## Fruit on the ground (resting or rolling, no worm inside): where it is now, or null if it can't be pushed.
func _loose_pos(f: Dictionary, now: int):
	if f.state == "hang" or f.worm != 0:
		return null
	if f.state == "ground":
		return Vector3(f.pos.x, FRUIT_R, f.pos.z)
	var q := path_pos(f.fall, now)
	return q if q.y < FRUIT_R + 0.05 else null


## People walking into fruit on the ground kick it along (the faster you go, the further it rolls); standing on one
## nudges it out from under you.
func _kicks(now: int, players: Array) -> void:
	for f in fruits.values():
		if now - int(f.get("kicked", -999)) < KICK_COOLDOWN:
			continue
		var q = _loose_pos(f, now)
		if q == null:
			continue
		for pl in players:
			var pp: Vector3 = pl[1]
			var d := Vector2(q.x - pp.x, q.z - pp.z)
			if d.length() > Sim.RADIUS + FRUIT_R or pp.y > 0.5:
				continue
			var pv: Vector2 = pl[3] if pl.size() > 3 else Vector2.ZERO
			var away := d.normalized() if d.length() > 1e-4 else Vector2(1, 0)
			var push := maxf(pv.dot(away), 0.0)
			var dir := (away + (pv.normalized() if pv.length() > 0.1 else Vector2.ZERO) * 0.6).normalized()
			var speed := maxf(0.8, push * 1.4 + 0.3)
			_launch(f, now, q, Vector3(dir.x * speed, speed * 0.12, dir.y * speed))
			break


## A blast (lightning, a fireball): loose fruit nearby is thrown away from it, harder the closer it was.
func blast_fruit(center: Vector3, radius: float, now: int) -> void:
	for f in fruits.values():
		var q = _loose_pos(f, now)
		if q == null:
			continue
		var d := Vector2(q.x - center.x, q.z - center.z)
		if d.length() > radius:
			continue
		var dir := d.normalized() if d.length() > 1e-3 else Vector2(1, 0)
		var k := 1.0 - d.length() / radius
		_launch(f, now, q + Vector3(0, 0.02, 0), Vector3(dir.x * (2.0 + 5.0 * k), 2.0 + 4.0 * k, dir.y * (2.0 + 5.0 * k)))


## A melee swing lands: fruit on the ground within reach and in front flies off the way the blow goes.
func hit_fruit(origin: Vector3, face: Vector2, reach: float, arc_deg: float, knock: float, now: int) -> void:
	for f in fruits.values():
		var q = _loose_pos(f, now)
		if q == null:
			continue
		var d := Vector2(q.x - origin.x, q.z - origin.z)
		if d.length() > reach + 0.4 or (d.length() > 0.5 and absf(face.angle_to(d)) > deg_to_rad(arc_deg / 2.0)):
			continue
		var dir := (face * 0.65 + d.normalized() * 0.35).normalized()
		var speed := 3.0 + knock * 0.6
		_launch(f, now, q + Vector3(0, 0.02, 0), Vector3(dir.x * speed, 1.6 + knock * 0.15, dir.y * speed))
		event.emit("sound", ["fruitDrop", q])


## A tree is hit (melee or arrow) with this much damage: it shakes and drops leaves; from the 3rd hit, ripe fruit falls.
func hit_tree(i: int, damage: int, now: int, dir: Vector3) -> void:
	var tr: Dictionary = trees[i]
	if tr.felled:
		return
	tr.hits += 1
	tr.last_hit = now
	event.emit("tree_hit", [i, dir, damage])
	# v0.12.0: any hit by any weapon or spell knocks ripe apples loose (one; two for a hard hit)
	var ripe := []
	for f in fruits.values():
		if f.tree == i and f.state == "hang" and f.grow >= 1.0:
			ripe.append(f)
	var n := mini(2 if damage >= 8 else 1, MAX_GROUND - _ground_count(i))
	for k in mini(n, ripe.size()):
		_drop(ripe[k], now, 1.0)


## v0.12.0: apples heal. Walking over a fallen fruit while hurt eats it: +HEAL health, a crunch and a small heal
## effect (the "fruit_gone" event carries the amount). A worm inside: it isn't eaten (it gets kicked instead).
const HEAL := 18
const EAT_R := 0.55


func eat_under(pos: Vector3, now: int) -> int:
	if pos.y > 0.6:
		return 0
	for f in fruits.values():
		if f.state != "ground" or f.worm != 0:
			continue
		var q = _loose_pos(f, now)
		if q == null or Vector2(q.x - pos.x, q.z - pos.z).length() > EAT_R:
			continue
		fruits.erase(f.id)
		event.emit("fruit_gone", [f.id, true, HEAL, q])
		return HEAL
	return 0


## v0.12.0 Thunderhorn: a tree splintered and felled (no more fruit until restore_trees), and fruit trampled to mush.
func fell_tree(i: int, now: int, dir: Vector3) -> void:
	var tr: Dictionary = trees[i]
	if tr.felled:
		return
	tr.felled = true
	for f in fruits.values().duplicate():
		if f.tree == i and f.state == "hang":
			fruits.erase(f.id)
			event.emit("fruit_gone", [f.id, false])
	event.emit("tree_fell", [i, dir])


func restore_trees(now: int) -> void:
	for tr in trees:
		if tr.felled:
			tr.felled = false
			tr.hits = 0
			event.emit("tree_up", [tr.i])
			for s in 2:
				_new_fruit(tr, s, 1.0, now)


## Fruit on the ground (resting or rolling) within r of p. -> [[id, position]]
func ground_fruit_near(p: Vector3, r: float, now: int) -> Array:
	var out := []
	for f in fruits.values():
		var q = _loose_pos(f, now)
		if q != null and Vector2(q.x - p.x, q.z - p.z).length() <= r:
			out.append([f.id, q])
	return out


func splat(id: int, now: int) -> void:
	if not fruits.has(id):
		return
	var f: Dictionary = fruits[id]
	var q = _loose_pos(f, now)
	if f.worm != 0 and worms.has(f.worm):
		_worm_leave(worms[f.worm], now)
	fruits.erase(id)
	event.emit("fruit_splat", [id, q if q != null else f.pos])


## E next to a fallen fruit: eat it (+8 HP). A worm inside: 70% it hops out and leaves, 30% it blows a raspberry and
## you put the fruit back down. -> HP gained.
func try_eat(pos: Vector3, now: int) -> int:
	var best: Dictionary = {}
	var best_d := 1.3
	for f in fruits.values():
		if f.state == "ground":
			var d := Vector2(f.pos.x - pos.x, f.pos.z - pos.z).length()
			if d < best_d:
				best = f
				best_d = d
	if best.is_empty():
		return 0
	if best.worm != 0 and worms.has(best.worm):
		var w: Dictionary = worms[best.worm]
		if rng.randf() < 0.3:
			event.emit("say", ["worm", w.id, "pbbt!"])
			return 0
		event.emit("say", ["worm", w.id, "Hey!"])
		_worm_leave(w, now)
	fruits.erase(best.id)
	event.emit("fruit_gone", [best.id, true, HEAL, best.pos])
	return HEAL


# ================================================================ worms
func _worms_tick(now: int, players: Array) -> void:
	if now >= next_worm_check:
		next_worm_check = now + rng.randi_range(6, 12) * Config.TICK_RATE
		if worms.size() < 2:
			var cands := []
			for f in fruits.values():
				if f.state == "ground" and f.worm == 0 and now - f.ground_since > 25 * Config.TICK_RATE and _nearest(players, f.pos) > 50 * PX:
					cands.append(f)
			if not cands.is_empty() and rng.randf() < 0.55:
				_worm_arrive(cands[rng.randi() % cands.size()], now)
	for w in worms.values().duplicate():
		if w.gone:
			if now > w.gone_at:
				worms.erase(w.id)
			continue
		var cur: Array = _current(w.steps, now)
		var phase: String = cur[1]
		var near := _nearest_info(players, (fruits[w.fruit].pos if fruits.has(w.fruit) else w.pos))
		# shy: a person close by makes it duck (at once if they run past)
		if phase == "out" and (near[0] < 26 * PX or (near[0] < 34 * PX and near[1] > Sim.WALK_SPEED + 1.0)):
			_worm_duck(w, now)
		elif phase == "crawl" and (now - w.crawl_from > 6 * Config.TICK_RATE or (near[0] < 20 * PX and near[1] > Sim.WALK_SPEED + 1.0)):
			_worm_leave(w, now)   # gives up and goes underground
		elif w.steps[-1][0] <= now and phase in ["in", "out"]:
			_worm_cycle(w, now)


func _worm_arrive(f: Dictionary, now: int) -> void:
	var side := Vector3(1 if rng.randf() < 0.5 else -1, 0, 0) * (14 * PX)
	var start: Vector3 = f.pos + side
	start.y = 0.0
	var w := { "id": next_id, "fruit": f.id, "steps": [], "lived_from": 0, "calm_until": 0, "gone": false, "gone_at": 0,
		"pos": start, "crawl_from": 0 }
	next_id += 1
	f.worm = w.id
	worms[w.id] = w
	var T := Config.TICK_RATE
	var crawl := int(start.distance_to(Vector3(f.pos.x, 0, f.pos.z)) / (13 * PX * 0.5) * T)   # inchworm: moves half the time
	w.crawl_from = now + int(2.1 * T)
	_worm_steps(w, now, [
		[0, "emerge", [start]], [int(1.1 * T), "look", ["left"]], [int(1.5 * T), "look", ["right"]],
		[int(2.1 * T), "crawl", [start, Vector3(f.pos.x, 0, f.pos.z), crawl]],
		[int(2.1 * T) + crawl, "bore", ["side"]], [int(2.9 * T) + crawl, "in", []],
		[int(4.0 * T) + crawl, "out", ["top", GREETINGS[rng.randi() % GREETINGS.size()]]],
	])
	w.lived_from = now + int(4.0 * T) + crawl


func _worm_steps(w: Dictionary, now: int, steps: Array) -> void:
	w.steps = []
	for s in steps:
		w.steps.append([now + int(s[0]), s[1], s[2]])
		event.emit("worm", [w.id, w.fruit, now + int(s[0]), s[1], s[2]])


## Living in the fruit: in 1.5-4.5 s, out 3.5-7.5 s (from the top, or the side hole 40%), with a quirk now and then.
func _worm_cycle(w: Dictionary, now: int) -> void:
	var cur: String = _current(w.steps, now)[1]
	var T := Config.TICK_RATE
	if cur == "out":
		_worm_steps(w, now, [[0, "in", []], [int(rng.randf_range(1.5, 4.5) * T), "out", ["side" if rng.randf() < 0.4 else "top", ""]]])
	else:
		var stay := int(rng.randf_range(3.5, 7.5) * T)
		var steps := [[0, "out", ["side" if rng.randf() < 0.4 else "top", ""]]]
		if rng.randf() < 0.6:
			steps.append([int(stay * 0.5), "quirk", [QUIRKS[rng.randi() % QUIRKS.size()]]])
		steps.append([stay, "in", []])
		steps.append([stay + int(rng.randf_range(1.5, 4.5) * T), "out", ["top", ""]])
		_worm_steps(w, now, steps)


func _worm_duck(w: Dictionary, now: int) -> void:
	_worm_steps(w, now, [[0, "duck", []], [int(0.25 * Config.TICK_RATE), "in", []], [int(5.0 * Config.TICK_RATE), "out", ["top", ""]]])


func _worm_leave(w: Dictionary, now: int) -> void:
	_worm_steps(w, now, [[0, "leave", []]])
	w.gone = true
	w.gone_at = now + 3 * Config.TICK_RATE
	if fruits.has(w.fruit):
		fruits[w.fruit].worm = 0


# ================================================================ birds
## After a worm has lived in a fruit for 9 s (and no person is near, and it isn't in its calm spell), a bird may come
## for it: about one every 12 s. It glides in, then catches the worm out in the open or probes and pecks for it,
## and wins or loses a tug-of-war. Any person close by scares it off.
func _birds_tick(now: int, players: Array) -> void:
	var T := Config.TICK_RATE
	for w in worms.values():
		if w.gone or not fruits.has(w.fruit) or w.lived_from == 0 or now - w.lived_from < 9 * T or now < w.calm_until:
			continue
		if _bird_for(w.id) != null or _nearest(players, fruits[w.fruit].pos) < 60 * PX:
			continue
		if rng.randf() < 1.0 / (12.0 * T):
			_bird_hunt(w, now)
	for b in birds.values().duplicate():
		if now > b.end:
			birds.erase(b.id)
			continue
		if b.fleeing:
			continue
		var fpos: Vector3 = fruits[b.fruit].pos if fruits.has(b.fruit) else b.pos
		var near := _nearest_info(players, fpos)
		var bnear := _nearest_info(players, b.pos)
		var reach := 48 * PX if maxf(near[1], bnear[1]) > Sim.WALK_SPEED + 1.0 else 34 * PX
		if minf(near[0], bnear[0]) < reach and now < b.commit:
			_bird_flee(b, now)


func _bird_for(worm_id: int):
	for b in birds.values():
		if b.worm == worm_id:
			return b
	return null


func _bird_hunt(w: Dictionary, now: int) -> void:
	var f: Dictionary = fruits[w.fruit]
	var T := Config.TICK_RATE
	var species: String = ["robin", "sparrow", "bluebird"][rng.randi() % 3]
	var a := rng.randf() * TAU
	var start: Vector3 = f.pos + Vector3(cos(a), 0, sin(a)) * (140 * PX) + Vector3(0, 80 * PX, 0)
	var land: Vector3 = f.pos + Vector3(cos(a), 0, sin(a)) * (18 * PX)
	land.y = 0.0
	var fly := int(start.distance_to(land) / 2.6 * T)
	var b := { "id": next_id, "worm": w.id, "fruit": f.id, "species": species, "pos": land, "end": 0, "commit": 0,
		"fleeing": false, "steps": [] }
	next_id += 1
	birds[b.id] = b
	var steps := [[0, "fly", [species, start, land, fly]], [fly, "land", []]]
	var t := fly
	var worm_out: bool = _current(w.steps, now + fly)[1] in ["out", "quirk"]
	var catch := false
	if worm_out and rng.randf() >= 0.4:
		steps.append([t, "hop", [land, Vector3(f.pos.x, 0, f.pos.z) + (land - f.pos).normalized() * 0.2]])
		t += int(0.5 * T)
		catch = true
	else:
		if worm_out:
			steps.append([t, "say_worm", ["!"]])
			_worm_steps_at(w, now + t, [[0, "duck", []], [int(0.25 * T), "in", []]])
		for r in rng.randi_range(2, 3):
			steps.append([t, "tilt", []]); t += int(rng.randf_range(0.6, 1.0) * T)
			steps.append([t, "listen", []]); t += int(rng.randf_range(0.45, 0.8) * T)
			for k in rng.randi_range(2, 3):
				steps.append([t, "peck", []]); t += int(0.24 * T)
		catch = rng.randf() < 0.6
		if not catch:
			steps.append([t, "shrug", []]); t += int(0.8 * T)
			steps.append([t, "hop", [land, land + (land - f.pos).normalized() * 0.5]]); t += int(0.6 * T)
			steps.append([t, "say_worm", ["phew"]])
			steps.append([t, "flyoff", [false]]); t += int(2.0 * T)
	if catch:
		steps.append([t, "grab", []]); t += int(0.3 * T)
		_worm_steps_at(w, now + t, [[0, "caught", []]])
		for r in rng.randi_range(2, 3):
			steps.append([t, "heave", []]); t += int(0.74 * T)
			steps.append([t, "strain", []]); t += int(rng.randf_range(0.6, 1.0) * T)
			if rng.randf() < 0.55:
				steps.append([t, "wriggle", []]); t += int(0.6 * T)
			steps.append([t, "fight", []]); t += int(0.52 * T)
		if rng.randf() < 0.5:   # the bird wins
			steps.append([t, "pop", ["POP!"]])
			steps.append([t, "flyoff", [true]])
			_worm_steps_at(w, now + t, [[0, "taken", ["Help me!"]]])
			w.gone = true
			w.gone_at = now + t + 4 * T
			f.worm = 0
			t += int(4.0 * T)
		else:                   # the tail slips
			steps.append([t, "tumble", []])
			_worm_steps_at(w, now + t, [[0, "out", ["top", "pbbt!"]]])
			w.calm_until = now + t + 30 * T
			steps.append([t + int(2.2 * T), "flyoff", [false]])
			t += int(4.2 * T)
	b.end = now + t + 2 * T
	b.commit = now + (t if not catch else fly + int(0.4 * T))   # once it has the worm it doesn't let go for a person
	b.steps = []
	for s in steps:
		b.steps.append([now + int(s[0]), s[1], s[2]])
		event.emit("bird", [b.id, w.id, now + int(s[0]), s[1], s[2]])


## Replace the worm's schedule from tick `at` on with these steps (relative to `at`).
func _worm_steps_at(w: Dictionary, at: int, steps: Array) -> void:
	var kept := []
	for st in w.steps:
		if st[0] < at:
			kept.append(st)
	w.steps = kept
	for st in steps:
		w.steps.append([at + int(st[0]), st[1], st[2]])
		event.emit("worm", [w.id, w.fruit, at + int(st[0]), st[1], st[2]])


func _bird_flee(b: Dictionary, now: int) -> void:
	b.fleeing = true
	b.end = now + 3 * Config.TICK_RATE
	event.emit("bird", [b.id, b.worm, now, "flee", [b.pos]])
	if worms.has(b.worm):
		var w: Dictionary = worms[b.worm]
		w.calm_until = now + rng.randi_range(25, 40) * Config.TICK_RATE
		if not w.gone:
			event.emit("say", ["worm", w.id, "Phew!"])
			_worm_steps(w, now, [[0, "in", []], [int(2.0 * Config.TICK_RATE), "out", ["top", ""]]])


# ================================================================ helpers
func _nearest(players: Array, p: Vector3) -> float:
	return _nearest_info(players, p)[0]


## [distance to the nearest person, that person's speed]
func _nearest_info(players: Array, p: Vector3) -> Array:
	var best := INF
	var spd := 0.0
	for e in players:
		var d := Vector2(e[1].x - p.x, e[1].z - p.z).length()
		if d < best:
			best = d
			spd = e[2]
	return [best, spd]
