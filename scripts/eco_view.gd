## Draws the living yard from the server's Ecology events: oaks and fruit trees (shaking and shedding leaves when
## hit), hanging and falling fruit, worms and birds with their little routines, and speech bubbles. Everything runs on
## the same delayed clock other players are drawn on (Net.render_tick), so it lines up for everyone.
class_name EcoView
extends Node3D

const SPECIES := { "robin": [Color("8a5a3c"), Color("e2683a")], "sparrow": [Color("8b6f4e"), Color("d9c7a8")],
	"bluebird": [Color("3b6fd1"), Color("e8a86a")] }

var net: Net
var trees: Array = []      # { root, crown, wobble, wv, kind, pos }
var fruits := {}           # id -> { node, tree, slot, state, segs, grow }
var worms := {}            # id -> { node, segs: [MeshInstance3D], steps: [[tick, phase, data]], fruit }
var birds := {}            # id -> { node, body, head, wings, steps, species }


func setup(n: Net) -> void:
	net = n
	net.eco.connect(_on_event)
	for t in WorldLayout.TREES:
		_make_tree(t[0], t[1])


func now_tick(frac: float) -> float:
	return net.render_tick + frac


# ================================================================ events
func _on_event(kind: String, a: Array) -> void:
	match kind:
		"fruit_hang":
			_fruit(a[0], a[1]).state = "hang"
			fruits[a[0]].slot = a[2]
			fruits[a[0]].grow = a[3]
		"fruit_fall":
			var f := _fruit(a[0], a[1])
			f.state = "fall"
			f.segs = a[2]
		"fruit_ground":
			var f := _fruit(a[0], a[1])
			f.state = "ground"
			f.segs = [[0, a[2], Vector3.ZERO]]
		"fruit_gone":
			if fruits.has(a[0]):
				var f: Dictionary = fruits[a[0]]
				if a[1]:
					var at: Vector3 = (f.node as Node3D).global_position
					Fx.word(get_parent(), at, "munch!", Color("ffe08a"))
					if a.size() > 2:   # v0.12.0 it healed: +N, a green sparkle rising, a crunch
						Fx.word(get_parent(), at + Vector3(0, 1.4, 0), "+%d" % int(a[2]), Color("7dff8a"))
						Fx.burst(get_parent(), at + Vector3(0, 0.4, 0), Vector3.UP, Color("7dff8a"), 12, 2.2, 0.05)
						_crunch(at)
				(f.node as Node3D).queue_free()
				fruits.erase(a[0])
		"tree_hit":
			var tr: Dictionary = trees[a[0]]
			var d: Vector3 = a[1]
			tr.wv += (1.0 if d.x >= 0.0 else -1.0) * minf(2.6, float(a[2]) / 4.0) * 0.5
			var leaves := 3 + 2 * mini(int(a[2]) / 3, 6)
			Fx.burst(get_parent(), tr.pos + Vector3(0, 3.2 if tr.kind == "oak" else 2.6, 0), Vector3.UP, Color("4f8a3a"), leaves, 2.5, 0.08)
		"tree_fell":   # v0.12.0 Thunderhorn splintered it: it topples away from him in a burst of splinters
			var tr: Dictionary = trees[a[0]]
			if tr.get("felled", false):
				return
			tr.felled = true
			var d: Vector3 = a[1]
			if d.length() < 0.01:
				tr.fall_axis = Vector3.RIGHT
				(tr.root as Node3D).rotation = Vector3(PI / 2.0 * 0.95, 0, 0)
				tr.fall_t = 1.0
			else:
				tr.fall_axis = Vector3.UP.cross(Vector3(d.x, 0, d.z).normalized()).normalized()
				tr.fall_t = 0.0
				Fx.burst(get_parent(), tr.pos + Vector3(0, 1.0, 0), Vector3(d.x, 0.5, d.z).normalized(), Color("8a6440"), 30, 7.0, 0.09)
				Fx.burst(get_parent(), tr.pos + Vector3(0, 3.0, 0), Vector3.UP, Color("4f8a3a"), 24, 4.0, 0.1)
				MotionFx.land(get_parent(), tr.pos, 1.5)
				_crack_sound(tr.pos)
		"tree_up":
			var tr: Dictionary = trees[a[0]]
			tr.felled = false
			(tr.root as Node3D).rotation = Vector3.ZERO
			(tr.root as Node3D).position = tr.pos
		"fruit_splat":   # v0.12.0 trampled: a red-brown mush splat that fades away after a few seconds
			if fruits.has(a[0]):
				((fruits[a[0]] as Dictionary).node as Node3D).queue_free()
				fruits.erase(a[0])
			_splat(a[1])
		"worm":
			var w := _worm(a[0], a[1])
			_add_step(w.steps, [a[2], a[3], a[4]])
		"bird":
			var b := _bird(a[0], a[1], a[3], a[4])
			_add_step(b.steps, [a[2], a[3], a[4]])
		"say":
			var who: Dictionary = worms.get(a[1], {}) if a[0] == "worm" else birds.get(a[1], {})
			if not who.is_empty():
				_bubble((who.node as Node3D).global_position + Vector3(0, 0.35, 0), str(a[2]))


func _add_step(steps: Array, s: Array) -> void:
	# keep steps in time order; a newer plan replaces what was planned from its start on
	var keep := []
	for x in steps:
		if x[0] < s[0]:
			keep.append(x)
	steps.clear()
	steps.append_array(keep)
	steps.append(s)


# ================================================================ per frame
func _process(delta: float) -> void:
	if net == null:
		return
	var t := now_tick(Engine.get_physics_interpolation_fraction())
	for tr in trees:   # v0.12.0: a felled tree keeps falling over (accelerating), then lies there
		if tr.get("felled", false) and float(tr.fall_t) < 1.0:
			tr.fall_t = minf(float(tr.fall_t) + delta * 0.9, 1.0)
			var k := float(tr.fall_t) * float(tr.fall_t)
			(tr.root as Node3D).basis = Basis(tr.fall_axis, PI / 2.0 * 0.95 * k)
			if tr.fall_t >= 1.0:
				MotionFx.land(get_parent(), tr.pos + Vector3.UP.cross(tr.fall_axis) * -2.5, 2.0)
	for tr in trees:   # a damped wobble when hit (village spring: k 80, c 6)
		var acc: float = -80.0 * tr.wobble - 6.0 * tr.wv
		tr.wv += acc * delta
		tr.wobble += tr.wv * delta
		(tr.crown as Node3D).rotation.z = tr.wobble * 0.08
	for id in fruits.keys():
		_draw_fruit(fruits[id], t)
	for id in worms.keys():
		if not _draw_worm(worms[id], t):
			(worms[id].node as Node3D).queue_free()
			worms.erase(id)
	for id in birds.keys():
		if not _draw_bird(birds[id], t):
			(birds[id].node as Node3D).queue_free()
			birds.erase(id)


func _current(steps: Array, t: float) -> Array:
	var cur: Array = []
	var nxt := INF
	for s in steps:
		if s[0] <= t:
			cur = s
		elif s[0] < nxt:
			nxt = s[0]
	return [cur, nxt]


# ================================================================ trees
func _make_tree(kind: String, pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var tk: Array = WorldLayout.TRUNK[kind]
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = tk[0] * 0.8
	cm.bottom_radius = tk[0] * 1.15
	cm.height = tk[1]
	trunk.mesh = cm
	trunk.position.y = tk[1] / 2.0
	trunk.material_override = _mat(Color("6b4a2e"))
	root.add_child(trunk)
	var crown := Node3D.new()           # pivots at the top of the trunk, so it sways
	crown.position.y = tk[1] * 0.85
	root.add_child(crown)
	var leaf := Color("3f7d35") if kind == "oak" else Color("4f9a3e")
	var big := 1.0 if kind == "oak" else 0.7
	for c in [[0, 1.2, 0, 1.5], [0.9, 0.9, 0.3, 1.1], [-0.9, 0.85, -0.2, 1.15], [0.2, 0.95, 0.9, 1.05], [-0.3, 1.0, -0.9, 1.1], [0.1, 1.8, 0.1, 1.0]]:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = c[3] * big
		sm.height = c[3] * big * 2.0
		s.mesh = sm
		s.position = Vector3(c[0], c[1], c[2]) * big
		s.material_override = _mat(leaf.lightened(randf_range(-0.08, 0.1)))
		crown.add_child(s)
	trees.append({ "root": root, "crown": crown, "wobble": 0.0, "wv": 0.0, "kind": kind, "pos": pos, "felled": false, "fall_t": 1.0, "fall_axis": Vector3.RIGHT })


# ================================================================ fruit
func _fruit(id: int, tree: int) -> Dictionary:
	if not fruits.has(id):
		var kind: String = WorldLayout.TREES[tree][0]
		var n := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		var apple := kind != "pear"   # v0.12.0: oaks bear apples too
		sm.height = 0.18 if apple else 0.24
		n.mesh = sm
		n.material_override = _mat(Color("d8343a") if apple else Color("cfc35a"), 0.5)
		var stem := MeshInstance3D.new()
		var st := CylinderMesh.new()
		st.top_radius = 0.008
		st.bottom_radius = 0.012
		st.height = 0.06
		stem.mesh = st
		stem.position.y = sm.height / 2.0 + 0.02
		stem.material_override = _mat(Color("5a3a20"))
		n.add_child(stem)
		add_child(n)
		fruits[id] = { "node": n, "tree": tree, "slot": 0, "state": "hang", "segs": [], "grow": 1.0 }
	return fruits[id]


func _draw_fruit(f: Dictionary, t: float) -> void:
	var n: MeshInstance3D = f.node
	if f.state == "hang":
		var tr: Dictionary = trees[f.tree]
		var p := Ecology.slot_pos(tr.pos, f.slot, tr.kind)
		p.x += sin(Time.get_ticks_msec() * 0.002 + f.slot) * 0.015 + tr.wobble * 0.12   # sways with wind and shakes
		n.global_position = p
		var g: float = f.grow
		n.scale = Vector3.ONE * (0.5 + 0.5 * g)
		return
	# falling, rolling or resting: the server's path segments; the fruit turns over as it rolls (distance / radius)
	var p := Ecology.path_pos(f.segs, t)
	var last: Vector3 = f.get("last", p)
	var d := p - last
	var flat := Vector2(d.x, d.z).length()
	if flat > 1e-5 and flat < 1.0:
		var axis := Vector3(d.z, 0.0, -d.x).normalized()
		n.rotate(axis, flat / Ecology.FRUIT_R * (1.0 if p.y < Ecology.FRUIT_R + 0.02 else 0.35))
	f.last = p
	n.global_position = p
	n.scale = Vector3.ONE


# ================================================================ worms
func _worm(id: int, fruit: int) -> Dictionary:
	if not worms.has(id):
		var root := Node3D.new()
		add_child(root)
		var segs := []
		for i in 5:
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.028 - i * 0.002
			sm.height = sm.radius * 2.0
			s.mesh = sm
			s.material_override = _mat(Color("f57a8e") if i % 2 == 0 else Color("ff9aa8"), 0.6)
			root.add_child(s)
			segs.append(s)
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.008
		em.height = 0.016
		eye.mesh = em
		eye.material_override = _mat(Color("1d1630"))
		segs[0].add_child(eye)
		eye.position = Vector3(0.012, 0.012, -0.022)
		worms[id] = { "node": root, "segs": segs, "steps": [], "fruit": fruit, "head": Vector3.ZERO }
	return worms[id]


## Place the worm for its current phase. -> false once it's gone.
func _draw_worm(w: Dictionary, t: float) -> bool:
	var cn := _current(w.steps, t)
	var cur: Array = cn[0]
	var root: Node3D = w.node
	if cur.is_empty():
		root.visible = false
		return true
	var phase: String = cur[1]
	var data: Array = cur[2]
	var age := (t - float(cur[0])) * Config.DT
	var fpos := Vector3.ZERO
	if fruits.has(w.fruit):
		fpos = (fruits[w.fruit].node as Node3D).global_position
	root.visible = true
	var pts := []
	match phase:
		"emerge", "look":
			var at: Vector3 = data[0] if phase == "emerge" else w.get("base", fpos)
			w.base = at
			var rise := clampf(age, 0.0, 1.0) if phase == "emerge" else 1.0
			var turn := 0.0 if phase == "emerge" else (-0.6 if data[0] == "left" else 0.6)
			for i in 5:
				pts.append(at + Vector3(sin(turn) * 0.02 * (4 - i), (0.02 + 0.03 * (4 - i)) * rise - 0.05 * (1.0 - rise), 0))
		"crawl":
			var a: Vector3 = data[0]
			var b: Vector3 = data[1]
			var dur := maxf(float(data[2]) * Config.DT, 0.01)
			var k := clampf(age / dur, 0.0, 1.0)
			var gait := sin(age / 0.625 * TAU)               # inchworm: arch up, stretch out
			var head := a.lerp(b, k)
			var dir := (b - a).normalized() if a.distance_to(b) > 0.01 else Vector3.RIGHT
			for i in 5:
				var back := float(i) * (0.028 - 0.008 * maxf(gait, 0.0))
				var arch := sin(float(i) / 4.0 * PI) * 0.03 * maxf(gait, 0.0)
				pts.append(head - dir * back + Vector3(0, 0.02 + arch, 0))
			w.base = head
		"bore":
			var k := clampf(age / 0.8, 0.0, 1.0)
			for i in 5:
				pts.append(fpos + Vector3(-0.1 + 0.02 * i, -0.05, 0).lerp(Vector3.ZERO, k) + Vector3(0, 0, -0.02 * (1.0 - k) * i))
		"in", "duck", "leave":
			if phase == "leave" and age < 1.0:
				var at: Vector3 = w.get("base", fpos)
				for i in 5:
					pts.append(at + Vector3(0, 0.05 - age * 0.1, 0))
			else:
				root.visible = false
				return phase != "leave" or age < 3.0
		"out", "quirk":
			var top := fpos + Vector3(0, 0.09, 0)
			var rise := clampf(age / 0.42, 0.0, 1.0) if phase == "out" else 1.0
			var sway := sin(age * 2.2) * 0.012
			var q := "" if phase == "out" else str(data[0])
			for i in 4:
				var h := (0.035 * (4 - i)) * rise
				var bend := sway * (4 - i)
				if q == "stretch":
					h *= 1.35
				if q == "wave":
					bend += sin(age * 12.0) * 0.01 * (4 - i)
				pts.append(top + Vector3(bend, h, 0))
			pts.append(top)
			if phase == "out" and data.size() > 1 and str(data[1]) != "" and not w.get("said_%d" % int(cur[0]), false):
				w["said_%d" % int(cur[0])] = true
				_bubble(top + Vector3(0, 0.3, 0), str(data[1]))
			if phase == "quirk" and not w.get("said_%d" % int(cur[0]), false):
				w["said_%d" % int(cur[0])] = true
				var words := { "yawn": "*yawn*", "munch": "munch munch", "wave": "hi!", "stretch": "", "burp": "*burp*", "look": "" }
				if str(words.get(q, "")) != "":
					_bubble(top + Vector3(0, 0.3, 0), words[q])
		"caught":
			for i in 5:
				pts.append(fpos + Vector3(0.03 * i, 0.09 + 0.02 * i, 0))
		"taken":
			# dangles from the beak of the bird flying off with it
			var b = _bird_carrying(w)
			if b == null:
				root.visible = false
				return age < 4.0
			var beak: Vector3 = (b.head as Node3D).global_position + Vector3(0, -0.05, 0)
			for i in 5:
				pts.append(beak + Vector3(sin(age * 9.0 + i) * 0.02, -0.035 * i, 0))
			if not w.get("said_taken", false):
				w.said_taken = true
				_bubble(beak, str(data[0]))
			if age > 4.0:
				return false
		_:
			root.visible = false
	var segs: Array = w.segs
	for i in segs.size():
		if i < pts.size():
			(segs[i] as Node3D).global_position = pts[i]
	return true


func _bird_carrying(w: Dictionary):
	for b in birds.values():
		if b.worm == w.get("id_hint", -1) or b.get("carry_fruit", -1) == w.fruit:
			return b
	for b in birds.values():
		if b.fruit_hint == w.fruit:
			return b
	return null


# ================================================================ birds
func _bird(id: int, worm: int, phase: String, data: Array) -> Dictionary:
	if not birds.has(id):
		var species: String = data[0] if phase == "fly" and data.size() > 0 and data[0] is String else "sparrow"
		var col: Array = SPECIES.get(species, SPECIES["sparrow"])
		var root := Node3D.new()
		add_child(root)
		var body := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.09
		bm.height = 0.16
		body.mesh = bm
		body.scale = Vector3(0.9, 0.9, 1.25)
		body.position.y = 0.11
		body.material_override = _mat(col[0])
		root.add_child(body)
		var breast := MeshInstance3D.new()
		var brm := SphereMesh.new()
		brm.radius = 0.065
		brm.height = 0.12
		breast.mesh = brm
		breast.position = Vector3(0, -0.02, -0.04)
		breast.material_override = _mat(col[1])
		body.add_child(breast)
		var head := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.055
		hm.height = 0.11
		head.mesh = hm
		head.position = Vector3(0, 0.2, -0.09)
		head.material_override = _mat(col[0])
		root.add_child(head)
		var beak := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.018
		cm.height = 0.05
		beak.mesh = cm
		beak.rotation.x = -PI / 2.0
		beak.position = Vector3(0, -0.005, -0.065)
		beak.material_override = _mat(Color("e8a040"))
		head.add_child(beak)
		for sx in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			var em := SphereMesh.new()
			em.radius = 0.01
			em.height = 0.02
			eye.mesh = em
			eye.position = Vector3(sx * 0.035, 0.015, -0.03)
			eye.material_override = _mat(Color("1d1630"))
			head.add_child(eye)
		var wings := []
		for sx in [-1.0, 1.0]:
			var wpiv := Node3D.new()
			wpiv.position = Vector3(sx * 0.07, 0.14, 0.0)
			root.add_child(wpiv)
			var wm := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = Vector3(0.14, 0.015, 0.1)
			wm.mesh = bx
			wm.position = Vector3(sx * 0.07, 0, 0)
			wm.material_override = _mat(col[0].darkened(0.15))
			wpiv.add_child(wm)
			wings.append(wpiv)
		birds[id] = { "node": root, "body": body, "head": head, "wings": wings, "steps": [], "worm": worm, "pos": Vector3.ZERO,
			"fruit_hint": worms[worm].fruit if worms.has(worm) else -1, "said": {} }
	return birds[id]


## Place the bird for its current phase. -> false once it has gone.
func _draw_bird(b: Dictionary, t: float) -> bool:
	var cn := _current(b.steps, t)
	var cur: Array = cn[0]
	var root: Node3D = b.node
	if cur.is_empty():
		root.visible = false
		return true
	root.visible = true
	var phase: String = cur[1]
	var data: Array = cur[2]
	var age := (t - float(cur[0])) * Config.DT
	var pos: Vector3 = b.pos
	var flap := 0.0
	var tilt := 0.0
	var dip := 0.0
	var on_back := false
	var fpos := pos
	if b.fruit_hint >= 0 and fruits.has(b.fruit_hint):
		fpos = (fruits[b.fruit_hint].node as Node3D).global_position
	match phase:
		"fly":
			var a: Vector3 = data[1]
			var c: Vector3 = data[2]
			var dur := maxf(float(data[3]) * Config.DT, 0.01)
			var k := clampf(age / dur, 0.0, 1.0)
			pos = a.lerp(c, 1.0 - (1.0 - k) * (1.0 - k)) + Vector3(0, sin(age * 6.0) * 0.06 * (1.0 - k), 0)   # glide in, slowing
			flap = sin(age * 28.0)
			root.look_at(Vector3(c.x, root.global_position.y, c.z) if root.global_position.distance_to(c) > 0.05 else root.global_position + Vector3.FORWARD, Vector3.UP)
		"land":
			flap = sin(age * 28.0) * maxf(0.0, 1.0 - age * 4.0)
		"hop":
			var a: Vector3 = data[0]
			var c: Vector3 = data[1]
			var k := clampf(age / 0.5, 0.0, 1.0)
			pos = a.lerp(c, k) + Vector3(0, absf(sin(k * PI * 2.0)) * 0.06, 0)
		"tilt":
			tilt = 0.5
		"listen":
			tilt = -0.3
		"peck", "grab":
			dip = absf(sin(age / 0.24 * PI)) * 0.6
		"heave", "strain", "wriggle", "fight":
			var pull := sin(age * (9.0 if phase == "heave" else 22.0)) * 0.03
			pos = b.get("anchor", pos) + (pos - fpos).normalized() * (0.08 + pull) if b.has("anchor") else pos
			if not b.has("anchor"):
				b.anchor = pos
			dip = 0.3
			flap = sin(age * 20.0) * (0.6 if phase == "fight" else 0.2)
		"pop", "flyoff", "flee":
			var away := (pos - fpos)
			away.y = 0.0
			away = away.normalized() if away.length() > 0.01 else Vector3.BACK
			var spd := 6.0 if phase == "flee" else 3.5
			pos = b.get("leave_from", pos) + away * spd * age + Vector3(0, 2.5 * age, 0)
			if not b.has("leave_from"):
				b.leave_from = b.pos
				if phase == "flee":
					Fx.burst(get_parent(), b.pos + Vector3(0, 0.15, 0), Vector3.UP, (SPECIES.get(b.get("species", "sparrow"), SPECIES["sparrow"]) as Array)[0], 8, 2.0, 0.05)
			flap = sin(age * 30.0)
			if phase == "flyoff" and data.size() > 0 and data[0]:
				b.carry_fruit = b.fruit_hint
			if age > 3.0:
				return false
		"tumble":
			on_back = true
		"shrug":
			tilt = sin(age * 10.0) * 0.3
		"say_worm":
			if not b.said.has(int(cur[0])) and worms.has(b.worm):
				b.said[int(cur[0])] = true
				_bubble((worms[b.worm].node as Node3D).global_position + Vector3(0, 0.3, 0), str(data[0]))
	if phase == "pop" and not b.said.has(int(cur[0])):
		b.said[int(cur[0])] = true
		_bubble(pos + Vector3(0, 0.4, 0), "POP!")
	b.pos = pos if phase in ["fly", "hop"] else b.pos
	root.global_position = pos
	if phase != "fly" and phase not in ["pop", "flyoff", "flee"]:
		var face := fpos - pos
		face.y = 0.0
		if face.length() > 0.02:
			root.look_at(pos + face, Vector3.UP)
	(b.head as Node3D).rotation = Vector3(-dip, 0, tilt)
	for i in 2:
		(b.wings[i] as Node3D).rotation.z = (1.0 if i == 0 else -1.0) * flap * 0.9
	root.rotation.z = PI if on_back else 0.0
	if on_back:
		root.global_position = pos + Vector3(0, 0.22, 0)
	return true


# ================================================================ helpers
func _bubble(at: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 34
	l.outline_size = 10
	l.modulate = Color.WHITE
	get_parent().add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "global_position", at + Vector3(0, 0.25, 0), 1.6)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(1.1)
	tw.tween_callback(l.queue_free)


var _sounds := {}


func _crunch(at: Vector3) -> void:
	_play("eat", at, -9.0)   # v0.12.9: a nicer crunch, and quieter (Jacob)


func _crack_sound(at: Vector3) -> void:
	_play("slam", at, -2.0)
	_play("scrape", at, 2.0)


func _play(key: String, at: Vector3, db: float) -> void:
	if not _sounds.has(key):
		_sounds[key] = Synth.fx(key)
	var d := 0.0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		d = cam.global_position.distance_to(at)
	Synth.play(get_parent(), _sounds[key], db - clampf(d * 0.25, 0.0, 30.0))


func _splat(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.28
	cm.bottom_radius = 0.32
	cm.height = 0.02
	cm.radial_segments = 10
	mi.mesh = cm
	var m := _mat(Color("8a2a1e"), 0.4)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	get_parent().add_child(mi)
	mi.global_position = Vector3(at.x, 0.015, at.z)
	mi.scale = Vector3(randf_range(0.8, 1.3), 1, randf_range(0.7, 1.1))
	mi.rotation.y = randf() * TAU
	Fx.burst(get_parent(), Vector3(at.x, 0.2, at.z), Vector3.UP, Color("c23a2a"), 10, 3.0, 0.05)
	Fx.burst(get_parent(), Vector3(at.x, 0.2, at.z), Vector3.UP, Color("e8d9a0"), 6, 2.5, 0.04)
	var tw := mi.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.5)
	tw.tween_callback(mi.queue_free)


func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
