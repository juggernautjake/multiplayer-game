extends SceneTree
## Fruit physics: fallen fruit comes to rest (no sliding forever), a person walking into it kicks it and it rolls to a
## stop, a melee blow sends it flying, it never ends up inside a pillar, trunk or dummy, and its path has no jumps.
##   Godot --headless --path . --script tools/fruit_test.gd

var bad := 0

func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


func smooth(segs: Array, from: int, to: int) -> float:
	var worst := 0.0
	var prev := Ecology.path_pos(segs, from)
	for t in range(from + 1, to + 1):
		var p := Ecology.path_pos(segs, t)
		worst = maxf(worst, p.distance_to(prev))
		prev = p
	return worst


func inside_something(p: Vector3) -> bool:
	for b: WorldLayout.Box in WorldLayout.boxes():
		if absf(p.x - b.cx) < b.hx - 0.01 and absf(p.z - b.cz) < b.hz - 0.01:
			return true
	for d: Vector3 in WorldLayout.DUMMIES:
		if Vector2(p.x - d.x, p.z - d.z).length() < Sim.DUMMY_RADIUS:
			return true
	return false


func _init() -> void:
	var eco := Ecology.new()
	var now := 100
	# 1) knock every fruit off the apple tree: each lands, rolls and stops; after it stops it stays put
	eco.hit_tree(0, 10, now, Vector3(1, 0, 0))
	eco.hit_tree(0, 10, now, Vector3(1, 0, 0))
	eco.hit_tree(0, 10, now, Vector3(1, 0, 0))
	var fallen := []
	for f in eco.fruits.values():
		if f.state == "fall":
			fallen.append(f)
	check(fallen.size() > 0, "hitting the tree three times drops fruit (%d)" % fallen.size())
	for f in fallen:
		var last: Array = f.fall[-1]
		check(last.size() > 3 and (last[2] as Vector3).length() < 1e-6, "fruit %d: its path ends at rest" % f.id)
		var rest := Ecology.path_pos(f.fall, f.land)
		var later := Ecology.path_pos(f.fall, f.land + 600)
		check(rest.distance_to(later) < 1e-4, "fruit %d: 10 s after landing it hasn't moved (%.4f m)" % [f.id, rest.distance_to(later)])
		check(smooth(f.fall, now, f.land + 5) < 0.6, "fruit %d: no jumps in its path (biggest step %.3f m)" % [f.id, smooth(f.fall, now, f.land + 5)])
		check(not inside_something(rest), "fruit %d: rests outside every pillar, trunk and dummy" % f.id)
	for t in range(now, now + 900):
		eco.tick(t, [])
	now += 900
	var f: Dictionary = fallen[0]
	check(f.state == "ground", "the fruit is on the ground after it stops")

	# 2) walk into it at walking speed: it gets kicked the way you walk and rolls to a stop
	var at: Vector3 = f.pos
	var walker := [1, at + Vector3(-0.45, -at.y, 0), 4.0, Vector2(4.0, 0.0)]
	eco.tick(now, [walker])
	check(f.state == "fall", "walking into it kicks it")
	var stop := Ecology.path_pos(f.fall, f.land)
	check(stop.x > at.x + 0.5, "it rolls the way you walked (%.2f m)" % (stop.x - at.x))
	check(stop.distance_to(Ecology.path_pos(f.fall, f.land + 300)) < 1e-4, "and comes to rest")
	check(smooth(f.fall, now, f.land + 5) < 0.2, "rolling has no jumps (biggest step %.3f m)" % smooth(f.fall, now, f.land + 5))
	for t in range(now, f.land + 2):
		eco.tick(t, [])
	now = f.land + 2

	# 3) a sword blow sends it flying the way the blow goes, then it rolls and stops
	var q: Vector3 = f.pos
	eco.hit_fruit(q + Vector3(0, 0, 1.0), Vector2(0, -1), 2.5, 100.0, 1.5, now)
	check(f.state == "fall", "a melee hit launches it")
	var top := 0.0
	for t in range(now, f.land):
		top = maxf(top, Ecology.path_pos(f.fall, t).y)
	var end := Ecology.path_pos(f.fall, f.land)
	check(top > 0.2, "it pops up off the ground (%.2f m)" % top)
	check(end.z < q.z - 1.0, "and lands away from the swing (%.2f m)" % (q.z - end.z))
	check(not inside_something(end), "and rests outside everything")

	# 4) rolled straight at a pillar: it bounces back off it and stops outside it
	var b: WorldLayout.Box = WorldLayout.boxes()[0]
	var start := Vector3(b.cx + b.hx + 1.5, Ecology.FRUIT_R, b.cz)
	var g := { "id": 999, "tree": 0, "state": "ground", "pos": start, "worm": 0, "fall": [], "kicked": -999 }
	eco.fruits[999] = g
	eco._launch(g, now, start, Vector3(-6.0, 0.0, 0.0))
	var rest2 := Ecology.path_pos(g.fall, g.land)
	check(not inside_something(rest2) and rest2.x > b.cx + b.hx, "rolled at a pillar, it bounces off and stops outside it (x %.2f, face at %.2f)" % [rest2.x, b.cx + b.hx])

	_apples()
	print("%d failed" % bad)
	quit(bad)


## v0.12.0: every tree bears apples; any hit knocks one loose; walking over one while hurt eats it and heals; trees
## regrow up to their cap; real apple trees round the arena; Thunderhorn's felling and trampling.
func _apples() -> void:
	var eco := Ecology.new()
	var now := 100
	var bearing := 0
	for tr in eco.trees:
		for f in eco.fruits.values():
			if f.tree == tr.i:
				bearing += 1
				break
	check(bearing == eco.trees.size(), "every tree (oaks too) has apples (%d of %d)" % [bearing, eco.trees.size()])
	var c := Vector2(WorldLayout.ALTAR_C.x, WorldLayout.ALTAR_C.y + 10.0)
	var arena := 0
	for t in WorldLayout.TREES:
		if Vector2(t[1].x, t[1].z).distance_to(c) < WorldLayout.ARENA_R:
			arena += 1
	check(arena >= 4, "real apple trees round the boss arena (%d)" % arena)
	var oak := 2
	var before := eco.fruits.size()
	eco.hit_tree(oak, 5, now, Vector3(1, 0, 0))
	var loose := eco.fruits.values().filter(func(f): return f.tree == oak and f.state != "hang")
	check(loose.size() == 1, "one hit on an oak knocks an apple loose (%d)" % loose.size())
	var f: Dictionary = loose[0]
	var rest := Ecology.path_pos(f.fall, f.land)
	eco.tick(f.land + 1, [])
	check(eco.eat_under(rest + Vector3(0, -Ecology.FRUIT_R, 0), f.land + 2) == Ecology.HEAL and not eco.fruits.has(f.id),
		"walking over it eats it and heals %d" % Ecology.HEAL)
	# regrowth: never more than the four slots per tree
	for k in 6:
		now += Ecology.GROW_EVERY
		eco.tick(now, [])
	var most := 0
	for tr in eco.trees:
		most = maxi(most, eco._slots_used(tr).size())
	check(most <= Ecology.SLOTS.size() and most >= 3, "trees regrow apples up to the cap (%d)" % most)
	# Thunderhorn fells a tree: its apples are gone, hits do nothing, it grows none until restored
	eco.fell_tree(oak, now, Vector3(1, 0, 0))
	eco.hit_tree(oak, 10, now, Vector3(1, 0, 0))
	now += Ecology.GROW_EVERY * 2
	eco.tick(now, [])
	var on_oak := eco.fruits.values().filter(func(q): return q.tree == oak and q.state == "hang").size()
	check(on_oak == 0, "a felled tree bears nothing")
	eco.restore_trees(now)
	on_oak = eco.fruits.values().filter(func(q): return q.tree == oak and q.state == "hang").size()
	check(on_oak > 0 and not eco.trees[oak].felled, "restored after the fight, with apples again")
	# trampling: an apple on the ground is splatted
	eco.hit_tree(oak, 5, now, Vector3(1, 0, 0))
	var g: Array = eco.fruits.values().filter(func(q): return q.tree == oak and q.state != "hang")
	if not g.is_empty():
		var gid: int = g[0].id
		eco.splat(gid, now + 200)
		check(not eco.fruits.has(gid), "a trampled apple is gone (a splat)")
