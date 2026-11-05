extends SceneTree
## Hangs a robe from a still body for 2 s and prints where each row ends up (a quick check of the cloth).
func _init() -> void:
	var g := WizardGarb.new()
	root.add_child(g)
	g.set_kind(WizardGarb.Kind.WIZARD)
	var f := { "hip": Vector3(0, 0.84, 0), "basis": Basis.IDENTITY, "top_r": 0.36, "hem_r": 0.5, "len": 0.76, "colliders": [],
		"ground": 0.0, "vel": Vector3.ZERO, "head_top": Vector3(0, 1.7, 0), "head_c": Vector3(0, 1.4, 0), "head_r": 0.44,
		"up": Vector3.UP, "face": Vector3.FORWARD, "neck": Vector3(0, 0.9, 0), "hat_h": 1.0, "hat_r": 0.36, "brim_r": 0.6, "visible": true }
	for i in 120:
		g.update(1.0 / 60.0, f)
	for i in 90:   # running at 10 m/s along -z (30 fps)
		f.hip = (f.hip as Vector3) + Vector3(0, 0, -10.0 / 30.0)
		f.vel = Vector3(0, 0, -10)
		g.update(1.0 / 30.0, f)
		if i % 15 == 0:
			var ys := []
			for r in WizardGarb.ROWS:
				ys.append(snappedf(g._p[r * WizardGarb.STRANDS + 4].y, 0.01))
			print("run ", i, " back-strand ys ", ys)
	for r in WizardGarb.ROWS:
		var p: Vector3 = g._p[r * WizardGarb.STRANDS]
		print("row %d  y %.2f  r %.2f" % [r, p.y, Vector2(p.x, p.z).length()])
	quit()
