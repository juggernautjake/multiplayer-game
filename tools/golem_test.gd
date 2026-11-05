extends SceneTree
## Golems: small and quick (faster than a walking player, slower than a sprinting one), notice enemies 25 m off,
## chase and hit them while still moving, leave players alone unless both sides have PvP on, crumble at 0 health.
##   Godot --headless --path . --script tools/golem_test.gd

var bad := 0

func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


## A golem summoned by player 1 at the origin after it has risen, and a target (player 2) that runs straight away at
## `speed`, starting `gap` metres off. -> [hits landed, closest gap, ticks].
func chase(speed: float, gap: float, pvp: bool, ticks := 600) -> Array:
	var gs := Golems.new()
	var start := Vector3(60.0, 0, 60.0)   # open ground, away from the pillars near the spawn
	var g := gs.spawn(1, start, 0.0, 0)
	var me := start + Vector3(0, 0, 3)
	var them := start + Vector3(0, 0, -gap)
	var hits := 0
	var closest := INF
	for t in range(1, ticks):
		if t > Golems.RISE:
			them += Vector3(0, 0, -speed * Config.DT)
		var out := gs.tick(t, [[1, me, pvp, true], [2, them, pvp, true]])
		hits += out.size()
		closest = minf(closest, Vector2(them.x - g.pos.x, them.z - g.pos.z).length())
	return [hits, closest, g]


func _init() -> void:
	var walk := chase(Sim.WALK_SPEED, 6.0, true)
	check(walk[0] > 0, "it catches a walking player and hits them (%d hits)" % walk[0])
	var sprint := chase(Sim.SPRINT_SPEED, 6.0, true)
	check(sprint[0] == 0, "a sprinting player gets away (closest %.1f m)" % sprint[1])
	check(Golems.SPEED > Sim.WALK_SPEED and Golems.SPEED < Sim.SPRINT_SPEED, "its speed %.1f is between walking %.1f and sprinting %.1f" % [Golems.SPEED, Sim.WALK_SPEED, Sim.SPRINT_SPEED])
	var far := chase(0.0, 24.0, true, 300)
	check(far[0] > 0, "it notices someone standing 24 m off and goes for them")
	var too_far := chase(0.0, 27.0, true, 300)
	check(too_far[0] == 0 and (too_far[2] as Golems.G).target != 2, "someone 27 m off is out of its sight")
	var peace := chase(0.0, 5.0, false, 300)
	check(peace[0] == 0, "with PvP off it leaves other players alone")
	# hits while moving: the golem is still moving during its swings at a walking target
	var gs := Golems.new()
	var g := gs.spawn(1, Vector3(60, 0, 60), 0.0, 0)
	var them := Vector3(60, 0, 57)
	var moved_while_swinging := false
	for t in range(1, 500):
		if t > Golems.RISE:
			them += Vector3(0, 0, -Sim.WALK_SPEED * Config.DT)
		var before := g.pos
		gs.tick(t, [[1, Vector3(60, 0, 63), true, true], [2, them, true, true]])
		if g.state == Golems.State.ATTACK and g.pos.distance_to(before) > 0.05:
			moved_while_swinging = true
	check(moved_while_swinging, "it keeps moving while it swings")
	# health
	var gs2 := Golems.new()
	var g2 := gs2.spawn(1, Vector3(60, 0, 60), 0.0, 0)
	for t in range(1, Golems.RISE + 2):
		gs2.tick(t, [])
	var died := false
	for i in 10:
		died = gs2.hurt(g2.id, 8, 2, Vector3(1, 0, 0)) or died
	check(died and g2.state == Golems.State.DIE, "it crumbles when its health runs out")
	check(not gs2.hurt(g2.id, 8, 1, Vector3.ZERO), "its summoner can't hurt it")
	# the titan: one per summoner, beside the six small ones; its slam crushes everyone round where it lands
	var gt := Golems.new()
	for i in 6:
		gt.spawn(1, Vector3(40 + i * 2, 0, 80), 0.0, 0)
	var t1 := gt.spawn(1, Vector3(60, 0, 60), 0.0, 0, true)
	var t2 := gt.spawn(1, Vector3(62, 0, 60), 0.0, 1, true)
	var alive_small := gt.list.values().filter(func(g): return not g.titan and g.state != Golems.State.DIE).size()
	check(t1.state == Golems.State.DIE and t2.state != Golems.State.DIE and alive_small == 6, "one titan at a time (a new one replaces the old), and the six small golems stay")
	var p2 := Vector3(62, 0, 57.4)
	var p3 := Vector3(63.2, 0, 57.0)
	var hit_ids := {}
	for t in range(2, 260):
		for h in gt.tick(t, [[1, Vector3(70, 0, 70), true, true], [2, p2, true, true], [3, p3, true, true]]):
			if h[0] == t2:
				hit_ids[h[1]] = h[2]
	check(hit_ids.has(2) and hit_ids.has(3), "its slam crushes both players standing together (%s)" % str(hit_ids))
	check(int(hit_ids.get(2, 0)) == Golems.TITAN_DAMAGE, "for %d each" % Golems.TITAN_DAMAGE)
	# v0.8.0: a leap from a few metres out
	var gl := Golems.new()
	var lg := gl.spawn(1, Vector3(60, 0, 60), 0.0, 0)
	var leapt := false
	var leap_hit := false
	for t in range(1, 200):
		for h in gl.tick(t, [[1, Vector3(60, 0, 66), true, true], [2, Vector3(60, 0, 55.5), true, true]]):
			if int(h[2]) == Golems.LEAP_DAMAGE:
				leap_hit = true
		if lg.state == Golems.State.LEAP:
			leapt = true
	check(leapt and leap_hit, "it leaps at someone 4.5 m off and comes down on them")
	# several after one target spread round it instead of queueing behind each other
	var gm := Golems.new()
	var tgt := Vector3(60, 0, 50)
	var three := []
	for i in 3:
		three.append(gm.spawn(1, Vector3(58.5 + i * 1.5, 0, 66), 0.0, 0))
	for t in range(1, 400):
		gm.tick(t, [[1, Vector3(60, 0, 70), true, true], [2, tgt, true, true]])
	var angles := []
	for g3 in three:
		angles.append(rad_to_deg(Vector2(g3.pos.x - tgt.x, g3.pos.z - tgt.z).angle()))
	angles.sort()
	check(angles[2] - angles[0] > 40.0, "three golems after one target spread round it (%s degrees)" % str(angles.map(func(a): return snappedf(a, 1))))
	# with nothing to fight: a guard ring round the summoner
	var gg := Golems.new()
	var guards := []
	for i in 4:
		guards.append(gg.spawn(1, Vector3(70 + i, 0, 70), 0.0, 0))
	var owner_at := Vector3(80, 0, 80)
	for t in range(1, 500):
		gg.tick(t, [[1, owner_at, false, true]])
	var ring_ok := true
	for g4 in guards:
		var dd := Vector2(g4.pos.x - owner_at.x, g4.pos.z - owner_at.z).length()
		ring_ok = ring_ok and dd > 1.2 and dd < 3.2
	check(ring_ok, "with nothing to fight they stand guard round their summoner")
	print("%d failed" % bad)
	quit(bad)
