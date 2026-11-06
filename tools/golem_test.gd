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
## v0.12.0: player 2 is a challenger (Golems.Who.NPC) unless `who` says otherwise; `owner_at` is how far along
## toward the target the summoner stands (so far targets are inside the leash).
func chase(speed: float, gap: float, pvp: bool, ticks := 600, who := Golems.Who.NPC, owner_at := -3.0) -> Array:
	var gs := Golems.new()
	var start := Vector3(60.0, 0, 60.0)   # open ground, away from the pillars near the spawn
	var g := gs.spawn(1, start, 0.0, 0)
	var me := start + Vector3(0, 0, -owner_at)
	var them := start + Vector3(0, 0, -gap)
	var hits := 0
	var closest := INF
	for t in range(1, ticks):
		if t > Golems.RISE:
			them += Vector3(0, 0, -speed * Config.DT)
			me += Vector3(0, 0, -speed * Config.DT)   # the summoner keeps up (the leash is round them)
		var out := gs.tick(t, [[1, me, pvp, true, Golems.Who.PLAYER], [2, them, pvp, true, who]])
		hits += out.size()
		closest = minf(closest, Vector2(them.x - g.pos.x, them.z - g.pos.z).length())
	return [hits, closest, g]


func _init() -> void:
	var walk := chase(Sim.WALK_SPEED, 6.0, true)
	check(walk[0] > 0, "it catches a walking player and hits them (%d hits)" % walk[0])
	var sprint := chase(Sim.SPRINT_SPEED, 6.0, true)
	check(sprint[0] == 0, "a sprinting player gets away (closest %.1f m)" % sprint[1])
	check(Golems.SPEED > Sim.WALK_SPEED and Golems.SPEED < Sim.SPRINT_SPEED, "its speed %.1f is between walking %.1f and sprinting %.1f" % [Golems.SPEED, Sim.WALK_SPEED, Sim.SPRINT_SPEED])
	var far := chase(0.0, 24.0, true, 300, Golems.Who.NPC, 12.0)
	check(far[0] > 0, "it notices someone standing 24 m off and goes for them")
	var too_far := chase(0.0, 27.0, true, 300)
	check(too_far[0] == 0 and (too_far[2] as Golems.G).target != 2, "someone 27 m off is out of its sight")
	var peace := chase(0.0, 5.0, false, 300, Golems.Who.PLAYER)
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
		gs.tick(t, [[1, Vector3(60, 0, 63), true, true], [2, them, true, true, Golems.Who.NPC]])
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
		for h in gt.tick(t, [[1, Vector3(70, 0, 70), true, true], [2, p2, true, true, Golems.Who.NPC], [3, p3, true, true, Golems.Who.NPC]]):
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
		for h in gl.tick(t, [[1, Vector3(60, 0, 66), true, true], [2, Vector3(60, 0, 55.5), true, true, Golems.Who.NPC]]):
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
		gm.tick(t, [[1, Vector3(60, 0, 62), true, true], [2, tgt, true, true, Golems.Who.NPC]])
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
	_owner_rules()
	print("%d failed" % bad)
	quit(bad)


## v0.12.0: golems fight for their summoner.
func _pick_after(gs: Golems, people: Array, ticks: int, from := 1) -> int:
	for t in range(from, from + ticks):
		gs.tick(t, people)
	return (gs.list.values()[0] as Golems.G).target


func _owner_rules() -> void:
	var c := Vector3(60, 0, 60)
	var me := [1, c + Vector3(0, 0, 2), true, true, Golems.Who.PLAYER]
	# PvP on, but player 2 never hurt us: left alone
	var gs := Golems.new()
	gs.spawn(1, c, 0.0, 0)
	var p2 := [2, c + Vector3(0, 0, -4), true, true, Golems.Who.PLAYER]
	check(_pick_after(gs, [me, p2], 120) != 2, "PvP on: a player who hasn't hurt the summoner is left alone")
	# they hit the summoner: a grudge
	gs.note_harm(1, 2, 120)
	var hits := 0
	for t in range(121, 300):
		hits += gs.tick(t, [me, p2]).size()
	check((gs.list.values()[0] as Golems.G).target == 2 and hits > 0, "PvP on: after they hurt the summoner, the golem goes for them (%d hits)" % hits)
	# the grudge runs out
	var after := _pick_after(gs, [me, p2], 120, 121 + Golems.GRUDGE + 5)
	check(after != 2, "the grudge expires after %d s" % (Golems.GRUDGE / 60))
	# hurting the summoner's golem counts as hurting them
	var gh := Golems.new()
	gh.spawn(1, c, 0.0, 0)
	_pick_after(gh, [me, p2], 60)
	gh.note_harm(1, 2, 60)   # (what Net does when 2 hits one of 1's golems)
	check(_pick_after(gh, [me, p2], 30, 61) == 2, "hurting the summoner's golem starts a grudge too")
	# PvP off: never, even after a hit
	var go := Golems.new()
	go.spawn(1, c, 0.0, 0)
	go.note_harm(1, 2, 1)
	var p2off := [2, c + Vector3(0, 0, -4), false, true, Golems.Who.PLAYER]
	var hits_off := 0
	for t in range(1, 300):
		hits_off += go.tick(t, [me, p2off]).size()
	check(hits_off == 0, "PvP off: players are never attacked, even after they hit the summoner")
	# other players' golems: only with a grudge on their summoner
	var gg := Golems.new()
	gg.spawn(1, c, 0.0, 0)
	var theirs := gg.spawn(2, c + Vector3(0, 0, -4), 0.0, 0)
	var p2far := [2, c + Vector3(30, 0, 0), true, true, Golems.Who.PLAYER]
	check(_pick_after(gg, [me, p2far], 120) != -1000 - theirs.id, "PvP on: another player's golem is left alone without a grudge")
	gg.note_harm(1, 2, 120)
	var tg := _pick_after(gg, [me, p2far], 30, 121)
	check(tg == -1000 - theirs.id or tg == 2, "with a grudge, their golem is fair game too")
	# a challenger's golem: always
	var gn := Golems.new()
	gn.spawn(1, c, 0.0, 0)
	var npcg := gn.spawn(3, c + Vector3(0, 0, -4), 0.0, 0)
	var npc_far := [3, c + Vector3(0, 0, -14), true, true, Golems.Who.NPC]
	check(_pick_after(gn, [me, npc_far], 120) == -1000 - npcg.id, "a challenger's golem is always an enemy")
	# and the challenger's golems fight players, PvP or not
	var nt: int = (gn.list[npcg.id] as Golems.G).target
	check(nt == 1 or nt == -1000 - (gn.list.values()[0] as Golems.G).id, "a challenger's golem goes for the player or the player's golem (%d)" % nt)
	# the boss: always
	var gb := Golems.new()
	gb.spawn(1, c, 0.0, 0)
	check(_pick_after(gb, [me, [Boss.ID, c + Vector3(0, 0, -8), true, true, Golems.Who.BOSS]], 120) == Boss.ID, "PvP off or on, golems go for Thunderhorn")
	# priority: whoever is attacking the summoner first, over a nearer enemy
	var gp := Golems.new()
	gp.spawn(1, c, 0.0, 0)
	var near := [5, c + Vector3(0, 0, -3), true, true, Golems.Who.NPC]
	var attacker := [6, c + Vector3(6, 0, -6), true, true, Golems.Who.NPC]
	check(_pick_after(gp, [me, near, attacker], 60) == 5, "the nearest enemy, with nobody attacking the summoner")
	gp.note_harm(1, 6, 60)
	check(_pick_after(gp, [me, near, attacker], 20, 61) == 6, "whoever is attacking the summoner comes first")
	# leash: an enemy near the golem but far from the summoner is ignored
	var gl := Golems.new()
	gl.spawn(1, c, 0.0, 0)
	var far_me := [1, c + Vector3(0, 0, 14), true, true, Golems.Who.PLAYER]
	var stray := [7, c + Vector3(0, 0, -6), true, true, Golems.Who.NPC]
	check(_pick_after(gl, [far_me, stray], 60) != 7, "an enemy more than %d m from the summoner is ignored (the leash)" % int(Golems.LEASH))
