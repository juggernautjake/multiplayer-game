extends SceneTree
## Hangs a robe (WizardGarb) from a still body for 2 s, then runs with it at 10 m/s, printing the height of each row of
## the back strand. A quick check that the cloth hangs to the floor in even steps and trails without flying up.
##   Godot --headless --path . --script tools/garb_check.gd
func _init() -> void:
	var g := WizardGarb.new()
	root.add_child(g)
	g.set_kind(WizardGarb.Kind.SHADOW)
	var waist := Vector3(0, 1.05, 0)
	var f := { "rings": [], "pinned": 4, "colliders": [], "ground": 0.0, "vel": Vector3.ZERO,
		"head_top": Vector3(0, 1.75, 0), "head_c": Vector3(0, 1.6, 0), "head_r": 0.17, "up": Vector3.UP,
		"face": Vector3.FORWARD, "neck": Vector3(0, 1.5, 0), "hat_h": 0.7, "hat_r": 0.2, "brim_r": 0.4, "visible": true }
	var make := func(w: Vector3) -> Array:
		var r := [[w + Vector3(0, 0.45, 0), Basis.IDENTITY, 0.12, 0.11], [w + Vector3(0, 0.36, 0), Basis.IDENTITY, 0.29, 0.21],
			[w + Vector3(0, 0.2, 0), Basis.IDENTITY, 0.28, 0.22], [w, Basis.IDENTITY, 0.25, 0.21]]
		for i in 6:
			var u := float(i + 1) / 6.0
			r.append([w - Vector3(0, (w.y - 0.03) * u, 0), Basis.IDENTITY, lerpf(0.27, 0.42, u), lerpf(0.24, 0.38, u)])
		return r
	f.rings = make.call(waist)
	for i in 120:
		g.update(1.0 / 60.0, f)
	_print(g, "still")
	for i in 60:
		waist += Vector3(0, 0, -10.0 / 30.0)
		f.rings = make.call(waist)
		f.vel = Vector3(0, 0, -10)
		g.update(1.0 / 30.0, f)
	_print(g, "running")
	quit()


func _print(g: WizardGarb, what: String) -> void:
	var ys := []
	for r in g._rows:
		ys.append(snappedf(g._p[r * WizardGarb.STRANDS + 5].y, 0.01))
	print(what, ": back strand heights ", ys)
