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
		b.rng.seed = 12345   # deterministic (it used to fail now and then: see below)
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
			# stop as soon as the rush is over: before, a random next attack (a charge, called lightning) after the
			# recovery could land and make the dodge look like a miss now and then
			if net.boss == null or (b.state == Boss.S.IDLE and k > 300) or (b.state == Boss.S.RECOVER and launched_at < 0 and dodge):
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

	_stun_meter_tests(net)
	_golem_tests(net)
	_dodge_tests()
	_throw_tests()
	_maximin_tests()
	_tree_tests()
	_home_tests()
	print("%d failed" % bad)
	quit(bad)


## v0.12.2 golems are first-class foes: he goes after a golem that's hurting him (but not only it), every damaging
## attack hurts a golem in its reach (titans less), the charge throws them, and he kills a normal golem in good time
## through the real server loop, with nobody getting level credit for it.
func _golem_hit(b: Boss, gid: int) -> int:
	var dmg := 0
	for h in b.hits:
		if int(h[0]) == -1000 - gid:
			dmg += int(h[1])
	return dmg


## One attack against one golem: state set up by `setup`, ticked up to `n` ticks -> [damage to the golem, launched].
func _golem_attack(setup: Callable, gpos_rel: Vector3, n: int, titan := false) -> Array:
	var c := Boss.arena_c()
	var b := Boss.new(c, 1, 5)
	b.yaw = 0.0   # facing -Z
	var gp := c + gpos_rel
	var me := [[1, c + Vector3(30, 0, 30), true, false, 100]]   # a player well out of it all
	var gl := [[7, gp, titan, 150 if titan else 40]]
	setup.call(b, gp)
	var dmg := 0
	var thrown := false
	for k in n:
		b.tick(1 + k, me, gl)
		dmg += _golem_hit(b, 7)
		for l in b.launches:
			if int(l[0]) == -1007:
				thrown = true
		b.hits.clear(); b.fx.clear(); b.zaps.clear(); b.launches.clear(); b.strikes.clear(); b.slows.clear()
		b.felled.clear(); b.splats.clear()
		if dmg > 0 and k > 40:
			break
	return [dmg, thrown]


func _golem_tests(net: Net) -> void:
	var c := Boss.arena_c()
	# ---- targeting: a golem slamming him gets real attention; the fairness cap keeps the player in it
	var b := Boss.new(c, 1, 11)
	b.state = Boss.S.IDLE
	var me := [[1, c + Vector3(0, 0, 13), true, false, 100]]
	var gl := [[7, c + Vector3(3.5, 0, -3.0), false, 40]]
	var on_g := 0
	var on_p := 0
	for k in 3600:
		if k % 40 == 0:
			b.note_golem_hit(7, 8)   # the golem's slams
		b.tick(k, me, gl)
		b.hits.clear(); b.fx.clear(); b.zaps.clear(); b.launches.clear(); b.strikes.clear(); b.slows.clear()
		b.felled.clear(); b.splats.clear()
		b.hp = maxi(b.hp, int(b.max_hp * 0.9))
		b.leaps = Boss.LEAP_MAX
		me[0][1] = (me[0][1] as Vector3) * Vector3(1, 0, 1)
		if b.target == -1007:
			on_g += 1
		elif b.target == 1:
			on_p += 1
	var gk := float(on_g) / float(maxi(on_g + on_p, 1))
	check(gk > 0.25, "a golem slamming him: he goes after it (%.0f%% of the time)" % (gk * 100))
	check(gk < 0.6, "but the fairness cap keeps him on the player too (%.0f%% on the player)" % (100 - gk * 100))
	var b2 := Boss.new(c, 1, 11)
	var idle_g := 0
	for k in 60:
		b2._retarget([[1, c + Vector3(0, 0, 9), true, false, 100]], [[7, c + Vector3(-25, 0, 20), false, 40]])
		if b2.target == -1007:
			idle_g += 1
	check(idle_g < 10, "a far golem that isn't hurting him is mostly ignored (%d of 60 picks)" % idle_g)
	var b3 := Boss.new(c, 1, 11)
	var wall := 0
	for k in 60:   # a golem standing between him and the player
		b3._retarget([[1, c + Vector3(0, 0, -16), true, false, 100]], [[7, c + Vector3(0.5, 0, -7), false, 40]])
		if b3.target == -1007:
			wall += 1
	check(wall > 20, "a golem standing between him and a player draws him (%d of 60 picks)" % wall)

	# ---- every damaging attack hurts a golem in its reach
	var cases := {
		"charge": [func(bb: Boss, _g: Vector3):
			bb.state = Boss.S.CHARGE; bb.charge_dir = Vector2(0, -1); bb.charge_hit = {}, Vector3(0, 0, -10), 60],
		"rush": [func(bb: Boss, _g: Vector3):
			bb.state = Boss.S.RUSH; bb.charge_dir = Vector2(0, -1); bb.charge_hit = {}; bb.rush_target = 1, Vector3(0, 0, -10), 60],
		"gore": [func(bb: Boss, _g: Vector3):
			bb.state = Boss.S.GORE; bb.t = 4, Vector3(0.5, 0, -4.5), 10],
		"stomp ring": [func(bb: Boss, _g: Vector3):
			bb.state = Boss.S.STOMP_WIND; bb.t = 200, Vector3(6, 0, 3), 90],
		"map-wide wave": [func(bb: Boss, _g: Vector3):
			bb.state = Boss.S.HOWL; bb.t = 1; bb.orb_plan = 0
			bb.rings.append([Boss.RADIUS, {}, Vector3(bb.pos.x, 0, bb.pos.z), Boss.WAVE_V, 12, 2, Boss.wave_max(bb.pos)]), Vector3(0, 0, -60), 200],
		"horn beam": [func(bb: Boss, _g: Vector3):
			bb.state = Boss.S.BEAM; bb.t = 0; bb.beam_from = 0.0; bb.beam_to = 0.0; bb.beam_a = 0.0, Vector3(0, 0, -16), 20],
		"ball lightning": [func(bb: Boss, g: Vector3):
			bb.state = Boss.S.STAGGER; bb.t = -999
			bb.balls.append([g + Vector3(0, 1.1, 4), Vector3(0, 0, -4), 300, false]), Vector3(-12, 0, -10), 120],
		"static ball": [func(bb: Boss, g: Vector3):
			bb.state = Boss.S.STAGGER; bb.t = -999
			bb.balls.append([g + Vector3(0, 1.1, 4), Vector3(0, 0, -4), 300, true]), Vector3(-12, 0, -10), 120],
		"homing orbs": [func(bb: Boss, g: Vector3):
			bb.state = Boss.S.STAGGER; bb.t = -999; bb.target = -1007
			bb.gols = Boss.golem_foes([[7, g, false, 40]])
			for i in 4:
				bb._launch_orb([[1, bb.pos + Vector3(30, 0, 30), true, false, 100]], i), Vector3(-14, 0, -8), 400],
		"tail lash": [func(bb: Boss, _g: Vector3):
			bb.state = Boss.S.TAIL; bb.t = 8; bb.move_side = 1.0, Vector3(0, 0, 4.5), 10],
		"static field": [func(bb: Boss, _g: Vector3):
			bb.state = Boss.S.STAGGER; bb.t = -999, Vector3(Boss.RADIUS + 0.6, 0, 0), 40],
		"leap landing": [func(bb: Boss, _g: Vector3):
			bb.state = Boss.S.LEAP; bb.t = 0; bb.leap_from = bb.pos; bb.leap_to = bb.pos; bb.leap_air = 3, Vector3(1.5, 0, 1.5), 6],
	}
	var normal := {}
	for k in cases:
		var cs: Array = cases[k]
		var r := _golem_attack(cs[0], cs[1], cs[2])
		normal[k] = int(r[0])
		check(int(r[0]) > 0, "%s hurts a golem in reach (%d)" % [k, int(r[0])])
		if k in ["charge", "rush"]:
			check(bool(r[1]), "%s throws the golem" % k)
	var rt := _golem_attack(cases["gore"][0], cases["gore"][1], cases["gore"][2], true)
	check(int(rt[0]) > 0 and int(rt[0]) < int(normal["gore"]), "a Stone Titan takes less (gore: %d vs %d)" % [int(rt[0]), int(normal["gore"])])
	# called lightning: a strike under the golem he's fighting, and the server's bolt hurts it
	var bc := Boss.new(c, 1, 5)
	bc.state = Boss.S.CALL
	bc.t = 19
	bc.target = -1007
	bc.tick(1, [[1, c + Vector3(20, 0, 0), true, false, 100]], [[7, c + Vector3(-9, 0, -6), false, 40]])
	var under := false
	for st in bc.strikes:
		if _flat_d(st[0], c + Vector3(-9, 0, -6)) < 0.5:
			under = true
	check(under, "called lightning: a warning circle under the golem he's fighting")

	# ---- through the server: a strike, a toss, and he kills a golem in good time; no level credit
	net.boss = null
	net.summon_boss()
	var nb: Boss = net.boss
	nb.state = Boss.S.IDLE
	nb.rng.seed = 77
	var pl: Net.ServerPlayer = net.players[1]
	pl.state = Sim.spawn_state(1)
	pl.state.pos = nb.pos + Vector3(0, 0, 26)
	var kills0: Array = pl.kills.duplicate()
	var wl := pl.state.wand_lvl
	var sl := pl.state.staff_lvl
	var g := net.golems.spawn(1, nb.pos + Vector3(-12, 0, -6), 0.0, net.server_tick)
	g.state = Golems.State.IDLE
	var hp0 := g.hp
	net.pending_spells.append([net.server_tick + 1, "boss_strike", g.pos, 0])
	net._server_spells()
	net.server_tick += 1
	net._server_spells()
	check(g.hp < hp0, "the server's called-lightning bolt hurts a golem under it (%d -> %d)" % [hp0, g.hp])
	g.hp = hp0
	var gp0 := g.pos
	net._toss_golem(g.id, Vector3(1, 0, 0))
	var peak := 0.0
	for i in 90:
		net._tick_golem_tosses()
		peak = maxf(peak, g.pos.y)
	check(peak > 1.0 and g.pos.y == 0.0 and _flat_d(g.pos, gp0) > 3.0, "a thrown golem flies (%.1f m up, %.1f m off) and lands" % [peak, _flat_d(g.pos, gp0)])
	g.stun = 0
	var dead_at := -1
	var noted := 0.0
	for i in 60 * 40:
		pl.state.hp = Sim.MAX_HP   # keep the player in the fight
		pl.state.dead = 0
		net._server_tick()
		if net.boss != null:
			noted = maxf(noted, float(net.boss.gthreat.get(-1000 - g.id, 0.0)))
		if not net.golems.list.has(g.id) or net.golems.list[g.id].state == Golems.State.DIE:
			dead_at = i
			break
		if net.boss == null:
			break
	check(noted > 0.0, "the golem's slams on him count as its threat (%.0f)" % noted)
	check(dead_at >= 0 and dead_at < 60 * 30, "he kills a golem that fights him in %.1f s" % (dead_at / 60.0))
	check(pl.kills == kills0 and pl.state.wand_lvl == wl and pl.state.staff_lvl == sl, "and nobody gets level credit for it")
	net.boss = null
	net.golems.list.clear()


func _flat_d(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## v0.12.0 the stun meter: 9 Stun hits don't, the 10th dazes him 7 s; it holds, drains, interrupts anything (the
## charge, the Storm Leap in the air), is the only thing that stops a charge, is sent to clients, and fog (the wand's)
## doesn't change who he goes after.
func _tick_n(b: Boss, n: int, ppl: Array, from := 0) -> void:
	for k in n:
		b.tick(from + k, ppl, [])
		b.hits.clear(); b.fx.clear(); b.zaps.clear(); b.launches.clear(); b.strikes.clear(); b.slows.clear()
		b.felled.clear(); b.splats.clear()


func _stun_meter_tests(net: Net) -> void:
	var c := Boss.arena_c()
	var me := [[1, c + Vector3(0, 0, 14), true, false, 100]]
	var b := Boss.new(c, 1, 3)
	b.state = Boss.S.IDLE
	b.last_leap = 0
	var n1 := Boss.STUN_NEED - 1
	for i in n1:
		b.stunned(i)
	check(b.state != Boss.S.DAZED and is_equal_approx(b.stun_m, n1), "%d Stun hits: not dazed (meter %.0f/%d)" % [n1, b.stun_m, Boss.STUN_NEED])
	var hold := Boss.stun_hold_ticks()
	var sp: Dictionary = {}
	for x in Weapons.get_data(Weapons.WAND).spells:
		if str(x.name) == "Stun":
			sp = x
	check(hold > int(sp.recharge) + int(sp.cast), "the meter holds longer than the Stun's recharge + cast (%.1f s vs %.1f s)" % [hold / 60.0, (int(sp.recharge) + int(sp.cast)) / 60.0])
	_tick_n(b, hold - 5, me)
	check(is_equal_approx(b.stun_m, n1), "the meter holds for %.1f s after a hit" % (hold / 60.0))
	_tick_n(b, 5 + Boss.STUN_DRAIN * 3, me)
	check(b.stun_m < n1 - 2.4 and b.stun_m > n1 - 3.6, "then drains a point every %.0f s (%.2f after 3 points' time)" % [Boss.STUN_DRAIN / 60.0, b.stun_m])
	_tick_n(b, Boss.STUN_DRAIN * 8, me)
	check(b.stun_m == 0.0, "and empties when nobody keeps stunning him")
	for i in Boss.STUN_NEED:
		b.stunned(i)
	check(b.state == Boss.S.DAZED, "the %dth hit dazes him" % Boss.STUN_NEED)
	var hp0 := b.hp
	b.hurt(40, 1, "")
	check(b.hp == hp0 - 40, "dazed, he takes normal damage")
	b.rings.clear(); b.balls.clear(); b.orbs.clear()   # (what was already flying)
	var p0 := b.pos
	var hits := 0
	for k in Boss.STUN_TICKS - 2:
		b.tick(k, [[1, c + Vector3(0, 0, 3.5), true, false, 100]], [])
		hits += b.hits.size()
		b.hits.clear(); b.fx.clear(); b.zaps.clear(); b.launches.clear(); b.strikes.clear(); b.slows.clear()
	check(b.state == Boss.S.DAZED and hits == 0 and b.pos.distance_to(p0) < 0.01, "(%s, %d hits, moved %.2f m) for 7 s" % [Boss.S.keys()[b.state], hits, b.pos.distance_to(p0)] + "  he does nothing (no attacks, no static field, no moving), even with someone right next to him")
	for i in 3:
		b.stunned(i)   # Stuns while he's down don't count
	_tick_n(b, 3, me)
	check(b.state != Boss.S.DAZED and b.stun_m == 0.0, "then he gets up, the meter empty (%.1f s; Stuns while he was down didn't count)" % (Boss.STUN_TICKS / 60.0))
	# casting Stun on every recharge fills it; missing every 4th cast still does; two players fill it faster
	var every := int(sp.recharge) + int(sp.cast)
	for case in [[1, 0], [1, 4], [2, 0]]:
		var bb := Boss.new(c, 1, 9)
		bb.state = Boss.S.IDLE
		var casts := 0
		var filled := -1
		for k in 60 * 60:
			for who in int(case[0]):
				if (k + who * every / 2) % every == 0:
					casts += 1
					if int(case[1]) == 0 or casts % int(case[1]) != 0:
						bb.stunned(k)
			bb.tick(k, me, [])
			bb.hits.clear(); bb.fx.clear(); bb.zaps.clear(); bb.launches.clear(); bb.strikes.clear(); bb.slows.clear()
			bb.hp = bb.max_hp
			bb.last_leap = k
			if bb.state == Boss.S.DAZED:
				filled = k
				break
		var what := "%d wand player%s on cooldown%s" % [case[0], "s" if case[0] > 1 else "", ", missing every 4th" if case[1] > 0 else ""]
		var limit := (25 if case[0] == 2 else (50 if case[1] > 0 else 40)) * 60
		check(filled >= 0 and filled < limit, "%s: dazed after %.1f s (under %d s)" % [what, filled / 60.0, limit / 60])
	# the only way to stop a charge: fill the meter during the wind-up or the gallop
	var ch := Boss.new(c, 1, 5)
	ch.state = Boss.S.IDLE
	ch._attack("charge", c + Vector3(0, 0, -20))
	_tick_n(ch, 60, [[1, c + Vector3(0, 0, -20), true, false, 100]])
	check(ch.state == Boss.S.CHARGE, "(a charge under way)")
	ch.frosted()
	var at := ch.pos
	_tick_n(ch, 6, [[1, c + Vector3(0, 0, -20), true, false, 100]])
	check(ch.pos.distance_to(at) > Boss.GALLOP * 0.09, "frost doesn't slow a charge any more (%.1f m in 0.1 s)" % ch.pos.distance_to(at))
	for i in Boss.STUN_NEED:
		ch.stunned(i)
	at = ch.pos
	_tick_n(ch, 30, [[1, c + Vector3(0, 0, -20), true, false, 100]])
	check(ch.state == Boss.S.DAZED and ch.pos.distance_to(at) < 0.01, "a full meter stops the charge dead")
	# the Storm Leap: filled in the air, he lands and drops; the rest of the sequence is dropped
	var lp := Boss.new(c, 1, 6)
	lp.state = Boss.S.IDLE
	lp._start_leap(me)
	_tick_n(lp, 100, me)
	check(lp.state == Boss.S.LEAP and lp.pos.y > 1.0, "(in the air)")
	for i in Boss.STUN_NEED:
		lp.stunned(i)
	check(lp.state == Boss.S.LEAP, "filled mid-leap: he still lands first")
	_tick_n(lp, lp.leap_air, me)
	check(lp.state == Boss.S.DAZED and lp.pos.y == 0.0, "then drops, dazed, where he landed")
	_tick_n(lp, Boss.STUN_TICKS + 2, me)
	check(not lp.in_sequence(), "and gets up into his normal attacks (the leap sequence is over)")
	# synced: the meter and the dazed flag go out with his state
	var pk := Boss.new(c, 1, 7)
	pk.state = Boss.S.IDLE
	for i in 4:
		pk.stunned(i)
	var d := pk.pack()
	check(is_equal_approx(float(d[13][8]), 4.0), "his state carries the meter (%s)" % str(d[13][8]))
	for i in Boss.STUN_NEED - 4:
		pk.stunned(i)
	check(int(pk.pack()[8]) & 64 != 0, "and the dazed flag")
	# fog (the wand's, when it's in the game) doesn't change who he goes after
	var seq := []
	for fogged in [false, true]:
		net.summon_boss()
		net.boss.state = Boss.S.IDLE
		net.boss.rng.seed = 77
		net.server_tick = 50000
		net.defeated = false
		var a: Net.ServerPlayer = net.players[1]
		a.state = Sim.spawn_state(1)
		a.state.pos = net.boss.pos + Vector3(5, 0, 10)
		if fogged and "fogs" in net:
			var fog_script = load("res://scripts/fog.gd")
			net.set("fogs", [fog_script.make(1, a.state.pos, 1, net.server_tick, {"duration": 100000})])
		var picks := []
		for k in 600:
			net.server_tick += 1
			a.state.hp = Sim.MAX_HP   # (kept alive: this is about his choices)
			a.state.dead = 0
			net._server_boss()
			if net.boss == null:
				break
			picks.append([net.boss.target, net.boss.state])
		seq.append(picks)
		if "fogs" in net:
			net.set("fogs", [])
		net.boss = null
	var first_diff := -1
	for i in mini(seq[0].size(), seq[1].size()):
		if seq[0][i] != seq[1][i] and first_diff < 0:
			first_diff = i
			print("diverge at %d: %s vs %s" % [i, str(seq[0][i]), str(seq[1][i])])
	check(seq[0] == seq[1], "fog over the player changes nothing about his targeting or attacks%s" % ("" if "fogs" in net else " (fog not in this build: trivially)"))
	net.boss = null


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


# ================================================================ v0.12.0 the dodge audit
## A "skilled dodger" bot against each of his attacks: it sees the world REACT ticks late (~250 ms: the boss's state,
## rings, orbs, balls and the warning circles, extrapolated forward the way a player reads motion) and gives each
## attack its answer: side-dash the charge, the rush and the gore; back off from the tail lash and the roar; jump the
## rings and waves; leave the marked spots (called lightning, the leap's landing); outrun or dash the balls and orbs; out
## of the beam's reach or dash through it as it sweeps over. An idle player is set up the same way. Each type must be
## avoided >= 90% of the time by the bot, while the idle player is hit by most.
const REACT := 15
const DEBUG_DODGE := false
const DODGE_TRIALS := 24
var dodge_report: Array = []


func _snap(b: Boss) -> Dictionary:
	return {"st": b.state, "t": b.t, "pos": b.pos, "yaw": b.yaw, "beam_from": b.beam_from, "beam_to": b.beam_to,
		"variant": b.variant, "leap_to": b.leap_to, "stomp_w": b._wind(48), "leap_air": b.leap_air,
		"rings": b.rings.map(func(r): return [float(r[0]), r[2], float(r[3])]),
		"orbs": b.orbs.filter(func(o): return not o[5]).map(func(o): return [o[0], o[1]]),
		"balls": b.balls.map(func(x): return [x[0], x[1]])}


static func _f(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## The beam's heading at tick t of S.BEAM (the server's formula: there, then back again when enraged).
static func _beam_at(o: Dictionary, t: int) -> float:
	if t <= 90:
		return lerp_angle(o.beam_from, o.beam_to, clampf(float(t) / 90.0, 0.0, 1.0))
	return lerp_angle(o.beam_to, o.beam_from, clampf(float(t - 90) / 70.0, 0.0, 1.0))


## One tick of the bot: -> [buttons, yaw]. o: what it saw REACT ticks ago; mem: its own notes for this trial.
func _bot(s: Sim.PlayerState, o: Dictionary, strikes_seen: Array, now: int, mem: Dictionary) -> Array:
	var me := _f(s.pos)
	var bp := _f(o.pos)
	var rel := me - bp
	var d := rel.length()
	var away := rel.normalized() if d > 0.01 else Vector2(1, 0)
	var fwd := Vector2(-sin(o.yaw), -cos(o.yaw))
	var lag := REACT * Config.DT
	var want := Vector2.ZERO
	var dash := false
	var jump := false
	var st: int = o.st
	# rings: jump as the band arrives (its speed is steady: read where it is now)
	for r in o.rings:
		var rd := (me - _f(r[1])).length()
		var rn: float = float(r[0]) + float(r[2]) * lag
		var ta := (rd - 0.7 - rn) / float(r[2])
		if s.grounded and ta > 0.05 and ta < 0.12:
			jump = true
	# the rings he's about to send: a player reads the rhythm (the rear, the slam) and jumps on the beat, not after
	# seeing the ring (one sent from 5 m away arrives before anyone could react to it)
	var tn := int(o.t) + REACT
	var future := []   # [tick in the state it goes out, speed, start radius, centre]
	var gc := Vector3(o.pos.x, 0, o.pos.z)
	match st:
		Boss.S.STOMP_WIND:
			future.append([int(o.stomp_w) - int(o.t), Boss.STOMP_V, Boss.RADIUS, gc])
			for i in range(1, 4 if o.variant > 0 else 3):
				future.append([int(o.stomp_w) - int(o.t) + Boss.STOMP_EVERY * i, Boss.STOMP_V, Boss.RADIUS, gc])
		Boss.S.STOMP:
			for i in range(1, 4 if o.variant > 0 else 3):
				future.append([Boss.STOMP_EVERY * i - int(o.t), Boss.STOMP_V, Boss.RADIUS, gc])
				if o.variant > 0 and i == 3:
					future.append([Boss.STOMP_EVERY * i - int(o.t), Boss.STOMP_V, Boss.RADIUS - 1.6, gc])
		Boss.S.SLAMS:
			for i in 3:
				future.append([30 + i * Boss.WAVE_GAP - int(o.t), Boss.WAVE_V, Boss.RADIUS, gc])
		Boss.S.LEAP_WIND:
			future.append([90 - int(o.t) + int(o.leap_air), Boss.WAVE_V, Boss.RADIUS, o.leap_to])
		Boss.S.LEAP:
			future.append([int(o.leap_air) - int(o.t), Boss.WAVE_V, Boss.RADIUS, o.leap_to])
	for f in future:
		if int(f[0]) <= 0:
			continue   # already out: it is in the list above
		var rd := (me - _f(f[3])).length()
		var ta := (int(f[0]) - REACT) * Config.DT + (rd - 0.7 - float(f[2])) / float(f[1])
		if s.grounded and ta > 0.05 and ta < 0.12 and rd > float(f[2]) - 0.7:
			jump = true
	# warning circles: step out of any that will fire soon
	for k in strikes_seen:
		var sp := _f(k[0])
		if int(k[1]) > now and (me - sp).length() < 4.2:
			want += (me - sp).normalized() * 2.0
	match st:
		Boss.S.CHARGE_WIND, Boss.S.CHARGE, Boss.S.PAW, Boss.S.RUSH:
			var perp := Vector2(-fwd.y, fwd.x)
			var lat := rel.dot(perp)
			var side := perp * (1.0 if lat >= 0.0 else -1.0)
			var along := rel.dot(fwd)
			if absf(lat) < 6.5 and along > -4.0:
				want += side
			if st in [Boss.S.CHARGE, Boss.S.RUSH]:
				var v := (Boss.RUSH_V if st == Boss.S.RUSH else Boss.GALLOP * (1.3 if o.variant > 0 else 1.0))
				var gap := along - v * lag
				var key := "dashed%d" % int(o.get("seq", 0))
				if gap < 10.0 and gap > 0.0 and absf(lat) < 5.5 and not mem.has(key):
					dash = true
					mem[key] = true
		Boss.S.GORE_WIND, Boss.S.GORE, Boss.S.TAIL_WIND, Boss.S.TAIL:
			if d < 9.5:
				want += away * 2.0
				if not mem.has("dashed"):
					dash = true
					mem["dashed"] = true
		Boss.S.ROAR:
			if d < 17.0:
				want += away * 2.0
				if not mem.has("dashed"):
					dash = true
					mem["dashed"] = true
		Boss.S.BEAM_WIND:
			want += away * 2.0
		Boss.S.BEAM:
			want += away * 2.0
			for k in [1, 3, 5]:
				if Boss.beam_hits(o.pos, _beam_at(o, tn + k), s.pos, o.yaw) and s.dash_cd == 0:
					dash = true
		Boss.S.LEAP_WIND, Boss.S.LEAP:
			var lt := _f(o.leap_to)
			if (me - lt).length() < Boss.RADIUS + 6.0:
				want += (me - lt).normalized() * 2.0
	# balls and orbs: run from the nearest one coming; sidestep across its path; dash it at the last moment
	var near := INF
	var flee := Vector2.ZERO
	for x in o.orbs + o.balls:
		var p: Vector3 = (x[0] as Vector3) + (x[1] as Vector3) * lag
		var v := _f(x[1])
		var off := me - _f(p)
		var dist := off.length()
		if dist < 9.0 and dist < near and (v.length() < 0.1 or v.dot(off) > 0.0):
			near = dist
			var across := Vector2(-v.y, v.x).normalized()
			if across.dot(off) < 0.0:
				across = -across
			flee = (across * 1.5 + off.normalized()).normalized() if v.length() > 7.0 else off.normalized()
	if near < INF:
		want += flee * 3.0
		if near < 1.8 and s.dash_cd == 0:
			dash = true
	elif st in [Boss.S.HOWL, Boss.S.BALLS] or not o.orbs.is_empty():
		want += Vector2(-away.y, away.x) + away * clampf((14.0 - d) * 0.2, -1.0, 1.0)   # keep moving, round him
	if want.length() < 0.01:
		return [Sim.Btn.JUMP if jump else 0, s.yaw]
	var yaw := atan2(-want.x, -want.y)
	return [Sim.Btn.FORWARD | Sim.Btn.SPRINT | (Sim.Btn.DASH if dash else 0) | (Sim.Btn.JUMP if jump else 0), yaw]


## One trial: -> [hits on the player, chances (1, or the orbs sent)].
func _dodge_trial(kind: String, sd: int, skilled: bool, enraged: bool) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd * 7919 + (1 if enraged else 0)
	var c := Boss.arena_c()
	var b := Boss.new(c, 1, sd)
	b.enraged = enraged
	b.phase = 1 if enraged else 0
	b.want_phase = b.phase
	b.yaw = rng.randf() * TAU
	b.last_leap = 0
	var fwd := Vector2(-sin(b.yaw), -cos(b.yaw))
	var ang := rng.randf_range(-0.5, 0.5)
	var dist := 12.0
	match kind:
		"charge": dist = rng.randf_range(12.0, 22.0)
		"gore": dist = rng.randf_range(4.6, 6.6)
		"tail":
			dist = rng.randf_range(4.6, 7.0)
			ang = PI + rng.randf_range(-1.4, 1.4)
		"stomp": dist = rng.randf_range(5.0, 14.0)
		"beam": dist = rng.randf_range(9.0, 19.0)
		"call": dist = rng.randf_range(8.0, 20.0)
		"balls": dist = rng.randf_range(8.0, 16.0)
		"roar": dist = rng.randf_range(6.0, 10.0)
		"rush": dist = rng.randf_range(12.0, 20.0)
		"orbs": dist = rng.randf_range(10.0, 16.0)
		"waves": dist = rng.randf_range(5.0, 25.0)
		"leap": dist = 0.0
	var dir := fwd.rotated(ang)
	if kind == "leap":
		dir = Vector2(1, 0)
	var s := Sim.spawn_state(1)
	s.pos = c + Vector3(dir.x, 0, dir.y) * dist
	var ppl := func(): return [[1, s.pos, true, false, 100, s.dash_ticks, false, false]]
	var end_st := Boss.S.IDLE
	match kind:
		"rush":
			b.state = Boss.S.SLAMS
			b.t = 30 + 2 * Boss.WAVE_GAP + 39
			b.yaw = atan2(-(s.pos - c).x, -(s.pos - c).z)
			end_st = Boss.S.RECOVER
		"orbs":
			b.state = Boss.S.LEAP_LAND
			b.t = 39
			end_st = Boss.S.SLAMS
		"waves":
			b.state = Boss.S.SLAMS
			b.t = 0
			end_st = Boss.S.PAW
		"leap":   # he takes off 40 m away and comes down on (about) you
			b.pos = c + Vector3(dir.x, 0, dir.y) * -40.0
			b._start_leap(ppl.call())
			b.leap_to = s.pos + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
			end_st = Boss.S.HOWL
		"call":
			b.storm = enraged and sd % 2 == 0
			b._attack("call", s.pos)
		_:
			b._attack(kind, s.pos)
	var hist: Array = []
	var pending: Array = []   # called lightning: [point, fire tick, seen from tick]
	var mem := {}
	var hits := 0
	var chances := 1
	var seq := 0
	var last_st := -1
	var started := false
	for k in 1200:
		var snap := _snap(b)
		if b.state == Boss.S.CHARGE_WIND and last_st == Boss.S.CHARGE:
			seq += 1   # the next charge of a double
		last_st = b.state
		snap["seq"] = seq
		hist.append(snap)
		var o: Dictionary = hist[maxi(hist.size() - 1 - REACT, 0)]
		var btn := 0
		var yaw := s.yaw
		if skilled:
			var seen := pending.filter(func(x): return k >= int(x[2])).map(func(x): return [x[0], x[1]])
			var out := _bot(s, o, seen, k, mem)
			btn = out[0]
			yaw = out[1]
		Sim.step(s, Sim.PlayerInput.new(k, btn, yaw, 0.0, 0, 0, yaw, yaw))
		b.tick(k, ppl.call(), [])
		var got := false
		for h in b.hits:
			got = got or int(h[0]) == 1
		for z in b.zaps:
			if int(z[0]) == 1:
				if kind == "orbs":
					hits += 1
				got = true
		for sl in b.slows:
			got = got or int(sl[0]) == 1
		for st in b.strikes:
			pending.append([st[0], k + int(st[1]), k + REACT])
		for e in pending.duplicate():
			if k >= int(e[1]):
				pending.erase(e)
				var cp: Vector3 = e[0]
				var y := clampf(cp.y, s.pos.y, s.pos.y + 1.8)
				if cp.distance_to(Vector3(s.pos.x, y, s.pos.z)) <= 2.5:
					got = true
		if kind != "orbs" and got:
			if hits == 0 and skilled and DEBUG_DODGE:
				print("DBG %s k=%d st=%s t=%d d=%.1f y=%.2f gr=%s rings=%s leap_to=%s" % [kind, k, Boss.S.keys()[b.state], b.t, _f(s.pos - b.pos).length(), s.pos.y, s.grounded, str(b.rings.map(func(r): return snappedf(float(r[0]), 0.1))), str(b.leap_to)])
			hits = 1
		b.hits.clear(); b.fx.clear(); b.zaps.clear(); b.launches.clear(); b.strikes.clear(); b.slows.clear()
		b.felled.clear(); b.splats.clear()
		if b.state == end_st and k > 2:
			started = true
		if started:
			b.state = end_st
			b.t = 0
			if kind == "orbs":
				chances = b.orb_total
				if b.orbs.is_empty():
					break
			elif pending.is_empty() and b.rings.is_empty() and b.balls.is_empty():
				break
	return [hits, chances]


func _dodge_tests() -> void:
	var kinds := ["charge", "rush", "gore", "tail", "stomp", "waves", "beam", "call", "balls", "roar", "leap", "orbs"]
	print("attack     tell (calm / enraged+2p)   skilled bot avoided   idle player hit")
	for kind in kinds:
		var res := {true: [0, 0], false: [0, 0]}
		for skilled in [true, false]:
			for i in DODGE_TRIALS:
				var r := _dodge_trial(kind, 1000 + i, skilled, i % 2 == 1)
				res[skilled][0] += int(r[0])
				res[skilled][1] += int(r[1])
		var avoid := 1.0 - float(res[true][0]) / float(res[true][1])
		var idle_hit := float(res[false][0]) / float(res[false][1])
		var tell := _tell(kind)
		print("%-10s %-26s %5.0f%% (%d/%d)        %5.0f%%" % [kind, tell, avoid * 100.0, res[true][1] - res[true][0], res[true][1], idle_hit * 100.0])
		dodge_report.append([kind, tell, avoid, idle_hit])
		check(avoid >= 0.9, "dodge: the skilled bot avoids the %s %.0f%% of the time (>= 90%%)" % [kind, avoid * 100.0])
		check(idle_hit >= 0.5, "dodge: an idle player is hit by the %s %.0f%% of the time (most)" % [kind, idle_hit * 100.0])


## The telegraph of each attack, calm and at its shortest (enraged with two players), in seconds.
func _tell(kind: String) -> String:
	var calm := Boss.new(Vector3.ZERO, 1, 1)
	var fast := Boss.new(Vector3.ZERO, 2, 1)
	fast.enraged = true
	var w := func(base: int, plus: int) -> String:
		return "%.2f / %.2f s" % [(calm._wind(base) + plus) * Config.DT, (fast._wind(base) + plus) * Config.DT]
	match kind:
		"charge": return w.call(50, 0)
		"gore": return w.call(32, 6)
		"tail": return w.call(30, 9)
		"stomp": return w.call(48, 0)
		"beam": return w.call(60, 0)
		"roar": return "%.2f s" % (Boss.ROAR_AT * Config.DT)
		"call": return "%.2f s" % (80 * Config.DT)
		"rush": return "%.2f s (paw)" % (96 * Config.DT)
		"leap": return "%.2f s (marker)" % (90 * Config.DT)
		"waves": return "rear 0.5 s"
		"balls": return "%.2f s" % (20 * Config.DT)
		"orbs": return "0.5 s launch"
	return "?"
