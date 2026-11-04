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
		trees.append({ "i": trees.size(), "pos": t[1], "kind": t[0], "hits": 0, "last_hit": -9999 })
	for tr in trees:
		if tr.kind != "oak":
			for s in 3:   # each fruit tree starts with three ripe
				_new_fruit(tr, s, 1.0, 0)


# ================================================================ late joiners
## Everything a new player needs to see the yard as it is now.
func full_state(now: int) -> Array:
	var out := []
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
## players: Array of [id, position, speed (m/s)].
func tick(now: int, players: Array) -> void:
	# fruit grows and drops on its own
	if now >= next_grow:
		next_grow = now + GROW_EVERY
		for tr in trees:
			if tr.kind == "oak":
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
		"land": 0, "ground_since": 0, "worm": 0, "fall": [], "end": Vector3.ZERO }
	next_id += 1
	fruits[f.id] = f
	event.emit("fruit_hang", [f.id, tr.i, slot, grow])


## Where a hanging fruit is (shared with the client's drawing).
static func slot_pos(tree_pos: Vector3, slot: int) -> Vector3:
	var s: Vector2 = SLOTS[slot]
	return tree_pos + Vector3(s.x * 24.0 * PX * 2.2, 48.0 * PX + s.y * 40.0 * PX + 0.6, 0.35 + s.y * 0.3)


## Knock a fruit loose: it falls, maybe bounces once, and lies on the ground. The path is worked out here and sent as
## parabola segments [tick, start, velocity], so every client draws the same fall.
func _drop(f: Dictionary, now: int, kick := 1.0) -> void:
	var tr: Dictionary = trees[f.tree]
	var p := slot_pos(tr.pos, f.slot)
	var v := Vector3(rng.randf_range(-14, 14) * PX * kick, rng.randf_range(0, 20) * PX * kick, rng.randf_range(4, 14) * PX * kick)
	var segs := []
	var t := now
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
			break
	f.state = "fall"
	f.fall = segs
	f.land = t
	f.end = p + Vector3(0, 0.07, 0)
	event.emit("fruit_fall", [f.id, f.tree, segs])
	event.emit("sound", ["fruitDrop", f.end])


## A tree is hit (melee or arrow) with this much damage: it shakes and drops leaves; from the 3rd hit, ripe fruit falls.
func hit_tree(i: int, damage: int, now: int, dir: Vector3) -> void:
	var tr: Dictionary = trees[i]
	tr.hits += 1 + (1 if damage >= 8 else 0) + (1 if damage >= 10 else 0)
	tr.last_hit = now
	event.emit("tree_hit", [i, dir, damage])
	if tr.kind == "oak":
		return
	var ripe := []
	for f in fruits.values():
		if f.tree == i and f.state == "hang" and f.grow >= 1.0:
			ripe.append(f)
	if ripe.is_empty():
		tr.hits = 0
		return
	if tr.hits >= 3:
		var n := mini(3 if damage >= 8 else 2, MAX_GROUND - _ground_count(i))
		for k in mini(n, ripe.size()):
			_drop(ripe[k], now, 1.0)


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
	event.emit("fruit_gone", [best.id, true])
	return 8


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
