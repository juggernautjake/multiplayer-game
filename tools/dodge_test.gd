extends SceneTree
## v0.12.0 challengers learn to dash: by tier, how often a challenger side-dashes out of a lightning warning ring and
## out of Thunderhorn's charge line (more often at higher tiers, never every time, after a reaction delay); and the
## archers and slingers (v0.11.0, verified): they aim at where you stand now (no lead), their spread shrinks and they
## start draws a little more often with each tier.
##   Godot --headless --path . --script tools/dodge_test.gd   (prints harmless "not inside tree" RPC errors)

var bad := 0


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


## One trial: a fresh challenger of this tier, a threat set up by `setup`, `ticks` of its brain. -> [dashed, tick].
func trial(net: Net, a: Net.ServerPlayer, tier: int, setup: Callable, ticks: int) -> Array:
	var q := net.spawn_npc(a, Weapons.SWORD, tier)
	q.state.pos = Vector3(100, 0, 100)
	q.state.yaw = 0.0
	a.state.pos = Vector3(100, 0, 125)
	setup.call(q)
	var out := [false, -1]
	for t in ticks:
		net.server_tick += 1
		var inp := q.ai.think(net, q)
		if inp.buttons & Sim.Btn.DASH:
			out = [true, t]
			break
		Sim.step(q.state, inp)
	net.players.erase(q.id)
	return out


func _initialize() -> void:
	var net := Net.new()
	root.add_child(net)
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	net._server_add_player(1, "P1")
	var a: Net.ServerPlayer = net.players[1]
	net.server_tick = 1000

	check(NpcAI.SPELL_DODGE[0] < NpcAI.SPELL_DODGE[1] and NpcAI.SPELL_DODGE[1] < NpcAI.SPELL_DODGE[2] and NpcAI.SPELL_DODGE[2] < 1.0
		and NpcAI.SPELL_REACT[0] > NpcAI.SPELL_REACT[2], "spell / charge dodging: likelier and quicker by tier, never certain")

	# ---- lightning warning rings under it
	var rates := []
	var reacts := []
	for tier in 3:
		var n := 0
		var react_sum := 0
		for k in 60:
			var setup := func(q: Net.ServerPlayer) -> void:
				net.pending_spells = [[net.server_tick + 30, "lightning", q.state.pos + Vector3(0.8, 0, 0.5), 1]]
			var r := trial(net, a, tier, setup, 28)
			if r[0]:
				n += 1
				react_sum += int(r[1])
		rates.append(float(n) / 60.0)
		reacts.append(float(react_sum) / maxf(n, 1))
	net.pending_spells = []
	print("      lightning ring dodged: %s, after %s ticks on average" % [str(rates), str(reacts)])
	check(rates[0] < rates[2] and rates[1] < rates[2] and rates[2] < 0.95 and rates[2] > 0.35,
		"challengers dash out of lightning rings more at higher tiers, never always (%.0f%% / %.0f%% / %.0f%%)" % [rates[0] * 100, rates[1] * 100, rates[2] * 100])
	check(reacts[2] >= 3.0, "and only after a reaction delay (%.0f ticks at the top tier)" % reacts[2])

	# ---- Thunderhorn's charge coming down a line through it
	net.summon_boss()
	var b := net.boss
	var crates := []
	for tier in 3:
		var n := 0
		for k in 60:
			var setup := func(q: Net.ServerPlayer) -> void:
				b.state = Boss.S.CHARGE
				b.pos = q.state.pos + Vector3(0.6, 0, -14)
				b.charge_dir = Vector2(0, 1)
			var r := trial(net, a, tier, setup, 30)
			if r[0]:
				n += 1
		crates.append(float(n) / 60.0)
	print("      charge dodged: %s" % str(crates))
	check(crates[0] < crates[2] and crates[2] < 0.95 and crates[2] > 0.35, "they side-step his charge more at higher tiers, never always")
	var side := func(q: Net.ServerPlayer) -> void:
		b.state = Boss.S.CHARGE
		b.pos = q.state.pos + Vector3(8.0, 0, -14)   # a charge well off to the side: nothing to dodge
		b.charge_dir = Vector2(0, 1)
	var none := 0
	for k in 30:
		if trial(net, a, 2, side, 30)[0]:
			none += 1
	check(none == 0, "a charge that isn't coming at them: no dash")
	net.boss = null

	# ---- archers: no lead; spread down and draws more often by tier (v0.11.0)
	var q := net.spawn_npc(a, Weapons.BOW, 1)
	a.state.pos = Vector3(100, 0, 120)
	a.state.vel = Vector3(6, 0, 0)
	q.state.pos = Vector3(100, 0, 100)
	var w := Weapons.get_data(Weapons.BOW)
	var aim: Array = q.ai._lead(q.state, a, Weapons.shot(Weapons.BOW, int(w.draw))[0], float(w.gravity), 0.0)
	check((aim[2] as Vector3).distance_to(a.state.pos + Vector3(0, 1.1, 0)) < 0.01, "archers aim at where you stand now, not where you're going")
	check(NpcAI.SHOT_ERR[0] > NpcAI.SHOT_ERR[1] and NpcAI.SHOT_ERR[1] > NpcAI.SHOT_ERR[2] and NpcAI.SHOT_ERR[2] > 0.0,
		"their spread shrinks with tier but never to nothing (%s)" % str(NpcAI.SHOT_ERR))
	check(NpcAI.SHOT_START[0] < NpcAI.SHOT_START[1] and NpcAI.SHOT_START[1] < NpcAI.SHOT_START[2] and NpcAI.SHOT_HOLD[0] > NpcAI.SHOT_HOLD[2],
		"and they draw a little more often (%s) with a shorter hold (%s)" % [str(NpcAI.SHOT_START), str(NpcAI.SHOT_HOLD)])
	print("%d failed" % bad)
	quit(1 if bad > 0 else 0)
