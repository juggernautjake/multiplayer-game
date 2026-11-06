extends SceneTree
## v0.12.0: cloth keeps up with a dash. Hangs a robe and cloak (WizardGarb, the wizard's) from a still body, then dashes
## it (24 m/s for 0.15 s, Sim.DASH_SPEED), teleports it 1.5 m (a net correction) and dashes again, at 60 and at 30 fps.
## Every free point must stay within its rest length of the point above it (no stretching) and the robe's hem within
## a short trailing distance of where it hangs at rest (it used to be left far behind and whip back).
## v0.12.8: then every costume (all seven weapons) is put through every move by the real simulation (tools/cloth_rig.gd:
## standing, walking, sprinting, strafing, backpedalling, a snap turn, a running jump and landing, a dash, every move of
## the combo stepping into it, a bow / slingshot draw and release, a spell, a block, thrown, lying and getting up), drawn
## at 60 and at 30 fps: no cloth point may end up inside the body as drawn (the torso, hips, legs, head; a little more
## leeway for the arms, which the body always wins against), none may be a bad number, and none may get further from
## its anchor than its own length (plus a little: a robe pushed out by a raised knee). Then eight figures together,
## for the cost of their cloth.
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


const BODY_TOL := 0.02     # m inside the torso, hips, legs or head
const ARM_TOL := 0.08      # m inside an arm or hand (a hand pressed against the body, inside the cloth's reach)
const REACH_TOL := 0.25    # m past its length from its anchor: tabard, cloak, tails
const ROBE_REACH_TOL := 0.5   # the robe and kilt (a knee pulled up pushes them out)
# thrown by a charge the body cartwheels head over heels at up to 16 turns a second: there the cloth only has to stay
# near the body and in one piece
const THROWN_BODY_TOL := 0.08
const THROWN_REACH_TOL := 0.4
const THROWN_ROBE_REACH_TOL := 0.85
var _done := false


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var Rig = load("res://tools/cloth_rig.gd")
	var all := [Weapons.FISTS, Weapons.SWORD, Weapons.CLUB, Weapons.BOW, Weapons.SLING, Weapons.STAFF, Weapons.WAND]
	# at 60 and 30 fps, and a big (1.6x) knight and wizard (the dev console's sizes)
	var runs := []
	for tpf in [1, 2]:
		for w in all:
			runs.append([tpf, w, 1.0])
	runs.append([1, Weapons.SWORD, 1.6])
	runs.append([1, Weapons.STAFF, 1.6])
	for run in runs:
		var tpf: int = run[0]
		var w: int = run[1]
		var rig = Rig.new(root, w)
		rig.ticks_per_frame = tpf
		rig.fig.scale = Vector3.ONE * float(run[2])
		var worst := { "depth": 0.0, "arm": 0.0, "reach": 0.0, "reach_robe": 0.0 }
		var thrown := { "depth": 0.0, "arm": 0.0, "reach": 0.0, "reach_robe": 0.0 }
		var where := {}
		var nan := false
		var n := 0
		while not rig.done():
			rig.step()
			n += 1
			if not rig.drawn or n % 2 == 1:
				continue
			var m: Dictionary = rig.measure()
			nan = nan or m.nan
			if rig.phase == "thrown":
				for key in thrown:
					thrown[key] = maxf(float(thrown[key]), float(m[key]))
				continue
			for key in worst:
				if float(m[key]) > float(worst[key]):
					worst[key] = m[key]
					where[key] = "%s, %s" % [rig.phase, m.get("piece", "") + "/" + str(m.part) if key == "depth" else (m.arm_part if key == "arm" else "")]
		var wn: String = "%s at %d fps%s" % [Weapons.NAMES[w], 60 / tpf, "" if run[2] == 1.0 else ", %.1fx size" % run[2]]
		print("%s: deepest in the body %.3f m (%s), in an arm %.3f m (%s), past its reach %.2f m (%s), robe %.2f m" % [wn,
			worst.depth, where.get("depth", "-"), worst.arm, where.get("arm", "-"), worst.reach, where.get("reach", "-"), worst.reach_robe])
		var k := float(run[2])   # (a bigger body: every distance bigger)
		check(not nan, "%s: no bad numbers in the cloth" % wn)
		check(float(worst.depth) <= BODY_TOL * k, "%s: no cloth inside the body (%.3f <= %.2f m)" % [wn, worst.depth, BODY_TOL * k])
		check(float(worst.arm) <= ARM_TOL * k, "%s: none deep in an arm (%.3f <= %.2f m)" % [wn, worst.arm, ARM_TOL * k])
		check(float(worst.reach) <= REACH_TOL * k and float(worst.reach_robe) <= ROBE_REACH_TOL * k,
			"%s: every point within its length of its anchor (%.2f, robe %.2f)" % [wn, worst.reach, worst.reach_robe])
		print("%s, thrown and tumbling: in the body %.3f m, in an arm %.3f m, past its reach %.2f m, robe %.2f m" % [wn,
			thrown.depth, thrown.arm, thrown.reach, thrown.reach_robe])
		check(float(thrown.depth) <= THROWN_BODY_TOL * k and float(thrown.reach) <= THROWN_REACH_TOL * k and float(thrown.reach_robe) <= THROWN_ROBE_REACH_TOL * k,
			"%s: thrown and tumbling, the cloth stays round the body and in one piece" % wn)
		rig.fig.queue_free()
	# the cost: each costume on its own, then eight figures in different costumes running through their moves together
	var costs := []
	for w in all:
		var rig = Rig.new(root, w)
		WizardGarb.busy_usec = 0
		for i in 400:
			rig.step()
		costs.append("%s %.2f" % [Weapons.NAMES[w], WizardGarb.busy_usec / 1000.0 / 400.0])
		rig.fig.queue_free()
	print("cloth ms a frame, one figure: ", ", ".join(costs))
	var rigs := []
	for i in 8:
		rigs.append(Rig.new(root, all[i % all.size()]))
	var frames := 0
	WizardGarb.busy_usec = 0
	var t0 := Time.get_ticks_usec()
	while frames < 600:
		for r in rigs:
			r.step()
		frames += 1
	var total := float(Time.get_ticks_usec() - t0) / 1000.0
	var cloth := float(WizardGarb.busy_usec) / 1000.0
	print("8 figures, %d frames: %.3f ms a frame for everything (simulation, animation, cloth), %.3f ms of it cloth (%.3f ms a figure)" % [
		frames, total / frames, cloth / frames, cloth / frames / 8.0])
	check(cloth / frames / 8.0 < 2.5, "the cloth costs under 2.5 ms a figure a frame (headless, robes the most)")
	print("cloth_test: ", "ALL OK" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad else 0)
	return true
