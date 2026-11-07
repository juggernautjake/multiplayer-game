extends SceneTree
## v0.12.18: cancelling a drawn bow (Sim.Btn.CANCEL: lowered, no shot), Life Drain's aim help (Net.drain_assist: a
## near miss latches on; not far off, not behind you, not through a wall), the aim preview's sums (Net.aim_ground pulls
## a spot in to the reach; the Fireball's path comes down on the ground), and the challengers' dashes by weapon and
## their own reaction speeds.
##   Godot --headless --path . --script tools/aim_test.gd

var bad := 0


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


func _inp(seq: int, b: int) -> Sim.PlayerInput:
	return Sim.PlayerInput.new(seq, b, 0.0, 0.0, Weapons.BOW, 0, 0.0, 0.0, 0, Vector3(0, 1, -20))


func _initialize() -> void:
	# ---- cancel a draw
	var s := Sim.PlayerState.new()
	s.pos = Vector3(60, 0, 60)
	s.owned = 0xFF
	s.weapon = Weapons.BOW
	s.arrows = 5
	var seq := 0
	for i in 30:
		seq += 1
		Sim.step(s, _inp(seq, Sim.Btn.ATTACK))
	check(s.charge > 0, "holding attack draws the bow (%d)" % s.charge)
	seq += 1
	var ev := Sim.step(s, _inp(seq, Sim.Btn.CANCEL))
	check(s.charge == 0 and ev != Sim.Ev.SHOT and s.arrows == 5, "CANCEL lowers it: no shot, no arrow spent")
	seq += 1
	ev = Sim.step(s, _inp(seq, 0))
	check(ev != Sim.Ev.SHOT and s.arrows == 5, "and letting go after shoots nothing")
	for i in 20:
		seq += 1
		Sim.step(s, _inp(seq, Sim.Btn.ATTACK))
	seq += 1
	ev = Sim.step(s, _inp(seq, 0))
	check(ev == Sim.Ev.SHOT and s.arrows == 4, "a normal draw and let go still shoots")

	# ---- Life Drain's aim help
	var sp := Weapons.spell_named(Weapons.WAND, "Life Drain")
	check(float(sp.range) == 22.0 and float(sp.assist) > 1.0, "Life Drain reaches 22 m with aim help (%.1f m)" % float(sp.assist))
	var from := Vector3(60, 1.45, 60)
	var aim := Vector3(60, 1.1, 45)   # straight ahead (-z), 15 m
	var near := [[7, Vector3(61.3, 0, 47)]]   # 1.3 m off the line
	var got = Net.drain_assist(from, aim, 22.0, float(sp.assist), near)
	check(got != null and int(got[0]) == 7, "a near miss (1.3 m off) latches on")
	check(Net.drain_assist(from, aim, 22.0, float(sp.assist), [[8, Vector3(64, 0, 47)]]) == null, "4 m off: no")
	check(Net.drain_assist(from, aim, 22.0, float(sp.assist), [[9, Vector3(60.5, 0, 70)]]) == null, "behind you: no")
	check(Net.drain_assist(from, aim, 22.0, float(sp.assist), [[10, Vector3(60.5, 0, 30)]]) == null, "past its reach: no")
	var two = Net.drain_assist(from, aim, 22.0, float(sp.assist), [[11, Vector3(61.4, 0, 47)], [12, Vector3(60.4, 0, 50)]])
	check(two != null and int(two[0]) == 12, "the one nearest the aim line wins")
	# through a wall: find a box and stand behind it
	var b: WorldLayout.Box = WorldLayout.boxes()[0]
	var f2 := Vector3(b.cx, 1.45, b.cz + b.hz + 5.0)
	var behind := Vector3(b.cx + 0.8, 0, b.cz - b.hz - 3.0)
	check(Net.drain_assist(f2, Vector3(b.cx, 1.1, b.cz - b.hz - 3.0), 22.0, float(sp.assist), [[13, behind]]) == null or b.h < 1.2,
		"not through a wall")

	# ---- the preview's sums
	var at := Net.aim_ground(Vector3(0, 0, 0), Vector3(0, 0, -100), 40.0, 0.0)
	check(absf(Vector2(at.x, at.z).length() - 40.0) < 0.01, "a spot past the reach is pulled in to it (as the server does)")
	var path := AimPreview.fireball_path(Vector3(60, 1.45, 60), Vector3(0, -0.3, -1).normalized() * 26.0, 3.0)
	var end: Vector3 = path[-1]
	check(path.size() > 2 and end.y < 0.2 and end.z < 60.0, "the Fireball's path comes down ahead on the ground (%.1f m)" % Vector3(60, 0, 60).distance_to(Vector3(end.x, 0, end.z)))
	var M = load("res://scripts/main.gd")
	check(M.preview_spell(Weapons.spell_named(Weapons.STAFF, "Fireball")) and not M.preview_spell(Weapons.spell_named(Weapons.STAFF, "Shield"))
		and not M.preview_spell(Weapons.spell_named(Weapons.STAFF, "Heal Aura")), "hold-to-aim for thrown spells; the Shield and Heal Aura stay held")

	# ---- challengers' dashes and reactions
	var lens := {}
	for w in [Weapons.SWORD, Weapons.CLUB, Weapons.STAFF, Weapons.BOW]:
		var ai := NpcAI.new(100, 1, w, 1, 77)
		var st := Sim.PlayerState.new()
		st.pos = Vector3(60, 0, 60)
		st.owned = 0xFF
		st.weapon = w
		var q := 0
		var start := st.pos
		q += 1
		Sim.step(st, Sim.PlayerInput.new(q, Sim.Btn.DASH, 0.0, 0.0, w, 0, 0.0, 0.0, 0, Vector3.ZERO))
		while st.dash_ticks > 0:
			ai._dash_style(st)
			q += 1
			Sim.step(st, Sim.PlayerInput.new(q, 0, 0.0, 0.0, w, 0, 0.0, 0.0, 0, Vector3.ZERO))
		lens[w] = start.distance_to(st.pos)
	print("      dash lengths: sword %.2f  club %.2f  staff %.2f  bow %.2f" % [lens[Weapons.SWORD], lens[Weapons.CLUB], lens[Weapons.STAFF], lens[Weapons.BOW]])
	check(lens[Weapons.CLUB] < lens[Weapons.SWORD] * 0.75 and lens[Weapons.STAFF] < lens[Weapons.SWORD] * 0.75
		and lens[Weapons.BOW] < lens[Weapons.SWORD] and lens[Weapons.BOW] > lens[Weapons.CLUB], "a club's or staff's dash is far shorter, a bow's a little")
	var qs := []
	for k in 40:
		qs.append(NpcAI.new(100, 1, Weapons.SWORD, 1, 1000 + k).quick)
	check(qs.min() >= 0.8 and qs.max() <= 1.45 and qs.max() - qs.min() > 0.4, "each fighter has its own reaction speed (x%.2f to x%.2f)" % [qs.min(), qs.max()])
	print("%d failed" % bad)
	quit(1 if bad > 0 else 0)
