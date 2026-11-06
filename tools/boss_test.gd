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

	# ---- the rush: dash sideways in time and he misses; otherwise launched, knocked down, then up again
	for dodge in [true, false]:
		net.summon_boss()
		var b: Boss = net.boss
		b.state = Boss.S.SLAMS
		b.t = 139
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

	print("%d failed" % bad)
	quit(bad)


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
