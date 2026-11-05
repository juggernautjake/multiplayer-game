extends SceneTree
## The wizard's tower can be climbed, and the staff and wand follow their rules, in the shared simulation:
##   every step of the tower is reachable with one jump from the step below, and the top from the last step;
##   the teleport goes up to 18 m (five dashes) toward the crosshair and never ends inside a pillar;
##   staff spells cost mana and can't be cast without it; wand spells don't use mana but each has its own recharge;
##   a stun holds you in place for 3 s; a shield lasts 5 s.
##   Godot --headless --path . --script tools/magic_test.gd

var bad := 0

func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


func tower_boxes() -> Array:
	var steps := []
	var top: WorldLayout.Box
	for b: WorldLayout.Box in WorldLayout.boxes():
		if b.kind == "step":
			steps.append(b)
		elif b.kind == "tower":
			top = b
	steps.sort_custom(func(a, b): return a.h < b.h)
	steps.append(top)
	return steps


## Stand on `a`, face `b`, jump and steer toward its middle. True if you end up standing on top of `b`.
func jump_across(a: WorldLayout.Box, b: WorldLayout.Box) -> bool:
	var s := Sim.PlayerState.new()
	s.pos = Vector3(a.cx, a.h, a.cz)
	s.grounded = true
	for t in 120:
		var to := Vector2(b.cx - s.pos.x, b.cz - s.pos.z)
		var yaw := atan2(-to.x, -to.y)
		var btn := 0
		if to.length() > 0.35:
			btn |= Sim.Btn.FORWARD
		if t == 4:
			btn |= Sim.Btn.JUMP
		Sim.step(s, Sim.PlayerInput.new(t, btn, yaw))
	return absf(s.pos.y - b.h) < 0.02 and s.grounded and absf(s.pos.x - b.cx) <= b.hx + 0.05 and absf(s.pos.z - b.cz) <= b.hz + 0.05


func _init() -> void:
	# 1) the climb
	var steps := tower_boxes()
	check(steps.size() == WorldLayout.TOWER_STEPS + 1, "the tower has %d steps and its top" % WorldLayout.TOWER_STEPS)
	var ground := WorldLayout.Box.new()
	var first: WorldLayout.Box = steps[0]
	var out := Vector2(first.cx - WorldLayout.TOWER_C.x, first.cz - WorldLayout.TOWER_C.y).normalized() * 3.0
	ground.cx = first.cx + out.x
	ground.cz = first.cz + out.y
	ground.h = 0.0
	check(jump_across(ground, first), "from the ground onto the first step (%.1f m)" % first.h)
	for i in range(steps.size() - 1):
		var a: WorldLayout.Box = steps[i]
		var b: WorldLayout.Box = steps[i + 1]
		check(jump_across(a, b), "step %d (%.1f m) -> %s (%.1f m)" % [i + 1, a.h, "the top" if i == steps.size() - 2 else "step %d" % (i + 2), b.h])
	var staff_at := Vector3.ZERO
	for sp in WorldLayout.ITEM_SPAWNS:
		if int(sp[0]) == Weapons.Item.STAFF:
			staff_at = sp[1]
	check(absf(staff_at.y - WorldLayout.TOWER_TOP) < 0.01 and Vector2(staff_at.x, staff_at.z).distance_to(WorldLayout.TOWER_C) < 0.1, "the staff lies on the top (%.1f m up)" % staff_at.y)

	# 2) teleport: up to five dashes, never into a pillar
	var dash := Sim.DASH_SPEED * Sim.DASH_TICKS * Config.DT
	var reach := float(Weapons.spell(Weapons.WAND, 1).range)
	check(absf(reach - 5.0 * dash) < 0.01, "teleport reach %.1f m = five dashes (%.1f m each)" % [reach, dash])
	var far := Sim.teleport_target(Vector3(0, 0, 0), 0.0, Vector3(0, 0, -50), reach)
	check(absf(Vector2(far.x, far.z).length() - reach) < 0.6, "aimed far away it goes the full %.1f m (%.1f)" % [reach, Vector2(far.x, far.z).length()])
	var near := Sim.teleport_target(Vector3(0, 0, 0), 0.0, Vector3(0, 0, -7.0), reach)
	check(absf(Vector2(near.x, near.z).length() - 7.0) < 0.51, "aimed at the ground 7 m away it lands there (%.1f m), not the full reach" % Vector2(near.x, near.z).length())
	var step5: WorldLayout.Box = steps[4]
	var onto := Sim.teleport_target(Vector3(step5.cx + 6.0, 0, step5.cz), PI / 2.0, Vector3(step5.cx, step5.h, step5.cz), reach)
	check(absf(onto.y - step5.h) < 0.1 and absf(onto.x - step5.cx) < step5.hx + 0.1, "aimed at a pillar's top it lands on top (%.1f m up)" % onto.y)
	var sky := Sim.teleport_target(Vector3(0, 0, 0), 0.0, Vector3(0, 60, -20), reach)
	check(absf(sky.length() - reach) < 0.1 and sky.y > 15.0, "aimed into the sky it goes 18 m up and out (%.1f m up), then falls" % sky.y)
	var col: WorldLayout.Box = steps[-1]
	var from := Vector3(col.cx + col.hx + 8.0, 0, col.cz)
	var into := Sim.teleport_target(from, PI / 2.0, Vector3(col.cx, 1.0, col.cz), reach)
	check(into.x > col.cx + col.hx + Sim.RADIUS - 0.01, "aimed into the tower it stops outside it (x %.2f, wall %.2f)" % [into.x, col.cx + col.hx])

	# 3) staff: mana; wand: recharges
	var s := Sim.PlayerState.new()
	s.owned = 0b1111111
	s.weapon = Weapons.STAFF
	var fire := Weapons.spell(Weapons.STAFF, 1)
	var t := 0
	var casts := 0
	for i in 400:
		var ev := Sim.step(s, Sim.PlayerInput.new(t, Sim.Btn.ATTACK, 0.0, 0.0, Weapons.STAFF, 0, 0.0, INF, 1, Vector3(0, 0, -10)))
		t += 1
		if ev == Sim.Ev.CAST:
			casts += 1
	check(casts >= 4 and casts <= 12, "holding attack with the staff casts fireballs until the mana runs low (%d in 6.7 s)" % casts)
	s.mana = int(fire.cost) * 5 - 1
	s.atk = 0
	s.atk_cd = 0
	var ev0 := Sim.Ev.NONE
	for i in 2:
		ev0 = Sim.step(s, Sim.PlayerInput.new(t, Sim.Btn.ATTACK, 0.0, 0.0, Weapons.STAFF, 0, 0.0, INF, 1, Vector3(0, 0, -10)))
		t += 1
	check(s.atk > 0, "with just enough mana it casts")
	var w := Sim.PlayerState.new()
	w.owned = 0b1111111
	w.weapon = Weapons.WAND
	var golem_casts := []
	for i in 1300:
		var ev := Sim.step(w, Sim.PlayerInput.new(i, Sim.Btn.ATTACK, 0.0, 0.0, Weapons.WAND, 0, 0.0, INF, 0, Vector3(0, 0, -5)))
		if ev == Sim.Ev.CAST:
			golem_casts.append(i)
	check(golem_casts.size() == 3 and golem_casts[1] - golem_casts[0] == 600, "golems every 10 s with the wand held down (%s)" % str(golem_casts))
	check(w.mana == Sim.MANA_FULL, "the wand uses no mana")
	var w2 := Sim.PlayerState.new()
	w2.owned = 0b1111111
	w2.weapon = Weapons.WAND
	var tp := []
	for i in 600:
		if Sim.step(w2, Sim.PlayerInput.new(i, Sim.Btn.ATTACK, 0.0, 0.0, Weapons.WAND, 0, 0.0, INF, 1, Vector3(0, 0, -30))) == Sim.Ev.CAST:
			tp.append(i)
	check(tp.size() >= 2 and tp[1] - tp[0] == 240, "teleport every 4 s (%s)" % str(tp))
	var w3 := Sim.PlayerState.new()
	w3.owned = 0b1111111
	w3.weapon = Weapons.WAND
	var st := []
	for i in 1000:
		if Sim.step(w3, Sim.PlayerInput.new(i, Sim.Btn.ATTACK, 0.0, 0.0, Weapons.WAND, 0, 0.0, INF, 2, Vector3(0, 0, -10))) == Sim.Ev.CAST:
			st.append(i)
	check(st.size() >= 2 and st[1] - st[0] == 300, "stun every 5 s (%s)" % str(st))

	# 4) stunned: can't move for 3 s; shield lasts 5 s
	var v := Sim.PlayerState.new()
	v.stun = int(Weapons.spell(Weapons.WAND, 2).duration)
	var p0 := v.pos
	for i in 170:
		Sim.step(v, Sim.PlayerInput.new(i, Sim.Btn.FORWARD | Sim.Btn.JUMP | Sim.Btn.ATTACK, 0.0))
	check(v.pos.distance_to(p0) < 0.01 and v.atk == 0, "stunned: no moving, jumping or attacking")
	for i in 20:
		Sim.step(v, Sim.PlayerInput.new(200 + i, Sim.Btn.FORWARD, 0.0))
	check(v.pos.distance_to(p0) > 0.3, "after 3 s you can move again")
	# the shield is held: up while the button is down, its mana paid once, no mana back until it's let down
	var sh := Sim.PlayerState.new()
	sh.owned = 0b1111111
	sh.weapon = Weapons.STAFF
	sh.mana = 300
	for i in 120:
		Sim.step(sh, Sim.PlayerInput.new(i, Sim.Btn.ATTACK, 0.0, 0.0, Weapons.STAFF, 0, 0.0, INF, 2, Vector3.ZERO))
	var cost := int(Weapons.spell(Weapons.STAFF, 2).cost) * 5
	check(sh.shield > 0, "holding the button keeps the shield up (2 s)")
	check(absi(sh.mana - (300 - cost)) <= 1, "raising it cost %d mana once, and no mana came back while it was up (%d -> %d)" % [cost / 5, 300 / 5, sh.mana / 5])
	for i in 3:
		Sim.step(sh, Sim.PlayerInput.new(200 + i, 0, 0.0, 0.0, Weapons.STAFF, 0, 0.0, INF, 2, Vector3.ZERO))
	check(sh.shield == 0, "letting go drops it")
	var m0 := sh.mana
	for i in 60:
		Sim.step(sh, Sim.PlayerInput.new(300 + i, 0, 0.0, 0.0, Weapons.STAFF, 0, 0.0, INF, 2, Vector3.ZERO))
	check(sh.mana > m0, "with it down, mana comes back")

	# levels: 3 kills, 5 more, 10 more
	check(Weapons.level_for(2) == 1 and Weapons.level_for(3) == 2 and Weapons.level_for(8) == 3 and Weapons.level_for(18) == 4,
		"levels at 3, 8 and 18 kills (3, then 5 more, then 10 more)")
	check(not Weapons.unlocked(Weapons.STAFF, 3, 1) and Weapons.unlocked(Weapons.STAFF, 3, 2), "Frost Nova unlocks at staff level 2")
	check(not Weapons.unlocked(Weapons.WAND, 3, 1) and Weapons.unlocked(Weapons.WAND, 3, 2), "Earth Spikes unlocks at wand level 2")
	var lk := Sim.PlayerState.new()
	lk.owned = 0b1111111
	lk.weapon = Weapons.STAFF
	Sim.step(lk, Sim.PlayerInput.new(1, 0, 0.0, 0.0, Weapons.STAFF, 0, 0.0, INF, 3, Vector3.ZERO))
	check(lk.spell != 3, "a locked spell can't be picked")
	lk.staff_lvl = 2
	Sim.step(lk, Sim.PlayerInput.new(2, 0, 0.0, 0.0, Weapons.STAFF, 0, 0.0, INF, 3, Vector3.ZERO))
	check(lk.spell == 3, "once unlocked it can")
	var sl := Sim.PlayerState.new()
	sl.slow = 120
	for i in 60:
		Sim.step(sl, Sim.PlayerInput.new(i, Sim.Btn.FORWARD, 0.0))
	var slow_v := Vector2(sl.vel.x, sl.vel.z).length()
	check(absf(slow_v - Sim.WALK_SPEED * Sim.SLOW_FACTOR) < 0.05, "frost slows you to half speed (%.1f m/s)" % slow_v)
	print("%d failed" % bad)
	quit(bad)
