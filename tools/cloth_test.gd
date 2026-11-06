extends SceneTree
## v0.12.0: cloth keeps up with a dash. Hangs a robe and cloak (WizardGarb, the wizard's) from a still body, then dashes
## it (24 m/s for 0.15 s, Sim.DASH_SPEED), teleports it 1.5 m (a net correction) and dashes again, at 60 and at 30 fps.
## Every free point must stay within its rest length of the point above it (no stretching) and the robe's hem within
## a short trailing distance of where it hangs at rest (it used to be left far behind and whip back).
##   Godot --headless --path . --script tools/cloth_test.gd

var bad := 0


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


func _make(w: Vector3) -> Array:
	var r := [[w + Vector3(0, 0.45, 0), Basis.IDENTITY, 0.12, 0.11], [w + Vector3(0, 0.36, 0), Basis.IDENTITY, 0.29, 0.21],
		[w + Vector3(0, 0.2, 0), Basis.IDENTITY, 0.28, 0.22], [w, Basis.IDENTITY, 0.25, 0.21]]
	for i in 6:
		var u := float(i + 1) / 6.0
		r.append([w - Vector3(0, (w.y - 0.03) * u, 0), Basis.IDENTITY, lerpf(0.27, 0.42, u), lerpf(0.24, 0.38, u)])
	return r


## Runs the robe through still -> dash -> teleport -> dash; returns [max hem trail (m), max stretch ratio].
func _run(lag: float, fps: float) -> Array:
	var g := WizardGarb.new()
	root.add_child(g)
	g.set_kind(WizardGarb.Kind.WIZARD)
	g.lag_speed = lag
	var waist := Vector3(0, 1.05, 0)
	var f := { "rings": [], "pinned": 4, "colliders": [], "ground": 0.0, "vel": Vector3.ZERO,
		"head_top": Vector3(0, 1.75, 0), "head_c": Vector3(0, 1.6, 0), "head_r": 0.17, "up": Vector3.UP,
		"face": Vector3.FORWARD, "neck": Vector3(0, 1.5, 0), "hat_h": 0.7, "hat_r": 0.2, "brim_r": 0.4, "visible": true }
	var dt := 1.0 / fps
	var trail := 0.0
	var stretch := 0.0
	var moves := []   # per frame: the body's step
	for i in int(fps * 2):
		moves.append(Vector3.ZERO)
	for leg in 3:
		if leg == 1:
			moves.append(Vector3(1.5, 0, 0))   # a correction snap
		for i in int(fps * 0.15):
			moves.append(Vector3(0, 0, -Sim.DASH_SPEED * dt))
		for i in int(fps * 0.1):
			moves.append(Vector3.ZERO)
	for n in moves.size():
		var mv: Vector3 = moves[n]
		waist += mv
		f.rings = _make(waist)
		f.head_top = waist + Vector3(0, 0.7, 0)
		f.head_c = waist + Vector3(0, 0.55, 0)
		f.neck = waist + Vector3(0, 0.45, 0)
		f.vel = mv / dt
		g.update(dt, f)
		if n < int(fps * 2):
			continue
		var rings: Array = f.rings
		for i in range(4, g._rows):
			for j in WizardGarb.STRANDS:
				var k := i * WizardGarb.STRANDS + j
				var want := ((rings[i] as Array)[0] as Vector3).distance_to((rings[i - 1] as Array)[0]) * 1.01
				stretch = maxf(stretch, (g._p[k] as Vector3).distance_to(g._p[k - WizardGarb.STRANDS]) / want)
				if i == g._rows - 1:
					var rest := g._ring_pt(rings[i], TAU * j / WizardGarb.STRANDS)
					trail = maxf(trail, Vector2(g._p[k].x - rest.x, g._p[k].z - rest.z).length())
		for k in g._cp.size():
			if k >= WizardGarb.CLOAK_COLS:
				var seg := (g._cp[k] as Vector3).distance_to(g._cp[k - WizardGarb.CLOAK_COLS])
				var hang_len: float = ((rings[0] as Array)[0] as Vector3).y * 0.86 / 5.0
				stretch = maxf(stretch, seg / hang_len)
	g.queue_free()
	return [trail, stretch]


func _initialize() -> void:
	var old := _run(1e9, 60.0)
	print("without carrying: hem trails up to %.2f m" % old[0])
	for fps in [60.0, 30.0]:
		var r := _run(7.0, fps)
		print("at %d fps: hem trails up to %.2f m, segments stretch to x%.3f" % [fps, r[0], r[1]])
		check(r[1] < 1.03, "after a dash and a snap, every cloth point stays within its rest length of the one above (%d fps)" % fps)
		check(r[0] < 0.7, "the hem trails the body by under 0.7 m through a dash (%d fps)" % fps)
		check(r[0] < old[0] * 0.75 or old[0] < 0.7, "and clearly less than the cloth left behind before (%d fps)" % fps)
	print("cloth_test: ", "ALL OK" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad else 0)
