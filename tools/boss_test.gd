extends SceneTree
## v0.11.0: Thunderhorn's Static, homing orbs, Storm Leap rules, jumpable rings, the rush (dodge, launch, knock-down,
## get up) and fair targeting. Server side, run offline (prints harmless "not inside tree" RPC errors).
##   Godot --headless --path . --script tools/boss_test.gd

var bad := 0


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


func idle(s: Sim.PlayerState, buttons := 0, yaw := 0.0) -> void:
	Sim.step(s, Sim.PlayerInput.new(0, buttons, yaw, 0.0, s.weapon, 0, yaw, yaw))


func people_of(list: Array) -> Array:
	var out := []
	for e in list:
		var s: Sim.PlayerState = e[1]
		out.append([e[0], s.pos, s.dead == 0, s.shield > 0, s.hp, s.dash_ticks, false, s.stun > 0 or s.down > 0])
	return out


func _initialize() -> void:
	var net := Net.new()
	root.add_child(net)
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	net._server_add_player(1, "P1")
	var a: Net.ServerPlayer = net.players[1]

	# ---- Static: a stack per hit, holds, drains, stuns 7 s at 6 (5 enraged)
	net.summon_boss()
	net.boss.state = Boss.S.IDLE
	a.state = Sim.spawn_state(1)
	net._boss_zap(1, 6, Vector3.FORWARD, false)
	check(a.state.zap == Sim.ZAP_STACK and a.state.hp == Sim.MAX_HP - 6, "an orb hit: 6 damage and one stack of Static")
	net._boss_zap(1, 6, Vector3.FORWARD, false)
	check(a.state.zap == 2 * Sim.ZAP_STACK, "a second hit: two stacks (the bar fills per hit)")
	for i in Sim.ZAP_HOLD - 1:
		idle(a.state)
	check(a.state.zap == 2 * Sim.ZAP_STACK, "it holds for 2.5 s after a hit")
	for i in Sim.ZAP_STACK + 1:
		idle(a.state)
	check(a.state.zap < 2 * Sim.ZAP_STACK and a.state.zap > 0, "then drains slowly (%d left after 3.3 s more: one stack gone)" % a.state.zap)
	for i in 400:
		idle(a.state)
	check(a.state.zap == 0, "and empties when not hit")
	a.state.shield = 50
	net._boss_zap(1, 6, Vector3.FORWARD, true)
	check(a.state.zap == 0, "a shield blocks it: no stack")
	a.state.shield = 0
	a.state.hp = Sim.MAX_HP
	for i in 5:
		net._boss_zap(1, 1, Vector3.FORWARD, false)
	check(a.state.stun == 0 and a.state.zap == 5 * Sim.ZAP_STACK, "five stacks: not yet (he's calm: 6 needed)")
	net._boss_zap(1, 1, Vector3.FORWARD, false)
	check(a.state.stun == Sim.STATIC_STUN and a.state.zap == Sim.ZAP_STUN, "the sixth: stunned for 7 s (%d ticks)" % a.state.stun)
	var p0 := a.state.pos
	for i in 30:   # the last hit's little shove settles
		idle(a.state)
	p0 = a.state.pos
	for i in Sim.STATIC_STUN - 31:
		idle(a.state, Sim.Btn.FORWARD | Sim.Btn.ATTACK | Sim.Btn.JUMP | Sim.Btn.DASH)
	check(a.state.pos.distance_to(p0) < 0.01 and a.state.stun == 1 and a.state.atk == 0, "stunned: no moving, jumping, dashing or attacking for 7 s")
	net._boss_zap(1, 1, Vector3.FORWARD, false)
	check(a.state.zap == Sim.ZAP_STUN, "no more stacks while static-stunned")
	idle(a.state)
	check(a.state.stun == 0 and a.state.zap == 0, "then free, the meter empty")
	for i in 10:
		idle(a.state, Sim.Btn.FORWARD)
	check(a.state.pos.distance_to(p0) > 0.3, "and moving again")
	net.boss.enraged = true
	for i in 5:
		net._boss_zap(1, 0, Vector3.FORWARD, false)
	check(a.state.stun == Sim.STATIC_STUN, "enraged: 5 stacks are enough")
	a.state = Sim.spawn_state(1)
	# over the network: the snapshot carries static, a 7 s stun and the knock-down
	var w := Sim.spawn_state(1)
	w.zap = 777
	w.zap_cd = 99
	w.stun = 420
	w.down = 120
	var back: Sim.PlayerState = Codec.decode_snapshot(Codec.encode_snapshot(5, 1, [[1, w]])).ents[1]
	check(back.zap == 777 and back.zap_cd == 99 and back.stun == 420 and back.down == 120, "snapshots carry Static, a 7 s stun and the knock-down")
	net.boss = null

	# ---- homing orbs: how many, split evenly
	check(Boss.homing_count(1) == 10 and Boss.homing_count(2) == 15 and Boss.homing_count(3) == 20 and Boss.homing_count(6) == 24,
		"orbs: 10 alone, 15 for two, 20 for three, 24 at most")
	for n in [1, 2, 3]:
		var ppl := []
		for i in n:
			ppl.append([i + 1, Vector3(-14 + 14 * i, 0, 40), true, false, 100])
		var b2 := Boss.new(Vector3(0, 0, 52), n, 7)
		b2.state = Boss.S.LEAP_LAND
		b2.t = 39
		for k in 260:
			b2.tick(k, ppl, [])
		var launched: Dictionary = b2.orb_sent
		var total := 0
		for id in launched:
			total += int(launched[id])
		var lo := 99
		var hi := 0
		for id in launched:
			lo = mini(lo, int(launched[id]))
			hi = maxi(hi, int(launched[id]))
		check(total == Boss.homing_count(n) and launched.size() == n and hi - lo <= 1,
			"%d player(s): %d orbs, split %s" % [n, total, str(launched.values())])
	# hard but dodgeable: standing still eats most of them, sprinting in a circle and dashing gets past most
	var still := _orb_run(false)
	var moving := _orb_run(true)
	check(still >= 6 and moving < still, "orbs: standing still %d of 10 hit, sprinting round and dashing %d" % [still, moving])

	# ---- the leap: 2-5 a fight, spaced out
	for sd in [11, 22, 33, 44, 55, 66]:
		var b := Boss.new(Vector3(0, 0, 56), 1 + sd % 2, sd)
		var ppl := [[1, Vector3(6, 0, 44), true, false, 100], [2, Vector3(-8, 0, 60), true, false, 90]]
		if b.players_n == 1:
			ppl = [ppl[0]]
		var starts := []
		var every: int = 9 + int(sd) % 4 * 3   # different paces of damage (a 2-5 minute fight)
		for k in 30000:
			if b.state == Boss.S.DEATH:
				break
			if k % every == 0 and b.state != Boss.S.ENTER:
				b.hurt(14, 1, "")
			var st0 := b.state
			b.tick(k, ppl, [])
			if b.state == Boss.S.LEAP_WIND and st0 != Boss.S.LEAP_WIND:
				starts.append(k)
			b.hits.clear(); b.fx.clear(); b.zaps.clear(); b.launches.clear(); b.strikes.clear(); b.slows.clear()
			for p in ppl:   # they keep their footing (not on the boss)
				p[1] = Vector3((p[1] as Vector3).x, 0, (p[1] as Vector3).z)
		var gap := 999999
		for i in range(1, starts.size()):
			gap = mini(gap, starts[i] - starts[i - 1])
		check(starts.size() >= 2 and starts.size() <= 5 and gap >= Boss.LEAP_GAP,
			"seed %d (%d player%s): %d leaps, at least %.0f s apart" % [sd, b.players_n, "s" if b.players_n > 1 else "", starts.size(), (gap if starts.size() > 1 else 0) / 60.0])
	# losing badly: no bonus leaps
	var bl := Boss.new(Vector3(0, 0, 56), 1, 5)
	bl.state = Boss.S.IDLE
	bl.hp = int(bl.max_hp * 0.9)
	var bonus := 0
	for k in 2000:
		bl.tick(k, [[1, Vector3(6, 0, 44), true, false, 30]], [])
		bl.hits.clear(); bl.fx.clear()
	check(bl.leap_bonus == 0, "players struggling (30 health): no bonus leaps")

	# ---- the landing ring: jump it, or be hit on the ground
	for jump in [false, true]:
		var b := Boss.new(Vector3(0, 0, 56), 1, 3)
		b.state = Boss.S.HOWL
		b.orb_plan = 0
		var s := Sim.spawn_state(1)
		s.pos = Vector3(0, 0, 56 - 9.0)
		b._slam(10.0, 18)
		var hit := false
		for k in 150:
			var r := float(b.rings[0][0]) if not b.rings.is_empty() else 99.0
			var press: bool = jump and r > 9.0 - 10.0 * 0.22 and r < 9.0 - 10.0 * 0.12 and s.grounded
			idle(s, Sim.Btn.JUMP if press else 0)
			b.tick(k, people_of([[1, s]]), [])
			for h in b.hits:
				if h[0] == 1:
					hit = true
			b.hits.clear()
		check(hit != jump, "a landing ring: %s" % ("jumped over it: no hit" if jump else "standing on the ground: hit"))
	# v0.12.0: the landing ring and the slam waves cross the whole map: a player 150 m away is hit standing, not jumping
	for jump in [false, true]:
		var b := Boss.new(Vector3(0, 0, 56), 1, 3)
		b.state = Boss.S.HOWL
		b.orb_plan = 0
		var s := Sim.spawn_state(1)
		s.pos = Vector3(-120, 0, -40)
		var far := Vector2(s.pos.x, s.pos.z).distance_to(Vector2(0, 56))
		b.rings.append([Boss.RADIUS, {}, Vector3(0, 0, 56), Boss.WAVE_V, 18, 1, Boss.wave_max(Vector3(0, 0, 56))])
		var hit := false
		for k in int(far / Boss.WAVE_V * 60.0) + 120:
			var r := float(b.rings[0][0]) if not b.rings.is_empty() else 9999.0
			var press: bool = jump and r > far - Boss.WAVE_V * 0.22 and r < far - Boss.WAVE_V * 0.12 and s.grounded
			idle(s, Sim.Btn.JUMP if press else 0)
			b.state = Boss.S.HOWL
			b.t = 1
			b.tick(k, people_of([[1, s]]), [])
			for h in b.hits:
				if h[0] == 1:
					hit = true
			b.hits.clear(); b.fx.clear(); b.zaps.clear()
		check(hit != jump, "a map-wide ring %.0f m away: %s" % [far, "jumped over it: no hit" if jump else "standing on the ground: hit"])
	check(Boss.wave_max(Vector3(0, 0, 56)) > 250.0, "the waves run past the farthest corner of the map (%.0f m)" % Boss.wave_max(Vector3(0, 0, 56)))
	check(Boss.WAVE_GAP * Config.DT > 2.0 * Sim.JUMP_SPEED / Sim.GRAVITY + 0.3, "time between slam waves to land and jump again (%.2f s vs %.2f s in the air)" % [Boss.WAVE_GAP * Config.DT, 2.0 * Sim.JUMP_SPEED / Sim.GRAVITY])

	# ---- the rush: dash sideways in time and he misses; otherwise launched, knocked down, then up again
	for dodge in [true, false]:
		net.summon_boss()
		var b: Boss = net.boss
		b.state = Boss.S.SLAMS
		b.t = 30 + 2 * Boss.WAVE_GAP + 39
		b.yaw = 0.0   # facing -Z
		a.state = Sim.spawn_state(1)
		a.state.pos = b.pos + Vector3(0, 0, -16)
		var hp0 := a.state.hp
		var dashed := false
		var launched_at := -1
		var land := Vector3.ZERO
		var downed := 0
		for k in 600:
			var btn := 0
			var face := b.yaw
			var gap_now := Vector2(a.state.pos.x - b.pos.x, a.state.pos.z - b.pos.z).length()
			if dodge and b.state == Boss.S.RUSH and gap_now < 9.0 and not dashed:
				btn = Sim.Btn.DASH | Sim.Btn.RIGHT
				dashed = true
			Sim.step(a.state, Sim.PlayerInput.new(k, btn, face, 0.0, a.state.weapon, 0, face, face))
			net.server_tick += 1
			net._server_boss()
			if a.state.down > 0 and launched_at < 0:
				launched_at = k
				land = a.state.pos
			if a.state.down > 0:
				downed += 1
			if net.boss == null or (b.state == Boss.S.IDLE and k > 300):
				break
		if dodge:
			check(a.state.hp == hp0 and launched_at < 0, "a side-dash as he comes: missed")
		else:
			var flew := Vector2(a.state.pos.x - land.x, a.state.pos.z - land.z).length()
			check(launched_at >= 0 and a.state.hp <= hp0 - 30, "standing still: hit for %d and launched" % (hp0 - a.state.hp))
			check(flew > 10.0, "thrown %.1f m across the arena" % flew)
			check(downed >= Sim.DOWN_TICKS - 2, "knocked down %.1f s (can't act)" % (downed / 60.0))
			var q := a.state.pos
			for i in 20:
				idle(a.state, Sim.Btn.FORWARD)
			check(a.state.down == 0 and a.state.pos.distance_to(q) > 0.5, "then up and moving again")
		net.boss = null

	# ---- targeting: fair with two, punishes the one at range, leaves the stunned alone
	var bt := Boss.new(Vector3(0, 0, 56), 2, 9)
	bt.state = Boss.S.IDLE
	var share := {1: 0, 2: 0}
	var ppl2 := [[1, Vector3(5, 0, 50), true, false, 100], [2, Vector3(-6, 0, 62), true, false, 100]]
	for k in 7200:
		if k % 20 == 0:
			bt.hurt(1, 1, "")   # player 1 does all the damage
		bt.tick(k, ppl2, [])
		bt.hits.clear(); bt.fx.clear(); bt.zaps.clear(); bt.launches.clear()
		if bt.target in share:
			share[bt.target] += 1
		bt.hp = maxi(bt.hp, int(bt.max_hp * 0.9))   # no leaps or phases here
		bt.leaps = Boss.LEAP_MAX
		for p in ppl2:
			p[1] = Vector3((p[1] as Vector3).x, 0, (p[1] as Vector3).z)
	var k1 := float(share[1]) / float(share[1] + share[2])
	check(k1 > 0.4 and k1 < 0.8, "two players: the one hurting him gets more attention, but not all of it (%.0f%% / %.0f%%)" % [k1 * 100, 100 - k1 * 100])
	var bs := Boss.new(Vector3(0, 0, 56), 2, 4)
	var stun_t := 0
	for k in 60:
		bs._retarget([[1, Vector3(4, 0, 52), true, false, 20, 0, false, true], [2, Vector3(-9, 0, 62), true, false, 100]], [])
		if bs.target == 1:
			stun_t += 1
	check(stun_t < 15, "a stunned, low-health player is mostly left alone (%d of 60 picks)" % stun_t)

	_throw_tests()
	_maximin_tests()
	_tree_tests()
	_home_tests()
	print("%d failed" % bad)
	quit(bad)


## v0.12.0: a charge throws you hard: far, bouncing, skidding, off a trunk, never out of the world; then you get up.
func _throw(from: Vector3, dir: Vector3) -> Array:
	var s := Sim.spawn_state(1)
	s.pos = from
	s.grounded = true
	s.vel = dir.normalized() * Net.LAUNCH_V + Vector3(0, Net.LAUNCH_UP, 0)
	s.grounded = false
	s.down = Sim.DOWN_TICKS
	var bounces := 0
	var was_up := 0.0
	var ricochet := false
	var air_peak := 0.0
	var last_v := Vector2(s.vel.x, s.vel.z)
	var ticks := 0
	var inside := true
	while s.down > 0 and ticks < 1200:
		var vy := s.vel.y
		Sim.step(s, Sim.PlayerInput.new(ticks, 0, 0.0, 0.0, 0, 0, 0.0, 0.0))
		ticks += 1
		if vy < -1.0 and s.vel.y > 1.0:
			bounces += 1
		var hv := Vector2(s.vel.x, s.vel.z)
		if last_v.length() > 3.0 and hv.length() > 1.0 and hv.dot(last_v) < 0.0:
			ricochet = true
		last_v = hv
		air_peak = maxf(air_peak, s.pos.y)
		inside = inside and absf(s.pos.x) <= Config.WORLD_HALF and absf(s.pos.z) <= Config.WORLD_HALF
	return [Vector2(s.pos.x - from.x, s.pos.z - from.z).length(), bounces, ricochet, ticks, inside, s.down]


func _throw_tests() -> void:
	var open := _throw(Vector3(0, 0, 50), Vector3(1, 0, 0.3))
	print("thrown on open ground: %.1f m, %d bounces, down for %.1f s" % [open[0], open[1], open[3] / 60.0])
	check(open[0] > 20.0 and open[0] < 45.0, "a charge throws you 20-45 m across the arena (%.1f m)" % open[0])
	check(open[1] >= 1, "you bounce off the ground (%d bounces)" % open[1])
	check(open[5] == 0 and open[3] < 6 * 60, "then you lie and get up (%.1f s)" % (open[3] / 60.0))
	var oak: Vector3 = WorldLayout.TREES[2][1]   # into an oak's trunk from 6 m away
	var tree := _throw(oak + Vector3(6, 0, 0), Vector3(-1, 0, 0))
	check(tree[2], "thrown into a tree trunk, you ricochet off it")
	var edge := _throw(Vector3(Config.WORLD_HALF - 6.0, 0, 0), Vector3(1, 0, 0))
	check(edge[4] and edge[2], "thrown at the edge of the world, you stay inside and bounce back")
	# a charge throws players, and challengers / minions caught in it too
	for st in [Boss.S.CHARGE, Boss.S.RUSH]:
		var b := Boss.new(Vector3(0, 0, 50), 1, 5)
		b.yaw = 0.0
		b.state = st
		b.t = 1
		b.charge_dir = Vector2(0, -1)
		b.bystanders = [[1000001, Vector3(0.5, 0, 46)]]
		var thrown_p := false
		var thrown_n := false
		for k in 40:
			b.tick(k, [[1, Vector3(-0.5, 0, 44), true, false, 100]], [])
			for l in b.launches:
				thrown_p = thrown_p or int(l[0]) == 1
				thrown_n = thrown_n or int(l[0]) == 1000001
			b.launches.clear(); b.hits.clear(); b.fx.clear(); b.zaps.clear()
		check(thrown_p and thrown_n, "%s: the player and a challenger in his path are both thrown" % ("the charge" if st == Boss.S.CHARGE else "the rush"))


## v0.12.0: the Storm Leap lands at the point of the whole map furthest from every living player (maximin over the
## grid), within 200 m of his take-off; the arc grows with the distance.
func _maximin_tests() -> void:
	var c := Boss.arena_c()
	var cands := Boss.leap_candidates(c)
	check(cands.size() > 1000, "a grid of landing candidates over the whole map (%d)" % cands.size())
	var cases := [[c], [c + Vector3(8, 0, 3)], [c + Vector3(-12, 0, -10)], [c + Vector3(5, 0, 0), c + Vector3(-5, 0, 0)],
		[c + Vector3(0, 0, 14), c + Vector3(10, 0, -10)], [c + Vector3(-60, 0, 2), c + Vector3(80, 0, 40)]]
	var all_ok := true
	var inside := true
	var far := true
	for pts in cases:
		var q := Boss.maximin_spot(pts, c)
		var m := Boss.min_dist(q, pts)
		for o in cands:
			if Boss.min_dist(o, pts) > m + 0.011:
				all_ok = false
		var lim := Config.WORLD_HALF - Boss.LEAP_EDGE + 0.01
		inside = inside and absf(q.x) <= lim and absf(q.z) <= lim and Vector2(q.x - c.x, q.z - c.z).length() <= Boss.LEAP_MAX_D + 0.01
		far = far and Vector2(q.x - c.x, q.z - c.z).length() > 100.0
		var arc := Boss.leap_arc(Vector2(q.x - c.x, q.z - c.z).length())
		print("players %s -> lands %s (%.0f m away), %.0f m from the nearest player; apex %.0f m, %.1f s" % [str(pts.map(func(p): return Vector2(snappedf(p.x, 0.1), snappedf(p.z, 0.1)))), str(Vector2(q.x, q.z)), Vector2(q.x - c.x, q.z - c.z).length(), m, arc[0], int(arc[1]) / 60.0])
	check(all_ok, "with 1 and 2 players anywhere, no candidate on the map is further from the nearest player than his pick")
	check(inside, "the pick is always on the map, inside the edge, and within %d m of the take-off" % int(Boss.LEAP_MAX_D))
	check(far, "and it really is far: over 100 m every time")
	check(Boss.maximin_spot([c], c) == Boss.maximin_spot([c], c), "the same answer every time (deterministic)")
	var big := Boss.leap_arc(200.0)
	check(float(big[0]) >= 60.0 and int(big[1]) * Config.DT >= 3.0, "a 200 m bound is enormous (%d m up, %.1f s in the air)" % [int(big[0]), int(big[1]) * Config.DT])


## v0.12.0: he knows apples heal: fells trees now and then (more when they're low), charges through trees, tramples
## apples; cooldowns keep it pressure, not a wipe.
func _tree_run(low: bool, seed_v: int) -> Array:
	var c := Boss.arena_c()
	var b := Boss.new(c, 1, seed_v)
	b.state = Boss.S.IDLE
	var standing := [[30, c + Vector3(8, 0, 8)], [31, c + Vector3(-9, 0, 6)], [32, c + Vector3(6, 0, -10)], [33, c + Vector3(-12, 0, -8)]]
	var fells := 0
	var me := c + Vector3(0, 0, 14)
	for k in 60 * 60:
		b.trees = standing
		b.apples = []
		b.tick(k, [[1, me, true, false, 30 if low else 100]], [])
		for f in b.felled:
			fells += 1
			for i in range(standing.size() - 1, -1, -1):
				if int(standing[i][0]) == int(f[0]):
					standing.remove_at(i)
		b.felled.clear(); b.hits.clear(); b.fx.clear(); b.zaps.clear(); b.launches.clear(); b.strikes.clear(); b.slows.clear()
		b.splats.clear()
		b.hp = b.max_hp
	return [fells]


func _tree_tests() -> void:
	var low := 0
	var high := 0
	for sd in [3, 7, 11, 19]:
		low += int(_tree_run(true, sd)[0])
		high += int(_tree_run(false, sd)[0])
	print("trees felled in a minute: %d (players low) vs %d (healthy), over 4 fights" % [low, high])
	check(low >= 2, "he goes for the trees during the fight (%d)" % low)
	check(low >= high, "more when the players are low")
	check(low <= 4 * 5, "but no more than one every %d s (%d in 4 minutes)" % [Boss.TREE_CD / 60, low])
	# a charge runs through a tree in its path
	var c := Boss.arena_c()
	var b := Boss.new(c, 1, 2)
	b.state = Boss.S.CHARGE
	b.t = 1
	b.yaw = 0.0
	b.charge_dir = Vector2(0, -1)
	var smashed := false
	for k in 60:
		b.trees = [[40, c + Vector3(0.5, 0, -6)]] if not smashed else []
		b.tick(k, [[1, c + Vector3(0, 0, -16), true, false, 100]], [])
		smashed = smashed or not b.felled.is_empty()
		b.felled.clear(); b.hits.clear(); b.fx.clear(); b.launches.clear()
	check(smashed, "a tree in the path of his charge is smashed")
	# lining up: with a tree near the line to the target, he aims through it
	var lined := 0
	for sd in 20:
		var b2 := Boss.new(c, 1, 100 + sd)
		b2.trees = [[41, c + Vector3(2.0, 0, -8)]]
		var got = b2._tree_on_line(c + Vector3(0, 0, -16))
		if got != null:
			lined += 1
	check(lined >= 8 and lined < 20, "he usually (not always) lines a charge up through a tree on the way (%d of 20)" % lined)
	# apples: trampled underfoot, stomped when near
	var b3 := Boss.new(c, 1, 4)
	b3.state = Boss.S.IDLE
	b3.t = 0
	var stomped := false
	for k in 30:
		b3.apples = [[77, c + Vector3(3.5, 0.09, 0)]]
		b3.tick(k, [[1, c + Vector3(0, 0, 14), true, false, 100]], [])
		stomped = stomped or 77 in b3.splats
		b3.splats.clear(); b3.fx.clear(); b3.hits.clear()
	check(stomped, "an apple near him gets stomped to mush")
	check(b3.apple_cd > 0, "then a cooldown before the next stomp")


## v0.12.0: after a far leap he works his way home while still fighting a player who keeps near him.
func _attacks_in(b: Boss, ticks: int, follow: bool) -> Array:
	var attacks := 0
	var was := -1
	var start := Vector2(b.pos.x, b.pos.z).distance_to(Vector2(Boss.arena_c().x, Boss.arena_c().z))
	var me := b.pos + Vector3(0, 0, 12)
	for k in ticks:
		if follow:
			var off := me - b.pos
			if Vector2(off.x, off.z).length() > 14.0:
				me = b.pos + Vector3(off.x, 0, off.z).normalized() * 12.0
		b.tick(k, [[1, me, true, false, 100]], [])
		if b.state != was and Boss.S.keys()[b.state].ends_with("WIND"):
			attacks += 1
		was = b.state
		b.hp = b.max_hp
		b.hits.clear(); b.fx.clear(); b.zaps.clear(); b.launches.clear(); b.strikes.clear(); b.slows.clear(); b.felled.clear(); b.splats.clear()
		b.last_leap = k   # no new leaps during this test
	var end := Vector2(b.pos.x, b.pos.z).distance_to(Vector2(Boss.arena_c().x, Boss.arena_c().z))
	return [start, end, attacks]


func _home_tests() -> void:
	var c := Boss.arena_c()
	var home := Boss.new(c, 1, 9)
	home.state = Boss.S.IDLE
	var base := _attacks_in(home, 45 * 60, false)
	var away := Boss.new(c + Vector3(-140, 0, -120), 1, 9)
	away.state = Boss.S.IDLE
	var back := _attacks_in(away, 45 * 60, true)
	print("from %.0f m out: %.0f m from the arena after 45 s; %d attacks (%d in the arena)" % [back[0], back[1], back[2], base[2]])
	check(back[1] < WorldLayout.ARENA_R + 15.0, "after a far leap he is back near the arena within 45 s of fighting (%.0f m)" % back[1])
	check(back[2] >= base[2] * 0.7, "and keeps attacking on the way (%d vs %d attacks)" % [back[2], base[2]])
	var lone := Boss.new(c + Vector3(150, 0, -100), 1, 9)
	lone.state = Boss.S.IDLE
	var went_home := false
	for k in 30 * 60:
		lone.tick(k, [[1, c + Vector3(0, 0, 5), true, false, 100]], [])
		went_home = went_home or lone.state == Boss.S.HOME
		lone.hits.clear(); lone.fx.clear(); lone.zaps.clear(); lone.launches.clear(); lone.strikes.clear(); lone.slows.clear()
		lone.last_leap = k
	check(went_home and Vector2(lone.pos.x - c.x, lone.pos.z - c.z).length() < WorldLayout.ARENA_R + 10.0, "with nobody near him he gallops home")


## Ten orbs at one player: standing still, or sprinting in a circle and dashing now and then. -> hits.
func _orb_run(move: bool) -> int:
	var b := Boss.new(Vector3(0, 0, 56), 1, 21)
	b.state = Boss.S.LEAP_LAND
	b.t = 39
	var s := Sim.spawn_state(1)
	s.pos = Vector3(0, 0, 42)
	var hits := 0
	for k in 560:
		var btn := 0
		var yaw := 0.0
		if move:
			yaw = k * 0.012
			btn = Sim.Btn.FORWARD | Sim.Btn.SPRINT | (Sim.Btn.DASH if k % 60 == 30 else 0)
		Sim.step(s, Sim.PlayerInput.new(k, btn, yaw, 0.0, 0, 0, yaw, yaw))
		b.tick(k, [[1, s.pos, true, false, 100]], [])
		for z in b.zaps:
			hits += 1
		b.zaps.clear(); b.hits.clear(); b.fx.clear()
		if b.state == Boss.S.SLAMS:
			break
	return hits
