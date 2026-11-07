extends SceneTree
## v0.12.3 the Duel Stone's corruption cutscene (scripts/cutscene.gd), the server's side, run offline:
##   it starts the first time Thunderhorn drops below 60% and never again that fight; it waits for a Storm Leap
##   sequence or a daze to end; it raises exactly six minions (sword, club, bow, slingshot, staff wizard, wand wizard)
##   at the fight's tier with level-1 wizards; nobody can act or be hurt while it plays (players, minions, him) and
##   everyone can act again after; the stone is corrupted (summons nobody) until the fight ends; minion kills count
##   toward levels; his death fells every minion and they dissolve; a defeat and restart clears them, cleanses the stone
##   and arms the cutscene again; the boss state carries it to clients (and late joiners).
##   Godot --headless --path . --script tools/cutscene_test.gd   (prints harmless "not inside tree" RPC errors)

var bad := 0
var results := []


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


## One server tick, with each listed player holding `buttons` (their inputs queued like a client's).
func step(net: Net, buttons := 0, ids := [1]) -> void:
	for id in ids:
		if net.players.has(id):
			var p: Net.ServerPlayer = net.players[id]
			var inp := Sim.PlayerInput.new(p.last_applied + 1 + p.queue.size(), buttons, 0.0, 0.0, p.state.weapon, net.server_tick, 0.0, 0.0)
			p.queue[inp.seq] = inp
			p.primed = true
	net._server_tick()


func keep_alive(net: Net) -> void:
	for p: Net.ServerPlayer in net.players.values():
		if not p.npc:
			p.state.hp = Sim.MAX_HP
			p.state.dead = 0


func minions(net: Net) -> Array:
	return net._minions()


func _initialize() -> void:
	var net := Net.new()
	root.add_child(net)
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	net.boss_result.connect(func(k): results.append(k))
	net._server_add_player(1, "P1")
	var a: Net.ServerPlayer = net.players[1]
	a.state.staff_lvl = 3
	a.state.owned = 0b1111111
	a.state.weapon = Weapons.STAFF

	# ---- a fight: nothing above 60%
	net.summon_boss()
	var b := net.boss
	b.leaps = Boss.LEAP_MAX   # (no Storm Leaps in this fight: they would put the cutscene off; _defer_tests has that)
	check(b.cut_on and not b.cut_done, "a new fight arms the cutscene")
	a.state.pos = Boss.arena_c() + Vector3(0, 0, 14)
	for t in 200:   # his entrance
		step(net)
		keep_alive(net)
	b.hp = int(b.max_hp * 0.61)
	for t in 30:
		step(net)
		keep_alive(net)
	check(b.state != Boss.S.CUTSCENE and not b.cut_done, "at 61% nothing happens")

	# ---- below 60%: it starts as soon as he's free (v0.12.9: never in the middle of an attack or its recovery)
	var was := b.state
	var waited := 0
	var last := b.state
	var free_then := false
	b.hp = int(b.max_hp * 0.59)
	while b.state != Boss.S.CUTSCENE and waited < 900:
		last = b.state
		free_then = b.free_now()
		step(net)
		keep_alive(net)
		waited += 1
	check(b.state == Boss.S.CUTSCENE and b.cut_done and net.cutscene_on() and free_then and waited < 600,
		"below 60%% the cutscene starts once he's free (he was %s; %.1f s later, from %s)" % [Boss.S.keys()[was], waited / 60.0, Boss.S.keys()[last]])
	check(b.rings.is_empty() and b.balls.is_empty() and b.orbs.is_empty() and net.pending_spells.is_empty(), "rings, balls, orbs and pending spells are cleared")
	var pk := b.pack()
	check(int(pk[0]) == Boss.S.CUTSCENE and int(pk[1]) == b.t, "the boss state carries it (state and film time) to every client, late joiners too")
	net.boss_state(net.server_tick, pk)
	check(net.cut_client, "a client reading that state knows the cutscene is on (and sends no buttons)")

	# ---- nobody acts or gets hurt
	var p0 := a.state.pos
	var hp0 := a.state.hp
	var bhp := b.hp
	net._damage(1, 50, Boss.ID, Vector3.FORWARD, 5.0)
	net.dmg_src = Weapons.STAFF
	net._damage(Boss.ID, 500, 1, Vector3.FORWARD, 0.0)
	net.dmg_src = -1
	check(a.state.hp == hp0 and b.hp == bhp, "players and Thunderhorn are invulnerable (player %d, boss %d)" % [a.state.hp, b.hp])
	var g := net.golems.spawn(1, a.state.pos + Vector3(2, 0, 0), 0.0, net.server_tick)
	var ghp := g.hp
	net._damage(-1000 - g.id, 30, Boss.ID, Vector3.FORWARD, 0.0)
	check(g.hp == ghp, "golems are invulnerable")
	var moved := 0.0
	var b_from := b.pos
	var b_max := 0.0
	var spawned_at := -1
	var flag_at := -1
	var stone_used := false
	var minion_hit_ok := true
	var under := true
	var rose := true
	for t in Cutscene.LEN - 2:
		step(net, Sim.Btn.FORWARD | Sim.Btn.ATTACK | Sim.Btn.JUMP)
		moved = maxf(moved, Vector2(a.state.pos.x - p0.x, a.state.pos.z - p0.z).length())
		b_max = maxf(b_max, b.pos.distance_to(b_from))
		if spawned_at < 0 and not minions(net).is_empty():
			spawned_at = b.t
			for q in minions(net):
				under = under and q.state.pos.y < -1.5
		if flag_at < 0 and int(b.pack()[8]) & 128 != 0:
			flag_at = b.t
		if b.t == Cutscene.SNAP_AT - 5:
			for q in minions(net):
				rose = rose and absf(q.state.pos.y) < 0.01
				var h: int = q.state.hp
				net._damage(q.id, 40, 1, Vector3.FORWARD, 0.0)
				minion_hit_ok = minion_hit_ok and q.state.hp == h
	check(b.state == Boss.S.CUTSCENE, "still playing near the end (t %d of %d)" % [b.t, Cutscene.LEN])
	check(moved < 0.05, "players holding keys don't move or act during it (moved %.2f m)" % moved)
	check(b_max > 10.0 and b.pos.distance_to(Cutscene.stand_spot(b.cut_from)) < 0.01, "he gallops to the Duel Stone (%.0f m) and stands by it" % b_max)
	check(flag_at == Cutscene.CORRUPT_AT, "the stone turns corrupted (status bit 128) at the slam (t %d)" % flag_at)
	check(spawned_at == Cutscene.RISE_AT and under, "the minions appear at t %d, under the ground" % spawned_at)
	check(rose, "and have risen by the snap")
	check(minion_hit_ok, "minions are invulnerable during it too")
	var ms := minions(net)
	var ws := ms.map(func(q): return q.state.weapon)
	ws.sort()
	var want := Cutscene.WEAPONS.duplicate()
	want.sort()
	check(ms.size() == 6 and ws == want, "exactly six minions: sword, club, bow, slingshot, staff and wand (%s)" % str(ms.map(func(q): return Weapons.NAMES[q.state.weapon])))
	var ok_kit := true
	for q in ms:
		ok_kit = ok_kit and q.npc and q.minion and q.ai != null and q.ai.difficulty == Net.MINION_TIER_SOLO and q.state.staff_lvl == 1 and q.state.wand_lvl == 1 \
			and q.name.begins_with("Corrupted") and q.name.ends_with("(tier %d)" % (Net.MINION_TIER_SOLO + 1))
	check(ok_kit, "challenger brains at tier %d alone, wizards at level 1 (level-1 spells): %s" % [Net.MINION_TIER_SOLO + 1, ms[0].name if ms.size() > 0 else "-"])
	check(NpcAI.kit(Weapons.WAND).size() == 4 and NpcAI.MAX_GOLEMS == 3, "the wand wizard's kit is level 1 and it keeps at most 3 golems")
	check(ms.size() > 0 and net.can_hurt(ms[0].id, 1) and net.can_hurt(1, ms[0].id) and not net.can_hurt(ms[0].id, ms[1].id), "minions fight players whatever PvP says (and never each other)")
	# the stone can't be used while corrupted
	var before := net.players.size()
	a.state.pos = Vector3(WorldLayout.DUEL_C.x, 0, WorldLayout.DUEL_C.y + 1.2)
	stone_used = net._stone_interact(a)
	check(stone_used and net.players.size() == before, "the corrupted Duel Stone summons no challenger")
	a.state.pos = p0
	var snap_face := true
	for q in ms:
		var f := Vector2(-sin(q.state.yaw), -cos(q.state.yaw))
		var to := Vector2(a.state.pos.x - q.state.pos.x, a.state.pos.z - q.state.pos.z).normalized()
		snap_face = snap_face and f.dot(to) > 0.95
	check(snap_face, "at the snap they turn to face the players")

	# ---- the end: everyone acts again, he's back to fighting, the minions think
	for t in 6:
		step(net)
		keep_alive(net)
	check(b.state != Boss.S.CUTSCENE and not net.cutscene_on(), "it ends after %.0f s" % (Cutscene.LEN * Config.DT))
	net.boss_state(net.server_tick, b.pack())
	check(not net.cut_client, "and clients are told")
	var p1 := a.state.pos
	for t in 30:
		step(net, Sim.Btn.FORWARD)
		keep_alive(net)
	check(Vector2(a.state.pos.x - p1.x, a.state.pos.z - p1.z).length() > 1.0, "players can move again (%.1f m in 0.5 s)" % Vector2(a.state.pos.x - p1.x, a.state.pos.z - p1.z).length())
	var m0: Net.ServerPlayer = ms[0]
	var mpos := m0.state.pos
	for t in 120:
		step(net)
		keep_alive(net)
	check(m0.state.pos.distance_to(mpos) > 1.0 or m0.ai.seq > 0, "the minions come for them (moved %.1f m)" % m0.state.pos.distance_to(mpos))
	var h0 := a.state.hp
	net._damage(1, 10, m0.id, Vector3.FORWARD, 0.0)
	check(a.state.hp == h0 - 10, "and can hurt them now")
	check(net.golems.foe(1, m0.id, {}) and not net.golems.foe(m0.id, ms[1].id, {}), "players' golems fight them (whatever PvP says)")
	# a kill on a minion counts toward levels, like a challenger's
	var k0: int = a.kills[0]
	net.dmg_src = Weapons.STAFF
	net._damage(ms[1].id, 999, 1, Vector3.FORWARD, 0.0)
	net.dmg_src = -1
	check(a.kills[0] == k0 + 1, "killing a minion with the staff counts toward its level (%d -> %d)" % [k0, a.kills[0]])
	# never twice
	b.hp = int(b.max_hp * 0.3)
	for t in 60:
		step(net)
		keep_alive(net)
	check(b.state != Boss.S.CUTSCENE and minions(net).size() <= 6, "it never plays twice in a fight (at 30%%: %s)" % Boss.S.keys()[b.state])
	# ---- his death fells every minion; they dissolve
	net._damage(Boss.ID, 999999, 1, Vector3.FORWARD, 0.0)
	step(net)
	var all_down := true
	for q in minions(net):
		all_down = all_down and q.state.dead > 0
	check(b.state == Boss.S.DEATH and all_down, "killing Thunderhorn kills all his minions")
	for t in 220:
		step(net)
		keep_alive(net)
	check(minions(net).is_empty() and net.boss == null and "victory" in results, "they dissolve (gone) and it's a victory")

	_defer_tests(net, a)
	_restart_tests(net, a)
	print("%d failed" % bad)
	quit(bad)


## It waits for a Storm Leap sequence, and for a daze, to end.
func _defer_tests(net: Net, a: Net.ServerPlayer) -> void:
	net.summon_boss()
	var b := net.boss
	a.state = Sim.spawn_state(1)
	a.state.staff_lvl = 3
	a.state.pos = Boss.arena_c() + Vector3(0, 0, 14)
	for t in 200:
		step(net)
		keep_alive(net)
	b._start_leap([[1, a.state.pos, true, false, 100]])
	b.hp = int(b.max_hp * 0.58)
	var during := false
	var started_after := -1
	for t in 3000:
		var seq := b.in_sequence()
		step(net)
		keep_alive(net)
		if b.state == Boss.S.CUTSCENE and seq and b.t <= 1:
			during = true
		if b.state == Boss.S.CUTSCENE and started_after < 0:
			started_after = t
		if started_after >= 0:
			break
	check(not during and started_after > 300, "below 60%% in a Storm Leap: it waits for the sequence to end (started %d ticks later)" % started_after)
	net._damage(Boss.ID, 999999, 1, Vector3.FORWARD, 0.0)   # (invulnerable now; end the fight the quick way)
	net.boss = null
	net._clear_minions()
	# dazed
	net.summon_boss()
	b = net.boss
	b.leaps = Boss.LEAP_MAX
	for t in 200:
		step(net)
		keep_alive(net)
	b._daze()
	b.hp = int(b.max_hp * 0.58)
	var dazed_cut := false
	var got := -1
	for t in Boss.STUN_TICKS + 60:
		var dz := b.state == Boss.S.DAZED
		step(net)
		keep_alive(net)
		if dz and b.state == Boss.S.CUTSCENE:
			dazed_cut = b.t > 0   # (straight from the daze to the film would skip his getting up)
		if b.state == Boss.S.CUTSCENE and got < 0:
			got = t
	check(got >= Boss.STUN_TICKS - 2 and not dazed_cut, "while he's dazed it waits until he's up (started at %d, the daze lasts %d)" % [got, Boss.STUN_TICKS])
	net.boss = null
	net._clear_minions()


## A defeat and restart: minions gone, the stone cleansed, and the next fight arms it again.
func _restart_tests(net: Net, a: Net.ServerPlayer) -> void:
	net._server_add_player(2, "P2")
	var c: Net.ServerPlayer = net.players[2]
	net.summon_boss()
	var b := net.boss
	b.leaps = Boss.LEAP_MAX
	a.state = Sim.spawn_state(1)
	a.state.staff_lvl = 3
	for t in 200:
		step(net, 0, [1, 2])
		keep_alive(net)
	b.hp = int(b.max_hp * 0.5)
	for t in Cutscene.LEN + 10:
		step(net, 0, [1, 2])
		keep_alive(net)
	var ms := net._minions()
	check(ms.size() == 6 and ms[0].ai.difficulty == Net.MINION_TIER_SOLO + 1, "with two fighters the minions are a tier higher (tier %d)" % (ms[0].ai.difficulty + 1 if ms.size() > 0 else 0))
	results.clear()
	a.state.dead = Sim.RESPAWN_TICKS
	c.state.dead = Sim.RESPAWN_TICKS
	net._server_tick()
	check(net.defeated and "defeat" in results and net._minions().is_empty(), "a defeat removes every minion")
	net.ask_restart()
	check(not net.defeated and "restart" in results and net.boss == null, "and the restart")
	a.state.pos = Vector3(WorldLayout.DUEL_C.x, 0, WorldLayout.DUEL_C.y + 1.2)
	var before := net.players.size()
	net._stone_interact(a)
	check(net.players.size() == before + 1, "the Duel Stone is cleansed: it summons challengers again")
	for id in net.players.keys().duplicate():
		if net.players[id].npc:
			net.players.erase(id)
	net.boss_state(net.server_tick, [])
	check(not net.cut_client, "and clients see the fight is over")
	net.summon_boss()
	net.boss.leaps = Boss.LEAP_MAX
	check(net.boss.cut_on and not net.boss.cut_done, "a new fight arms the cutscene again")
	for t in 200:
		step(net, 0, [1, 2])
		keep_alive(net)
	net.boss.hp = int(net.boss.max_hp * 0.59)
	step(net, 0, [1, 2])
	check(net.boss.state == Boss.S.CUTSCENE, "and it plays again in the new fight")
	net.boss = null
	net._clear_minions()
