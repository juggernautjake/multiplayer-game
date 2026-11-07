extends SceneTree
## v0.10.0, the server's side, run offline: the Duel Stone (who it summons before and after the first level-up, one
## challenger at a time), challengers that really fight (a swordsman closes in and hits; an archer leads its shots and
## lands them), kills on challengers levelling the staff, Thunderhorn's health with one and two players, how every
## spell affects him, victory starting the prize, and defeat -> restart (alone, and with two players).
##   Godot --headless --path . --script tools/npc_test.gd   (prints harmless "not inside tree" RPC errors)

var bad := 0
var results := []


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


func _initialize() -> void:
	var net := Net.new()
	root.add_child(net)
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	net.boss_result.connect(func(k): results.append(k))
	for id in [1, 2]:
		net._server_add_player(id, "P%d" % id)
	var a: Net.ServerPlayer = net.players[1]
	var b: Net.ServerPlayer = net.players[2]

	# ---- the Duel Stone's pool
	var p1 := Net.duel_pool(1, 1)
	check(p1.size() == 4 and Weapons.BOW in p1 and Weapons.SLING in p1 and Weapons.SWORD in p1 and Weapons.CLUB in p1 and not Weapons.FISTS in p1,
		"before a level-up the stone summons only archers, slingers, swordsmen and clubbers")
	var p2 := Net.duel_pool(2, 1)
	check(Weapons.STAFF in p2 and Weapons.WAND in p2 and p2.size() == 6, "after the first level-up, wizards too (staff and wand)")
	# ---- pressing it: one challenger at a time
	a.state.pos = Vector3(WorldLayout.DUEL_C.x, 0, WorldLayout.DUEL_C.y + 1.2)
	var before := net.players.size()
	check(net._stone_interact(a), "E at the stone answers")
	check(net.players.size() == before + 1, "a challenger steps out")
	var npc: Net.ServerPlayer = null
	for q in net.players.values():
		if q.npc:
			npc = q
	check(npc != null and npc.state.weapon in p1, "with a weapon from the pool (%s)" % Weapons.NAMES[npc.state.weapon if npc else 0])
	net._stone_interact(a)
	check(net.players.size() == before + 1, "pressing it again while it lives does nothing")
	check(net.can_hurt(1, npc.id) and net.can_hurt(npc.id, 1) and not a.pvp, "challengers and players can hurt each other whatever PvP says")
	# ---- a kill on a challenger with the staff counts toward the staff's level
	var k0: int = a.kills[0]
	net.dmg_src = Weapons.STAFF
	net._damage(npc.id, 500, 1, Vector3(1, 0, 0), 0.0)
	net.dmg_src = -1
	check(a.kills[0] == k0 + 1, "killing a challenger with the staff counts toward its level (%d -> %d)" % [k0, a.kills[0]])
	for t in 200:
		net._server_npcs()
		npc.state.dead = maxi(npc.state.dead - 1, 0)
	check(not net.players.has(npc.id), "a fallen challenger is gone soon after")

	# ---- v0.12.0 tiers rise over a run of duels: tier 1, then 2 after three wins, then 3 at level 3 (or 8 wins)
	var tiers := []
	a.duel_wins = 0
	a.state.staff_lvl = 1
	a.state.wand_lvl = 1
	for k in 9:
		a.state.pos = Vector3(WorldLayout.DUEL_C.x, 0, WorldLayout.DUEL_C.y + 1.2)
		net._stone_interact(a)
		var ch: Net.ServerPlayer = null
		for q in net.players.values():
			if q.npc and q.state.dead == 0:
				ch = q
		tiers.append(ch.ai.difficulty + 1)
		if k == 0 or k == 3:
			check(ch.name.ends_with("(tier %d)" % (ch.ai.difficulty + 1)), "its name tag shows the tier: " + ch.name)
		net._damage(ch.id, 500, 1, Vector3(1, 0, 0), 0.0)
		net.players.erase(ch.id)
	check(tiers == [1, 1, 1, 2, 2, 2, 2, 2, 3], "tiers rise with challengers beaten (%s)" % str(tiers))
	check(Net.duel_tier(0, 2) == 1 and Net.duel_tier(0, 3) == 2 and Net.duel_tier(0, 1) == 0, "and with the staff / wand level (2 -> tier 2, 3 -> tier 3)")
	check(NpcAI.DODGE[0] == 0.0 and NpcAI.SPELL_DODGE[0] == 0.0 and NpcAI.DODGE[1] > 0.0 and NpcAI.DODGE[2] > NpcAI.DODGE[1],
		"no dash-dodging at tier 1; it starts at tier 2 and grows")
	a.duel_wins = 0

	# ---- challengers fight: a swordsman comes for you and lands hits
	a.state = Sim.spawn_state(1)
	a.state.pos = Vector3(60, 0, 60)
	var sw := net.spawn_npc(a, Weapons.SWORD, 2)
	sw.state.pos = Vector3(60, 0, 70)
	var hp0 := a.state.hp
	for t in 900:
		net._server_tick()
		a.state.hp = maxi(a.state.hp, 30)   # keep them standing
		a.state.dead = 0
	var closest := Vector2(sw.state.pos.x - a.state.pos.x, sw.state.pos.z - a.state.pos.z).length()
	check(closest < 4.0, "the swordsman closes in (%.1f m away)" % closest)
	check(net.hits_on(1) > 0 if net.has_method("hits_on") else a.state.hp < hp0 or sw.ai.seq > 0, "and fights")
	net.players.erase(sw.id)
	# an archer at range (v0.11.0: aims where you stand, with a spread, a tell and pauses) hits sometimes, never always
	for walk in [false, true]:
		a.state = Sim.spawn_state(1)
		a.state.pos = Vector3(60, 0, 60)
		var ar := net.spawn_npc(a, Weapons.BOW, 2)
		ar.state.pos = Vector3(60, 0, 74)
		var hits := 0
		var shots := 0
		var last_n := ar.state.swing_n
		var last_hp := a.state.hp
		for t in 1800:
			if walk:   # walking back and forth across its view
				a.state.pos.x = 60 + 6.0 * sin(t * 0.01)
				a.state.vel = Vector3(6.0 * 0.6 * cos(t * 0.01), 0, 0)
			net._server_tick()
			if ar.state.swing_n != last_n:
				shots += 1
				last_n = ar.state.swing_n
			if a.state.hp < last_hp:
				hits += 1
			a.state.hp = Sim.MAX_HP
			last_hp = a.state.hp
			a.state.dead = 0
		check(shots >= 4 and shots <= 30 and hits < shots and (walk or hits >= 1),
			"an archer %s: %d shots in 30 s, %d hit (not every one)" % ["at someone strafing" if walk else "at someone standing", shots, hits])
		net.players.erase(ar.id)
	var ar := {"id": -999}
	net._server_send_roster()
	# ---- v0.12.9 corrupted minions (NpcAI.aggressive) fight on at low health; challengers still back off
	var fought := {}
	for aggro in [false, true]:
		for w in [Weapons.SWORD, Weapons.BOW]:
			a.state = Sim.spawn_state(1)
			a.state.pos = Vector3(60, 0, 60)
			var m := net.spawn_npc(a, w, 2)
			m.ai.aggressive = aggro
			m.state.pos = Vector3(60, 0, 66 if w == Weapons.SWORD else 72)
			var away := 0
			var near_sum := 0.0
			var shots := 0
			var last_n := m.state.swing_n
			for t in 1800:
				m.state.hp = 20   # badly hurt the whole time
				net._server_tick()
				a.state.hp = Sim.MAX_HP
				a.state.dead = 0
				if m.ai._retreat > 0:
					away += 1
				near_sum += Vector2(m.state.pos.x - a.state.pos.x, m.state.pos.z - a.state.pos.z).length()
				if m.state.swing_n != last_n:
					shots += 1
					last_n = m.state.swing_n
			fought["%s %s" % ["minion" if aggro else "challenger", Weapons.NAMES[w]]] = [away, near_sum / 1800.0, shots]
			net.players.erase(m.id)
	print("      low health, 30 s: [ticks backing off, mean distance, swings/shots] %s" % str(fought))
	check(int(fought["challenger Sword"][0]) > 0 and int(fought["challenger Bow"][0]) > 0, "a hurt challenger still backs off now and then")
	check(int(fought["minion Sword"][0]) == 0 and int(fought["minion Bow"][0]) == 0, "a hurt minion never does: it keeps fighting")
	check(float(fought["minion Sword"][1]) < float(fought["challenger Sword"][1]) and int(fought["minion Sword"][2]) > int(fought["challenger Sword"][2]),
		"a minion swordsman stays closer and swings more")
	check(int(fought["minion Bow"][2]) > int(fought["challenger Bow"][2]), "a minion archer shoots more")
	net._server_send_roster()

	# ---- Thunderhorn: health for one and for two players
	var b1 := Boss.new(Vector3.ZERO, 1)
	var b2 := Boss.new(Vector3.ZERO, 2)
	# v0.12.9 Jacob: "45% less health at each stage": 55% of the old 7000 / 11 900 / 16 800
	check(b1.max_hp == 3273 and b2.max_hp == 5564 and Boss.hp_for(3) == 7855, "v0.12.15 his health is 15%% less again: %d alone, %d for two, %d for three (was 3850 / 6545 / 9240)" % [b1.max_hp, b2.max_hp, Boss.hp_for(3)])
	check(b2.max_hp == int(round(Boss.BASE_HP * 1.7)) and b1.max_hp == Boss.BASE_HP and Boss.hp_for(3) == int(round(Boss.BASE_HP * 2.4)), "two players: 1.7x his health, three 2.4x (%d vs %d)" % [b2.max_hp, b1.max_hp])
	# what each spell does to him
	var t1 := Boss.new(Vector3.ZERO, 1)
	t1.state = Boss.S.IDLE
	var h := t1.hp
	t1.hurt(28, 1, "Lightning")
	check(h - t1.hp == 7, "lightning does only a quarter (28 -> %d): he's made of it" % (h - t1.hp))
	h = t1.hp
	t1.hurt(40, 1, "Meteor")
	check(h - t1.hp == 60, "a meteor does half again (40 -> %d)" % (h - t1.hp))
	t1.hurt(10, 1, "Fireball")
	check(t1.burn > 0, "a fireball sets him burning")
	t1.state = Boss.S.CHARGE
	h = t1.hp
	t1.hurt(16, 1, "Earth Spikes")
	check(t1.state == Boss.S.CHARGE and h - t1.hp == 16, "v0.12.0: earth spikes are gone: no weakness, no charge stop (a stray name does plain damage)")
	t1.state = Boss.S.IDLE
	t1.frosted()
	check(t1.slow > 0 and t1.speed_k() < 0.5, "a frost nova slows him a lot")
	var t2 := Boss.new(Vector3.ZERO, 1)
	t2.state = Boss.S.IDLE
	t2.stunned(1000)
	check(t2.state == Boss.S.IDLE and t2.stun_m == 1.0, "v0.12.0: a stun adds a point to his stun meter (no stagger; boss_test has the rest)")
	# a gravity well can't pull him
	net.summon_boss()
	net.boss.state = Boss.S.IDLE
	var bp := net.boss.pos
	net.wells.append([net.server_tick + 100, bp + Vector3(3, 0, 0), 1])
	for t in 30:
		net._server_wells()
	check(net.boss.pos.distance_to(bp) < 0.01, "a gravity well doesn't move him")
	net.wells.clear()

	# ---- victory: his death plays out, then the prize
	results.clear()
	net.boss.state = Boss.S.IDLE
	net._damage(Boss.ID, 100000, 1, Vector3(1, 0, 0), 0.0)
	for t in 200:
		net._server_tick()
	check(net.boss == null and "victory" in results, "beating him ends in victory (the prize screen)")

	# ---- defeat and restart: alone
	for id in net.players.keys().duplicate():
		if id != 1:
			net.players.erase(id)
	results.clear()
	a.state = Sim.spawn_state(1)
	a.state.staff_lvl = 3
	net.summon_boss()
	a.state.dead = Sim.RESPAWN_TICKS
	net._server_tick()
	check(net.defeated and "defeat" in results and net.boss == null, "alone: you die, he's gone, the defeat screen")
	net.ask_restart()
	check(not net.defeated and a.state.dead == 0 and a.state.hp == Sim.MAX_HP and a.state.staff_lvl == 3 and "restart" in results,
		"a key: back on your feet at the spawn with full health, levels kept")
	# ---- two players: only when both are down at once
	net._server_add_player(2, "P2")
	b = net.players[2]
	results.clear()
	net.summon_boss()
	a.state.dead = Sim.RESPAWN_TICKS
	net._server_tick()
	check(not net.defeated and net.boss != null, "two players: one down isn't the end")
	b.state.dead = Sim.RESPAWN_TICKS
	a.state.dead = Sim.RESPAWN_TICKS
	net._server_tick()
	check(net.defeated and "defeat" in results, "both down at once: defeat")
	net.ask_restart()
	check(not net.defeated and a.state.dead == 0 and b.state.dead == 0 and net.boss == null, "and both start again")
	_golem_credit(net, a, b)
	_altar_button(net, a)
	print("%d failed" % bad)
	quit(bad)


## v0.12.0: golems fight for their summoner, and what they do counts for them.
func _golem_credit(net: Net, a: Net.ServerPlayer, b: Net.ServerPlayer) -> void:
	# a golem's kill of a challenger counts toward its summoner's wand level
	var q := net.spawn_npc(a, Weapons.SWORD)
	q.state.hp = 5
	var g := net.golems.spawn(a.id, q.state.pos + Vector3(0, 0, 1), 0.0, net.server_tick)
	var k1: int = a.kills[1]
	net.dmg_src = Weapons.WAND
	net._damage(q.id, Golems.DAMAGE, a.id, Vector3(0, 0, -1), Golems.KNOCK)   # (what Net does with a golem's slam)
	net.dmg_src = -1
	check(q.state.dead > 0 and a.kills[1] == k1 + 1, "a golem's kill of a challenger counts toward its summoner's levels")
	# killing a golem gives nothing
	var q2 := net.spawn_npc(a, Weapons.WAND)
	var g2 := net.golems.spawn(q2.id, q2.state.pos, 0.0, net.server_tick)
	g2.state = Golems.State.IDLE
	g2.hp = 1
	var k2: int = a.kills[1]
	net.dmg_src = Weapons.WAND
	net._damage(-1000 - g2.id, 5, a.id, Vector3.ZERO, 0.0)
	net.dmg_src = -1
	check(g2.state == Golems.State.DIE and a.kills[1] == k2, "killing a golem still gives no credit")
	# a golem's damage to Thunderhorn counts toward the summoner's share
	net.summon_boss()
	net.boss.state = Boss.S.IDLE
	var before := int(net.boss.damage_by.get(a.id, 0))
	net.dmg_src = Weapons.WAND
	net._damage(Boss.ID, Golems.DAMAGE, g.owner, Vector3.ZERO, 0.0)
	net.dmg_src = -1
	check(int(net.boss.damage_by.get(a.id, 0)) > before, "a golem's hits on Thunderhorn count toward its summoner's damage share")
	# hits on the summoner and their golems are remembered (who golems go after; PvP grudges)
	net._damage(a.id, 1, q2.id, Vector3.ZERO, 0.0)
	check(net.golems.harmed(a.id, q2.id, 60), "a challenger hitting the summoner is noted for their golems")
	# a challenger turns on a golem in its face
	var g3 := net.golems.spawn(a.id, q2.state.pos + Vector3(1.5, 0, 0), 0.0, net.server_tick)
	g3.state = Golems.State.IDLE
	var tgt = q2.ai._pick_target(net, q2)
	check(tgt != null and tgt.id == -1000 - g3.id, "a challenger fights a golem that gets in its face")
	net.boss = null


## v0.12.0: the Storm Altar's button is solid; only landing on top presses it; it stays down for the fight.
func _altar_button(net: Net, a: Net.ServerPlayer) -> void:
	net.boss = null
	net.defeated = false
	for id in net.players.keys().duplicate():
		if net.players[id].npc:
			net.players.erase(id)
	a.state = Sim.spawn_state(0)
	a.state.staff_lvl = 3
	var c := Vector3(WorldLayout.ALTAR_C.x, 0, WorldLayout.ALTAR_C.y)
	a.state.pos = c + Vector3(WorldLayout.ALTAR_BTN_R + 1.5, 0, 0)
	var closest := INF
	for k in 90:   # walking into its side
		Sim.step(a.state, Sim.PlayerInput.new(k, Sim.Btn.LEFT, 0.0, 0.0, Weapons.STAFF, 0, 0.0, 0.0))
		net._server_altar()
		closest = minf(closest, Vector2(a.state.pos.x - c.x, a.state.pos.z - c.z).length())
	check(net.boss == null and closest >= WorldLayout.ALTAR_BTN_R, "walking into the button's side doesn't press it (kept %.2f m from its middle)" % closest)
	a.state.pos = c + Vector3(0, 2.5, 0)   # dropping onto it from a jump
	a.state.vel = Vector3.ZERO
	a.state.grounded = false
	a.air = true
	for k in 60:
		Sim.step(a.state, Sim.PlayerInput.new(k, 0, 0.0, 0.0, Weapons.STAFF, 0, 0.0, 0.0))
		net._server_altar()
	check(net.boss != null and WorldLayout.altar_pressed, "landing on top presses it: Thunderhorn comes")
	check(absf(a.state.pos.y - WorldLayout.ALTAR_DOWN) < 0.02 and a.state.grounded, "standing on the pressed button (feet at %.2f m)" % a.state.pos.y)
	net.boss = null
	net._server_altar()
	check(not WorldLayout.altar_pressed, "after the fight it comes back up")
